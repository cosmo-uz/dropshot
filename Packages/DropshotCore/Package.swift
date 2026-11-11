// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DropshotCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DropshotCore", targets: ["DropshotCore"])
    ],
    targets: [
        .target(name: "DropshotCore"),
        .testTarget(name: "DropshotCoreTests", dependencies: ["DropshotCore"])
    ]
)
