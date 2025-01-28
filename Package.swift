// swift-tools-version:5.1
import PackageDescription


let package = Package(
	name: "json-logger",
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
		], path: "Sources"),
		.testTarget(name: "JSONLoggerTests", dependencies: ["JSONLogger"]),
	]
)
