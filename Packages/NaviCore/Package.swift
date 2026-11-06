// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaviCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NaviCore", targets: ["NaviCore"])],
    targets: [
        .target(name: "NaviCore"),
        .testTarget(name: "NaviCoreTests", dependencies: ["NaviCore"]),
    ]
)
