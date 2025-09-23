#if canImport(Android)
import Android
#endif
import Foundation



#if swift(>=5.10)
private nonisolated(unsafe) let system_read = read
private nonisolated(unsafe) let system_close = close
#else
private let system_read = read
private let system_close = close
#endif

extension FileHandle {
	
	func jl_close() throws {
		if #available(macOS 10.15, *) {
			try close()
		} else {
			/* closeFile exists but I’m not sure it never throws an ObjC exception, so I call the C function. */
			let ret = system_close(fileDescriptor)
			guard ret == 0 else {
				throw Errno()
			}
		}
	}
	
	func jl_readToEnd() throws -> Data? {
		if #available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *) {
#if swift(>=5.2) || !canImport(Darwin)
			return try readToEnd()
#else
			let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 512, alignment: MemoryLayout<UInt8>.alignment)
			defer {buffer.deallocate()}
			
#if !os(Windows)
			var nread = 0
			let bufferCount = buffer.count
#else
			var nread = Int32(0)
			let bufferCount = UInt32(buffer.count)
#endif
			var ret = Data()
			while ({ nread = system_read(fileDescriptor, buffer.baseAddress, bufferCount); return nread }()) > 0 {
				ret += buffer[0..<Int(nread)]
			}
			guard nread >= 0 else {
				throw Errno()
			}
			return ret
#endif
		} else {
			let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 512, alignment: MemoryLayout<UInt8>.alignment)
			defer {buffer.deallocate()}
			
#if !os(Windows)
			var nread = 0
			let bufferCount = buffer.count
#else
			var nread = Int32(0)
			let bufferCount = UInt32(buffer.count)
#endif
			var ret = Data()
			while ({ nread = system_read(fileDescriptor, buffer.baseAddress, bufferCount); return nread }()) > 0 {
				ret += buffer[0..<Int(nread)]
			}
			guard nread >= 0 else {
				throw Errno()
			}
			return ret
		}
	}
	
}


struct Errno : Error {
#if canImport(Darwin)
	var err: errno_t
#else
	var err: Int32
#endif
	init() {
		self.err = errno
	}
}
