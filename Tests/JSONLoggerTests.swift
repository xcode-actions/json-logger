import XCTest
@testable import JSONLogger

import Logging



final class JSONLoggerTests: XCTestCase {
	
	override class func setUp() {
		LoggingSystem.bootstrap{ _ in JSONLogger() }
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
	
	
}
