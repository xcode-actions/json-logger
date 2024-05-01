import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif
import XCTest

import Logging

@testable import JSONLogger



final class JSONLoggerTests : XCTestCase {
	
	public static let defaultJSONDecoder: JSONDecoder = {
		let res = JSONDecoder()
		if #available(macOS 12.0, tvOS 15.0, iOS 15.0, watchOS 8.0, *) {
			res.allowsJSON5 = false
		}
		res.keyDecodingStrategy = .useDefaultKeys
		res.dateDecodingStrategy = .iso8601
		res.dataDecodingStrategy = .base64
		if #available(macOS 12.0, tvOS 15.0, iOS 15.0, watchOS 8.0, *) {
			res.assumesTopLevelDictionary = false
		}
		res.nonConformingFloatDecodingStrategy = .throw
		return res
	}()
	
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
	
	/* ⚠️ Must be the first test. */
	func test0NoSeparatorForFirstLog() throws {
		/* We do not init the JSONLogger using Logger because we want to test multiple configurations
		 *  which is not possible using LoggingSystem as the bootstrap can only be done once. */
		let pipe = Pipe()
		let jsonLogger = JSONLogger(label: "best-logger", fd: FileDescriptor(rawValue: pipe.fileHandleForWriting.fileDescriptor), lineSeparator: Data([0x0a]), prefix: Data(), suffix: Data())
		jsonLogger.log(level: .info, message: "First log message", metadata: nil, source: "dummy-source", file: "dummy-file", function: "dummy-function", line: 42)
		try pipe.fileHandleForWriting.close()
		let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
		XCTAssertEqual(data.first, 0x7b)
	}
	
	func testSeparatorForNotFirstLog() throws {
		let pipe = Pipe()
		let jsonLogger = JSONLogger(label: "best-logger", fd: FileDescriptor(rawValue: pipe.fileHandleForWriting.fileDescriptor), lineSeparator: Data([0x0a]), prefix: Data(), suffix: Data())
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
		let ref = LogLine(level: .info, message: "Not first log message", metadata: .object(["yolo": .object(["val": .number(21)])]), date: Date(), label: "best-logger", source: "dummy-source", file: "dummy-file", function: "dummy-function", line: 42)
		
		let pipe = Pipe()
		let jsonLogger = JSONLogger(label: "best-logger", fd: FileDescriptor(rawValue: pipe.fileHandleForWriting.fileDescriptor))
		jsonLogger.log(level: ref.level, message: "\(ref.message)", metadata: ["yolo": .stringConvertible(BestStruct(val: 21))], source: ref.source, file: ref.file, function: ref.function, line: ref.line)
		try pipe.fileHandleForWriting.close()
		let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
		print(data.reduce("", { $0 + String(format: "%02x", $1) }))
		var line = try Self.defaultJSONDecoder.decode(LogLine.self, from: data)
		XCTAssertLessThanOrEqual(line.date.timeIntervalSince(ref.date), 0.1)
		line.date = ref.date
		XCTAssertEqual(line, ref)
	}
	
	func testFallbackOnLogLineEncodeFailure() throws {
		struct BestStruct : Encodable, CustomStringConvertible {
			var val: Int
			var description: String {"manually: \(val)"}
		}
		let ref = LogLine(level: .info, message: "Not first log message! 🙃", metadata: .object(["yolo": .object(["val": .number(21)])]), date: Date(), label: "best-logger", source: "dummy-source", file: "dummy-file", function: "dummy-function", line: 42)
		let mangled = LogLine(level: .info, message: "MANGLED LOG MESSAGE (see JSONLogger doc) -- Not first log message! -", metadata: .object([
			"JSONLogger.LogInfo": .string("Original metadata removed (see JSONLogger doc)"),
			"JSONLogger.LogError": .string("AnError()")
		]), date: Date(), label: "best-logger", source: "dummy-source", file: "dummy-file", function: "dummy-function", line: 42)
		
		struct AnError : Error {}
		let failEncoder = {
			let res = JSONEncoder()
			res.dateEncodingStrategy = .custom({ _, _ in throw AnError() })
			return res
		}()
		
		let pipe = Pipe()
		let jsonLogger = JSONLogger(label: "best-logger", fd: FileDescriptor(rawValue: pipe.fileHandleForWriting.fileDescriptor), jsonEncoder: failEncoder)
		jsonLogger.log(level: ref.level, message: "\(ref.message)", metadata: ["yolo": .stringConvertible(BestStruct(val: 21))], source: ref.source, file: ref.file, function: ref.function, line: ref.line)
		try pipe.fileHandleForWriting.close()
		let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
		var line = try Self.defaultJSONDecoder.decode(LogLine.self, from: data)
		XCTAssertLessThanOrEqual(line.date.timeIntervalSince(ref.date), 0.1)
		line.date = mangled.date
		XCTAssertEqual(line, mangled)
	}
	
	func testDecodeLogLineWithBothValidDateAndMangledDate() throws {
		let data = Data(#"{"level":"info","message":"","metadata":{},"date":"2023-10-31T23:41:33Z","date-1970":1698795606.2196689,"label":"","source":"","file":"","function":"","line":42}"#.utf8)
		try XCTAssertThrowsError(Self.defaultJSONDecoder.decode(LogLine.self, from: data))
	}
	
	func testDecodeLogLineWithBothInvalidDateAndMangledDate() throws {
		let data = Data(#"{"level":"info","message":"","metadata":{},"date":"this is not a date","date-1970":1698795606.2196689,"label":"","source":"","file":"","function":"","line":42}"#.utf8)
		try XCTAssertThrowsError(Self.defaultJSONDecoder.decode(LogLine.self, from: data))
	}
	
}
