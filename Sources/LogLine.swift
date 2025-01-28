import Foundation

import GenericJSON
import Logging



public struct LogLine : Hashable, Codable, JSONLogger_Sendable {
	
	public var level: Logger.Level
	public var message: String
	public var metadata: JSON
	
	public var date: Date
	
	public var label: String
	public var source: String
	public var file: String
	public var function: String
	public var line: UInt
	
	public init(level: Logger.Level, message: String, metadata: JSON, date: Date, label: String, source: String, file: String, function: String, line: UInt) {
		self.level = level
		self.message = message
		self.metadata = metadata
		self.date = date
		self.label = label
		self.source = source
		self.file = file
		self.function = function
		self.line = line
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.level    = try container.decode(Logger.Level.self, forKey: .level)
		self.message  = try container.decode(String.self,       forKey: .message)
		self.metadata = try container.decode(JSON.self,         forKey: .metadata)
		self.label    = try container.decode(String.self,       forKey: .label)
		self.source   = try container.decode(String.self,       forKey: .source)
		self.file     = try container.decode(String.self,       forKey: .file)
		self.function = try container.decode(String.self,       forKey: .function)
		self.line     = try container.decode(UInt.self,         forKey: .line)
		/* Date is special. */
		do {
			self.date = try container.decode(Date.self, forKey: .date)
			guard !container.contains(.mangledDate) else {
				throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Both \(CodingKeys.date) and \(CodingKeys.mangledDate) are present in JSON data; this is invalid.")
			}
		} catch let error as DecodingError {
			guard case .keyNotFound = error else {
				throw error
			}
			let t = try container.decode(Double.self, forKey: .mangledDate)
			self.date = Date(timeIntervalSince1970: t)
		}
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(level,    forKey: .level)
		try container.encode(message,  forKey: .message)
		try container.encode(metadata, forKey: .metadata)
		try container.encode(date,     forKey: .date)
		try container.encode(label,    forKey: .label)
		try container.encode(source,   forKey: .source)
		try container.encode(file,     forKey: .file)
		try container.encode(function, forKey: .function)
		try container.encode(line,     forKey: .line)
	}
	
	enum CodingKeys : String, CodingKey {
		case level
		case message
		case metadata
		case date
		case mangledDate = "date-1970"
		case label
		case source
		case file
		case function
		case line
	}
	
}
