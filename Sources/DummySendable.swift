import Foundation


#if swift(>=5.5)
public protocol JSONLogger_Sendable : Sendable {}
#else
public protocol JSONLogger_Sendable {}
#endif
