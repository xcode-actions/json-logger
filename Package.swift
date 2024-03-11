// swift-tools-version:5.3
import PackageDescription


let commonSwiftSettings: [SwiftSetting] = [
	/* Set swift-tools-version to 5.8 to have this available. */
//	.enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
	name: "json-logger",
	platforms: [
		.macOS(.v11),
		.tvOS(.v14),
		.iOS(.v14),
		.watchOS(.v7)
	],
	products: [
		.library(name: "JSONLogger", targets: ["JSONLogger"])
	],
	dependencies: {
		var ret = [Package.Dependency]()
		ret.append(.package(url: "https://github.com/apple/swift-log.git",      from: "1.5.1"))
#if !canImport(System)
		ret.append(.package(url: "https://github.com/apple/swift-system.git",   from: "1.0.0"))
#endif
		ret.append(.package(url: "https://github.com/Frizlab/generic-json.git", from: "3.0.0"))
		return ret
	}(),
	targets: [
		.target(name: "JSONLogger", dependencies: {
			var ret = [Target.Dependency]()
			ret.append(.product(name: "GenericJSON",   package: "generic-json"))
			ret.append(.product(name: "Logging",       package: "swift-log"))
#if !canImport(System)
			ret.append(.product(name: "SystemPackage", package: "swift-system"))
#endif
			return ret
		}(), path: "Sources", swiftSettings: commonSwiftSettings),
		.testTarget(name: "JSONLoggerTests", dependencies: ["JSONLogger"], path: "Tests", swiftSettings: commonSwiftSettings)
	]
)
