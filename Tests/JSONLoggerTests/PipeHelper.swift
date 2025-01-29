#if os(WASI)
import Foundation



typealias Pipe = FakePipe
/* We create a fake pipe on WASI as creating a pipe is not possible. */
final class FakePipe {
	
	init() {
		/* For some reasons, creating the file with `FakePipe.fm.createFile(atPath: filepath, contents: nil)` fails.
		 * Instead we use the Data.write(to:) method which works. */
		guard (try? Data().write(to: fileURL)) != nil else {
			fatalError("\u{1B}[91;1mCould not create temporary file.\u{1B}[0m\n\u{1B}[31;1mPlease make sure to run the test with the `--dir \"\(fileURL.deletingLastPathComponent().path)\"` option.\u{1B}[0m")
		}
	}
	
	deinit {
		_ = try? FakePipe.fm.removeItem(at: fileURL)
	}
	
	var fileHandleForWriting: FileHandle {
		try! FileHandle(forWritingTo: fileURL)
	}
	
	var fileHandleForReading: FileHandle {
		try! FileHandle(forReadingFrom: fileURL)
	}
	
	private static let fm = FileManager.default
	
	private let fileURL = FakePipe.fm.temporaryDirectory.appendingPathComponent("json-logger-test-\(UUID()).txt")
	private var filepath: String {
		fileURL.absoluteURL.path
	}
	
}
#endif
