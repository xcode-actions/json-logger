import Foundation

import Logging



/* The @Sendable attribute is only available starting at Swift 5.5.
 * We make these methods only available starting at Swift 5.8 for our convenience (avoids creating another Package@swift-... file)
 *  and because for Swift <5.8 the non-@Sendable variants of the methods are available. */
extension JSONLogger {
	
	@Sendable
	public init(label: String, metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider) {
		/* The fileHandle argument should be present to avoid infinite recursion
		 *  but its value should be the same as the default value of the initializer we’re calling (for API consistency). */
		self.init(label: label, fileHandle: .standardOutput, metadataProvider: metadataProvider)
	}
	
}
