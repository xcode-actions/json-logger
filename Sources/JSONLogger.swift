import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

import GenericJSON
import Logging



/**
 A logger that logs it’s messages to stdout in the JSON format, one log per line.
 
 The end of line separator is actually customizable, and can be any sequence of bytes.
 By default it’s “`\n`”.
 
 The separator customization allows you to choose 
  a prefix for the JSON payload (defaults to `[]`),
  a suffix too (defaults to `[0x0a]`, aka. a single UNIX newline),
  and an inter-JSON separator (defaults to `[]`, same as the prefix).
 For instance if there are two messages logged, you’ll get the following written to the fd:
 ```
 prefix JSON1 suffix separator prefix JSON2 suffix
 ```
 
 An interesting configuration is setting the prefix to `[0x1e]` and the suffix to `[0x0a]`, which generates a `json-seq` stream.
 You can use the ``forJSONSeq(on:label:metadataProvider:)`` convenience to get this configuration directly.
 
 Another interesting configuration is to set the inter-JSON separator to `[0xff]` or `[0xfe]` (or both).
 These bytes should not appear in valid UTF-8 strings and should be able to be used to separate JSON payloads.
 (Note I’m not sure why `json-seq` does not do that but there must be a good reason.
 Probably because the resulting output would not be valid UTF-8 anymore.)
 
 The output file descriptor is also customizable and is `stdout` by default.
 
 Finally, the JSON coders are customizable too.
 There is a `JSONEncoder` that create the JSON from a ``LogLine`` entry, which is the struct created internally for any logged line.
 There is also an optional `(JSONEncoder, JSONDecoder)` tuple which is used specifically to get structured metadata from any object in the metadata.
 
 All of the JSON output from this logger should be parsable as a ``LogLine`` by a `JSONDecoder` matching the config of the `JSONEncoder` set in the config of the logger. */
public struct JSONLogger : LogHandler {
	
	public static let defaultJSONEncoder: JSONEncoder = {
		let res = JSONEncoder()
		res.outputFormatting = [.withoutEscapingSlashes]
		res.keyEncodingStrategy = .useDefaultKeys
		res.dateEncodingStrategy = .iso8601
		res.dataEncodingStrategy = .base64
		res.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
		return res
	}()
	
	public static let defaultJSONCodersForStringConvertibles: (JSONEncoder, JSONDecoder) = {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.withoutEscapingSlashes]
		encoder.keyEncodingStrategy = .useDefaultKeys
		encoder.dateEncodingStrategy = .iso8601
		encoder.dataEncodingStrategy = .base64
		encoder.nonConformingFloatEncodingStrategy = .throw
		let decoder = JSONDecoder()
		/* #if os(Darwin) is not available on this version of the compiler. */
#if !os(Linux)
		if #available(macOS 12.0, tvOS 15.0, iOS 15.0, watchOS 8.0, *) {
			decoder.allowsJSON5 = false
		}
#endif
		decoder.keyDecodingStrategy = .useDefaultKeys
		decoder.dateDecodingStrategy = .iso8601
		decoder.dataDecodingStrategy = .base64
#if !os(Linux)
		if #available(macOS 12.0, tvOS 15.0, iOS 15.0, watchOS 8.0, *) {
			decoder.assumesTopLevelDictionary = false
		}
#endif
		decoder.nonConformingFloatDecodingStrategy = .throw
		return (encoder, decoder)
	}()
	
	public var logLevel: Logger.Level = .info
	
	public var metadata: Logger.Metadata = [:] {
		didSet {jsonMetadataCache = jsonMetadata(metadata)}
	}
	public var metadataProvider: Logger.MetadataProvider?
	
	public let label: String
	
	public let outputFileDescriptor: FileDescriptor
	public let lineSeparator: Data
	public let prefix: Data
	public let suffix: Data
	
	public let jsonEncoder: JSONEncoder
	/**
	 If non-`nil`, the `Encodable` stringConvertible properties in the metadata will be encoded as `JSON` using the `JSONEncoder` and `JSONDecoder`.
	 If the encoding fails or this property is set to `nil` the String value will be used. */
	public let jsonCodersForStringConvertibles: (JSONEncoder, JSONDecoder)?
	
	public static func forJSONSeq(
		on fd: FileDescriptor = .standardOutput,
		label: String,
		jsonEncoder: JSONEncoder = Self.defaultJSONEncoder,
		jsonCodersForStringConvertibles: (JSONEncoder, JSONDecoder) = Self.defaultJSONCodersForStringConvertibles,
		metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider
	) -> Self {
		return Self(
			label: label,
			fd: fd,
			lineSeparator: Data(), prefix: Data([0x1e]), suffix: Data([0x0a]),
			jsonEncoder: jsonEncoder,
			jsonCodersForStringConvertibles: jsonCodersForStringConvertibles,
			metadataProvider: metadataProvider
		)
	}
	
	public init(
		label: String,
		fd: FileDescriptor = .standardOutput,
		lineSeparator: Data = Data(), prefix: Data = Data(), suffix: Data = Data("\n".utf8),
		jsonEncoder: JSONEncoder = Self.defaultJSONEncoder,
		jsonCodersForStringConvertibles: (JSONEncoder, JSONDecoder) = Self.defaultJSONCodersForStringConvertibles,
		metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider
	) {
		self.label = label
		self.outputFileDescriptor = fd
		self.lineSeparator = lineSeparator
		self.prefix = prefix
		self.suffix = suffix
		self.jsonEncoder = jsonEncoder
		self.jsonCodersForStringConvertibles = jsonCodersForStringConvertibles
		
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
		let logLine = LogLine(level: level, message: message.description, metadata: effectiveJSONMetadata, date: Date(),
									 label: label, source: source, file: file, function: function, line: line)
		let jsonLine: Data
		do    {jsonLine = try jsonEncoder.encode(logLine)}
		catch {
			/* If encoding the line failed, we fallback to a manual building of the JSON.
			 * For the date, we cannot know how the client would want the date to be encoded as we cannot use the JSONEncoder,
			 *  so we use a special property LogLine will use when the date property is not present.
			 * This “date-1970” contains the date, represented using the time interval since 1970. */
			jsonLine = Data((
				#"{"# +
					#""level":"\#(level.rawValue.safifyForJSON())","# +
					#""message":"MANGLED LOG MESSAGE (see JSONLogger doc) -- \#(logLine.message.safifyForJSON())","# +
					#""metadata":{"# +
						#""JSONLogger.LogInfo":"Original metadata removed (see JSONLogger doc)","# +
						#""JSONLogger.LogError":"\#(String(describing: error).safifyForJSON())""# +
					#"},"# +
					#""date-1970":\#(logLine.date.timeIntervalSince1970),"# +
					#""label":"\#(label.safifyForJSON())","# +
					#""source":"\#(source.safifyForJSON())","# +
					#""file":"\#(file.safifyForJSON())","# +
					#""function":"\#(function.safifyForJSON())","# +
					#""line":\#(line)"# +
				#"}"#
			).utf8)
		}
		let lineDataNoSeparator = prefix + jsonLine + suffix
		
		/* We lock, because the writeAll function might split the write in more than 1 write
		 *  (if the write system call only writes a part of the data).
		 * If another part of the program writes to fd, we might get interleaved data,
		 *  because they cannot be aware of our lock (and we cannot be aware of theirs if they have one). */
		JSONLogger.lock.withLock{
			let interLogData: Data
			if Self.isFirstLog {interLogData = Data(); Self.isFirstLog = false}
			else               {interLogData = lineSeparator}
			/* Is there a better idea than silently drop the message in case of fail? */
			_ = try? outputFileDescriptor.writeAll(interLogData + lineDataNoSeparator)
		}
	}
	
	/* Do _not_ use os_unfair_lock, apparently it is bad in Swift:
	 *  <https://twitter.com/grynspan/status/1392080373752995849>.
	 * And OSAllocatedUnfairLock is not available on Linux. */
	private static let lock = NSLock()
#if swift(>=5.10)
	private static nonisolated(unsafe) var isFirstLog = true
#else
	private static var isFirstLog = true
#endif
	
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
				if let (encoder, decoder) = jsonCodersForStringConvertibles,
					let c = s as? any Encodable,
					let data = try? encoder.encode(c),
					let json = try? decoder.decode(JSON.self, from: data)
				{
					json
				} else {
					.string(s.description)
				}
		}
		
	}
	
}
