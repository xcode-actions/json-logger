import Foundation



internal extension String {
	
	func safifyForJSON() -> String {
		let ascii = unicodeScalars.lazy.map{ scalar in
			switch scalar {
				case _ where !scalar.isASCII: return "-"
				case #"\"#: return #"\\"#
				case #"""#: return #"\""#
				case "\n": return #"\n"#
				case "\r": return #"\r"#
				/* `scalar.value` should never be bigger than Int32.max, but we still use bitPattern to be safe. */
				case _ where isprint(Int32(bitPattern: scalar.value)) == 0: return "-"
				default: return String(scalar)
			}
		}
		return ascii.joined(separator: "")
	}
	
}
