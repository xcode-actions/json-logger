#if canImport(Android)
import Android
#endif
import Foundation

import GenericJSON
import Logging



/**
 A logger that logs its messages to stdout in the JSON format, one log per line.
 
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
#if canImport(Darwin) || swift(>=5.3)
		if #available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *) {
			res.outputFormatting = [.withoutEscapingSlashes]
		}
#endif
		res.keyEncodingStrategy = .useDefaultKeys
		if #available(macOS 10.12, tvOS 10.0, iOS 10.0, watchOS 3.0, *) {
			res.dateEncodingStrategy = .iso8601
		} else {
			res.dateEncodingStrategy = .formatted({
				/* Technically an RFC3339 date formatter (straight from the doc), but compatible with ISO8601. */
				let ret = DateFormatter()
				ret.locale = Locale(identifier: "en_US_POSIX")
				ret.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
				ret.timeZone = TimeZone(secondsFromGMT: 0)
				return ret
			}())
		}
		res.dataEncodingStrategy = .base64
		res.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
		return res
	}()
	
#if swift(>=5.7)
	public static let defaultJSONCodersForStringConvertibles: (JSONEncoder, JSONDecoder) = {
		let encoder = JSONEncoder()
		if #available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *) {
			encoder.outputFormatting = [.withoutEscapingSlashes]
		}
		encoder.keyEncodingStrategy = .useDefaultKeys
		encoder.dateEncodingStrategy = .iso8601
		encoder.dataEncodingStrategy = .base64
		encoder.nonConformingFloatEncodingStrategy = .throw
		let decoder = JSONDecoder()
		/* #if os(Darwin) is not available on this version of the compiler. */
#if canImport(Darwin) || swift(>=6.0)
		if #available(macOS 12.0, tvOS 15.0, iOS 15.0, watchOS 8.0, *) {
			decoder.allowsJSON5 = false
		}
#endif
		decoder.keyDecodingStrategy = .useDefaultKeys
		decoder.dateDecodingStrategy = .iso8601
		decoder.dataDecodingStrategy = .base64
#if canImport(Darwin) || swift(>=6.0)
		if #available(macOS 12.0, tvOS 15.0, iOS 15.0, watchOS 8.0, *) {
			decoder.assumesTopLevelDictionary = false
		}
#endif
		decoder.nonConformingFloatDecodingStrategy = .throw
		return (encoder, decoder)
	}()
#endif
	
	public var logLevel: Logger.Level = .info
	
	public var metadata: Logger.Metadata = [:] {
		didSet {jsonMetadataCache = jsonMetadata(metadata)}
	}
	public var metadataProvider: Logger.MetadataProvider?
	
	public let label: String
	
	public let outputFileHandle: FileHandle
	public let lineSeparator: Data
	public let prefix: Data
	public let suffix: Data
	
	public let jsonEncoder: JSONEncoder
#if swift(>=5.7)
	/**
	 If non-`nil`, the `Encodable` stringConvertible properties in the metadata will be encoded as `JSON` using the `JSONEncoder` and `JSONDecoder`.
	 If the encoding fails or this property is set to `nil` the String value will be used. */
	public let jsonCodersForStringConvertibles: (JSONEncoder, JSONDecoder)?
#endif
	
#if swift(>=5.7)
	public static func forJSONSeq(
		on fh: FileHandle = .standardOutput,
		label: String,
		jsonEncoder: JSONEncoder = Self.defaultJSONEncoder,
		jsonCodersForStringConvertibles: (JSONEncoder, JSONDecoder) = Self.defaultJSONCodersForStringConvertibles,
		metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider
	) -> Self {
		return Self(
			label: label,
			fileHandle: fh,
			lineSeparator: Data(), prefix: Data([0x1e]), suffix: Data([0x0a]),
			jsonEncoder: jsonEncoder,
			jsonCodersForStringConvertibles: jsonCodersForStringConvertibles,
			metadataProvider: metadataProvider
		)
	}
	
	public init(
		label: String,
		fileHandle: FileHandle = .standardOutput,
		lineSeparator: Data = Data(), prefix: Data = Data(), suffix: Data = Data("\n".utf8),
		jsonEncoder: JSONEncoder = Self.defaultJSONEncoder,
		jsonCodersForStringConvertibles: (JSONEncoder, JSONDecoder) = Self.defaultJSONCodersForStringConvertibles,
		metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider
	) {
		self.label = label
		self.outputFileHandle = fileHandle
		self.lineSeparator = lineSeparator
		self.prefix = prefix
		self.suffix = suffix
		self.jsonEncoder = jsonEncoder
		self.jsonCodersForStringConvertibles = jsonCodersForStringConvertibles
		
		self.metadataProvider = metadataProvider
	}
	
#else
	
	public static func forJSONSeq(
		on fh: FileHandle = .standardOutput,
		label: String,
		jsonEncoder: JSONEncoder = Self.defaultJSONEncoder,
		metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider
	) -> Self {
		return Self(
			label: label,
			fileHandle: fh,
			lineSeparator: Data(), prefix: Data([0x1e]), suffix: Data([0x0a]),
			jsonEncoder: jsonEncoder,
			metadataProvider: metadataProvider
		)
	}
	
	public init(
		label: String,
		fileHandle: FileHandle = .standardOutput,
		lineSeparator: Data = Data(), prefix: Data = Data(), suffix: Data = Data("\n".utf8),
		jsonEncoder: JSONEncoder = Self.defaultJSONEncoder,
		metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider
	) {
		self.label = label
		self.outputFileHandle = fileHandle
		self.lineSeparator = lineSeparator
		self.prefix = prefix
		self.suffix = suffix
		self.jsonEncoder = jsonEncoder
		
		self.metadataProvider = metadataProvider
	}
#endif
	
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
		
		/* We lock, because the write(contentsOf:) function might split the write in more than 1 write
		 *  (if the write system call only writes a part of the data).
		 * If another part of the program writes to fd, we might get interleaved data,
		 *  because they cannot be aware of our lock (and we cannot be aware of theirs if they have one). */
		JSONLogger.lock.withLock{
			let interLogData: Data
			if Self.isFirstLog {interLogData = Data(); Self.isFirstLog = false}
			else               {interLogData = lineSeparator}
			/* Is there a better idea than silently drop the message in case of fail? */
			/* Is the write retried on interrupt?
			 * We’ll assume yes, but we don’t and can’t know for sure
			 *  until FileHandle has been migrated to the open-source Foundation. */
			let data = interLogData + lineDataNoSeparator
			/* Is there a better idea than silently drop the message in case of fail? */
			/* Is the write retried on interrupt?
			 * We’ll assume yes, but we don’t and can’t know for sure
			 *  until FileHandle has been migrated to the open-source Foundation. */
			if #available(macOS 10.15.4, tvOS 13.4, iOS 13.4, watchOS 6.2, *) {
#if swift(>=5.2) || !canImport(Darwin)
				_ = try? outputFileHandle.write(contentsOf: data)
#else
				/* Let’s write “manually” (FileHandle’s write(_:) method throws an ObjC exception in case of an error).
				 * This code is copied below. */
				data.withUnsafeBytes{ bytes in
					guard !bytes.isEmpty else {
						return
					}
					var written: Int = 0
					repeat {
						written += write(
							outputFileHandle.fileDescriptor,
							bytes.baseAddress!.advanced(by: written),
							bytes.count - written
						)
					} while written < bytes.count && (errno == EINTR || errno == EAGAIN)
				}
#endif
			} else {
				/* Let’s write “manually” (FileHandle’s write(_:) method throws an ObjC exception in case of an error).
				 * This is a copy of the code just above. */
				data.withUnsafeBytes{ bytes in
					guard !bytes.isEmpty else {
						return
					}
					var written: Int = 0
					repeat {
						written += write(
							outputFileHandle.fileDescriptor,
							bytes.baseAddress!.advanced(by: written),
							bytes.count - written
						)
					} while written < bytes.count && (errno == EINTR || errno == EAGAIN)
				}
			}
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
		var metadata = self.metadata
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
		switch metadataValue {
			case let .string(s):              return .string(s)
			case let .array(array):           return .array (array     .map      (jsonMetadataValue(_:)))
			case let .dictionary(dictionary): return .object(dictionary.mapValues(jsonMetadataValue(_:)))
			case let .stringConvertible(s):
				/* Swift 5.7 and more. */
#if swift(>=5.7)
				if let (encoder, decoder) = jsonCodersForStringConvertibles,
					let c = s as? any Encodable,
					let data = try? encoder.encode(c),
					let json = try? decoder.decode(JSON.self, from: data)
				{
					return json
				} else {
					return .string(s.description)
				}
#else
				return .string(s.description)
#endif
		}
		
	}
	
}
