import Foundation

import Logging



extension JSONLogger {
	
	public init(label: String, metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider) {
		/* The fileHandle argument should be present to avoid infinite recursion
		 *  but its value should be the same as the default value of the initializer we’re calling (for API consistency). */
		self.init(label: label, fileHandle: .standardOutput, metadataProvider: metadataProvider)
	}
	
}
