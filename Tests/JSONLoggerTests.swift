import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif
import XCTest

import Logging

@testable import JSONLogger



final class JSONLoggerTests: XCTestCase {
	
	override class func setUp() {
		LoggingSystem.bootstrap{ JSONLogger(label: $0) }
	}
	
	/* From <https://apple.github.io/swift-log/docs/current/Logging/Protocols/LogHandler.html#treat-log-level-amp-metadata-as-values>. */
	func testFromDoc() {
		var logger1 = Logger(label: "first logger")
		logger1.logLevel = .debug
		logger1[metadataKey: "only-on"] = "first"
		
		var logger2 = logger1
		logger2.logLevel = .error                  /* This must not override `logger1`'s log level. */
		logger2[metadataKey: "only-on"] = "second" /* This must not override `logger1`'s metadata. */
		
		XCTAssertEqual(.debug, logger1.logLevel)
		XCTAssertEqual(.error, logger2.logLevel)
		XCTAssertEqual("first",  logger1[metadataKey: "only-on"])
		XCTAssertEqual("second", logger2[metadataKey: "only-on"])
	}
	
	/* Must be the first test. */
	func test0NoSeparatorForFirstLog() throws {
		/* We do not init the JSONLogger using Logger because we want to test multiple configurations
		 *  which is not possible using LoggingSystem as the bootstrap can only be done once. */
		let pipe = Pipe()
		let jsonLogger = JSONLogger(label: "best-logger", fd: FileDescriptor(rawValue: pipe.fileHandleForWriting.fileDescriptor))
		jsonLogger.log(level: .info, message: "First log message", metadata: nil, source: "dummy-source", file: "dummy-file", function: "dummy-function", line: 42)
		try pipe.fileHandleForWriting.close()
		let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
		XCTAssertEqual(data.first, 0x7b)
	}
	
	func testSeparatorForNotFirstLog() throws {
		let pipe = Pipe()
		let jsonLogger = JSONLogger(label: "best-logger", fd: FileDescriptor(rawValue: pipe.fileHandleForWriting.fileDescriptor))
		jsonLogger.log(level: .info, message: "Not first log message", metadata: nil, source: "dummy-source", file: "dummy-file", function: "dummy-function", line: 42)
		try pipe.fileHandleForWriting.close()
		let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
		XCTAssertEqual(data.first, 0x0a)
	}
	
	func testEncodeMetadataAsJSON() throws {
		struct BestStruct : Encodable, CustomStringConvertible {
			var val: Int
			var description: String {"manually: \(val)"}
		}
		let ref = LogLine(level: .info, message: "Not first log message", metadata: .object(["yolo": .object(["val": .number(21)])]), label: "best-logger", source: "dummy-source", file: "dummy-file", function: "dummy-function", line: 42)
		
		let pipe = Pipe()
		let jsonLogger = JSONLogger(label: "best-logger", fd: FileDescriptor(rawValue: pipe.fileHandleForWriting.fileDescriptor))
		jsonLogger.log(level: ref.level, message: "\(ref.message)", metadata: ["yolo": .stringConvertible(BestStruct(val: 21))], source: ref.source, file: ref.file, function: ref.function, line: ref.line)
		try pipe.fileHandleForWriting.close()
		let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
		let line = try JSONDecoder().decode(LogLine.self, from: data)
		XCTAssertEqual(line, ref)
	}
	
}
