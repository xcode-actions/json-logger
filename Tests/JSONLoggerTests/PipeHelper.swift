#if os(WASI)
import Foundation
import WASILibc



typealias Pipe = FakePipe
struct FakePipe {
	
	init() {
		try! Data().write(to: fileURL)
		assert(FileManager.default.fileExists(atPath: fileURL.absoluteURL.path), "Created file does not exist!")
	}
	
	var fileHandleForWriting: FileHandle {
		return try! FileHandle(forWritingTo: fileURL)
	}
	
	var fileHandleForReading: FileHandle {
		return try! FileHandle(forReadingFrom: fileURL)
	}
	
	private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("json-logger-test-\(UUID()).txt")
//	private let fileURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("json-logger-test-\(UUID()).txt")
	private var filepath: String {
		fileURL.absoluteURL.path
	}
	
}
#endif
