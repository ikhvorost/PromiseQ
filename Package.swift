// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "PromiseQ",
	platforms: [
        .iOS(.v9),
        .macOS(.v10_10),
        .tvOS(.v9),
        .watchOS(.v2)
    ],
    products: [
        .library(name: "PromiseQ", targets: ["PromiseQ"]),
    ],
    targets: [
        .target(name: "PromiseQ", dependencies: []),
		.testTarget(name: "PromiseQTests", dependencies: ["PromiseQ"]),
    ],
	swiftLanguageVersions: [.v5]
)
