// swift-tools-version:5.8
import PackageDescription


//let swiftSettings: [SwiftSetting] = []
let swiftSettings: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
	name: "json-logger",
	platforms: [
		.macOS(.v11),
		.tvOS(.v14),
		.iOS(.v14),
		.watchOS(.v7),
	],
	products: [
		.library(name: "JSONLogger", targets: ["JSONLogger"])
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-log.git",      from: "1.5.1"),
		.package(url: "https://github.com/Frizlab/generic-json.git", from: "3.1.3"),
	],
	targets: [
		.target(name: "JSONLogger", dependencies: [
			.product(name: "GenericJSON",   package: "generic-json"),
			.product(name: "Logging",       package: "swift-log"),
		], path: "Sources", swiftSettings: swiftSettings),
		.testTarget(name: "JSONLoggerTests", dependencies: ["JSONLogger"], swiftSettings: swiftSettings),
	]
)
