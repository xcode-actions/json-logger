import Foundation

@preconcurrency import GenericJSON
import Logging



public struct LogLine : Hashable, Codable, Sendable {
	
	public var level: Logger.Level
	public var message: String
	public var metadata: JSON
	
	public var label: String
	public var source: String
	public var file: String
	public var function: String
	public var line: UInt
	
	public init(level: Logger.Level, message: String, metadata: JSON, label: String, source: String, file: String, function: String, line: UInt) {
		self.level = level
		self.message = message
		self.metadata = metadata
		self.label = label
		self.source = source
		self.file = file
		self.function = function
		self.line = line
	}
	
}
