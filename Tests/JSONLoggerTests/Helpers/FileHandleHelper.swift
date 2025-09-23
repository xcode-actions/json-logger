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
#if !os(Windows)
			/* closeFile exists but I’m not sure it never throws an ObjC exception, so I call the C function. */
			let ret = system_close(fileDescriptor)
			guard ret == 0 else {
				throw Errno()
			}
#else
			fatalError("Unreachable code reached: In else of #available with only Apple platforms checks, but also on Windows.")
#endif
		}
	}
	
	func jl_readToEnd() throws -> Data? {
		if #available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *) {
#if swift(>=5.2) || !canImport(Darwin)
			return try readToEnd()
#elseif !os(Windows)
			let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 512, alignment: MemoryLayout<UInt8>.alignment)
			defer {buffer.deallocate()}
			
			var nread = 0
			var ret = Data()
			while ({ nread = system_read(fileDescriptor, buffer.baseAddress, buffer.count); return nread }()) > 0 {
				ret += buffer[0..<Int(nread)]
			}
			guard nread >= 0 else {
				throw Errno()
			}
			return ret
#else
 #error("How can we get here? We can import Darwin, but we are on Windows??")
#endif
		} else {
#if !os(Windows)
			let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 512, alignment: MemoryLayout<UInt8>.alignment)
			defer {buffer.deallocate()}
			
			var nread = 0
			var ret = Data()
			while ({ nread = system_read(fileDescriptor, buffer.baseAddress, buffer.count); return nread }()) > 0 {
				ret += buffer[0..<Int(nread)]
			}
			guard nread >= 0 else {
				throw Errno()
			}
			return ret
#else
			fatalError("Unreachable code reached: In else of #available with only Apple platforms checks, but also on Windows.")
#endif
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
