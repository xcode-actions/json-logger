import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

@preconcurrency import GenericJSON
import Logging



/**
 A logger that logs it’s messages to stdout in the JSON format, one log per line.
 
 The line separator is actually customizable, and can be any sequence of bytes.
 By default it’s “`\n`”.
 
 The separator customization allows you to choose 
  a prefix for the JSON payload (defaults to `[]`),
  a suffix too (defaults to `[]` too),
  and an inter-JSON separator (defaults to `[0x0a]`, which is a UNIX newline).
 For instance if there are two messages logged, you’ll get the following written to the fd:
 ```
 prefix JSON1 suffix separator prefix JSON2 suffix
 ```
 
 This configuration is interesting mostly to generate `json-seq` stream.
 To do this, set the inter-JSON separator to `[]`, the prefix to `[0x1e]` and the suffix to `[0x0a]`,
  or use the convenience ``JSONLogger/forJSONSeq()``.
 
 Finally, another interesting configuration is to set the separator to `[0xff]` or `[0xfe]`.
 These bytes should not appear in valid UTF-8 strings and should be able to be used to separate JSON payloads.
 (Note I’m not sure why `json-seq` does not do that; there must be a good reason, though.
 Probably because the resulting output would not be valid UTF-8 anymore.)
 
 The output file descriptor is also customizable and is `stdout` by default. */
public struct JSONLogger : LogHandler {
	
	public var logLevel: Logger.Level = .info
	
	public var metadata: Logger.Metadata = [:] {
		didSet {jsonMetadataCache = jsonMetadata(metadata)}
	}
	public var metadataProvider: Logger.MetadataProvider?
	
	public let outputFileDescriptor: FileDescriptor
	public let lineSeparator: Data
	public let prefix: Data
	public let suffix: Data
	
	/**
	 If `true`, the `Encodable` properties in the metadata will be encoded and kept structured in the resulting log line.
	 If the encoding fails or this property is set to `false` the String value will be used. */
	public var tryEncodingStringConvertibles: Bool
	
	public static func forJSONSeq(on fd: FileDescriptor = .standardError, metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider) -> Self {
		return Self(fd: fd, lineSeparator: Data(), prefix: Data([0x1e]), suffix: Data([0x0a]), metadataProvider: metadataProvider)
	}
	
	public init(fd: FileDescriptor = .standardError, lineSeparator: Data = Data("\n".utf8), prefix: Data = Data(), suffix: Data = Data(), tryEncodingStringConvertibles: Bool = true, metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider) {
		self.outputFileDescriptor = fd
		self.lineSeparator = lineSeparator
		self.prefix = prefix
		self.suffix = suffix
		self.tryEncodingStringConvertibles = tryEncodingStringConvertibles
		
		self.metadataProvider = metadataProvider
	}
	
	public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
		get {metadata[metadataKey]}
		set {metadata[metadataKey] = newValue}
	}
	
	public func log(level: Logger.Level, message: Logger.Message, metadata logMetadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
		let effectiveJSONMetadata: JSON
		if let m = mergedMetadata(with: logMetadata) {effectiveJSONMetadata = jsonMetadata(m)}
		else                                         {effectiveJSONMetadata = jsonMetadataCache}
		
		/* We compute the data to print outside of the lock. */
		let line = LogLine(level: level, message: message.description, metadata: effectiveJSONMetadata,
								 source: source, file: file, function: function, line: line)
		let jsonLine: Data
		do    {jsonLine = try JSONEncoder().encode(line)}
		catch {
			/* The encoding should never fail.
			 * But what if it does? */
			jsonLine = Data((
				#"{"# +
					#""level":"\#(level.rawValue.safifyForJSON())","# +
					#""message":"MANGLED LOG MESSAGE (see JSONLogger doc) -- \#(line.message.safifyForJSON())","# +
					#""metadata":{"# +
						#""JSONLogger.LogInfo":"Original metadata removed (see JSONLogger doc)","# +
						#""JSONLogger.LogError":"\#(String(describing: error).safifyForJSON())""# +
					#"},"# +
					#""source":"\#(source.safifyForJSON())","# +
					#""file":"\#(file.safifyForJSON())","# +
					#""function":"\#(function.safifyForJSON())","# +
					#""line":\#(line)"# +
				#"}"#
			).utf8)
		}
		let dataNoSeparator = prefix + jsonLine + suffix
		
		/* We lock, because the writeAll function might split the write in more than 1 write
		 *  (if the write system call only writes a part of the data).
		 * If another part of the program writes to fd, we might get interleaved data,
		 *  because they cannot be aware of our lock (and we cannot be aware of theirs if they have one). */
		JSONLogger.lock.withLock{
			let prefix: Data
			if Self.isFirstLog {prefix = Data(); Self.isFirstLog = false}
			else               {prefix = lineSeparator}
			/* Is there a better idea than silently drop the message in case of fail? */
			_ = try? outputFileDescriptor.writeAll(prefix + dataNoSeparator)
		}
	}
	
	/* Do _not_ use os_unfair_lock, apparently it is bad in Swift:
	 *  <https://twitter.com/grynspan/status/1392080373752995849>. */
	private static var lock = NSLock()
	private static var isFirstLog = true
	
	private var jsonMetadataCache: JSON = .object([:])
	
}


/* Metadata handling. */
extension JSONLogger {
	
	/**
	 Merge the logger’s metadata, the provider’s metadata and the given explicit metadata and return the new metadata.
	 If the provider’s metadata and the explicit metadata are `nil`, returns `nil` to signify the current `jsonMetadataCache` can be used. */
	private func mergedMetadata(with explicit: Logger.Metadata?) -> Logger.Metadata? {
		var metadata = metadata
		let provided = metadataProvider?.get() ?? [:]
		
		guard !provided.isEmpty || !((explicit ?? [:]).isEmpty) else {
			/* All per-log-statement values are empty or not set: we return nil. */
			return nil
		}
		
		if !provided.isEmpty {
			metadata.merge(provided, uniquingKeysWith: { _, provided in provided })
		}
		if let explicit = explicit, !explicit.isEmpty {
			metadata.merge(explicit, uniquingKeysWith: { _, explicit in explicit })
		}
		return metadata
	}
	
	private func jsonMetadata(_ metadata: Logger.Metadata) -> JSON {
		.object(metadata.mapValues(jsonMetadataValue(_:)))
	}
	
	private func jsonMetadataValue(_ metadataValue: Logger.MetadataValue) -> JSON {
		return switch metadataValue {
			case let .string(s):              .string(s)
			case let .array(array):           .array (array     .map      (jsonMetadataValue(_:)))
			case let .dictionary(dictionary): .object(dictionary.mapValues(jsonMetadataValue(_:)))
			case let .stringConvertible(s):
				if tryEncodingStringConvertibles, let c = s as? any Encodable, let encoded = try? JSON(encodable: c) {
					encoded
				} else {
					.string(s.description)
				}
		}
		
	}
	
}
