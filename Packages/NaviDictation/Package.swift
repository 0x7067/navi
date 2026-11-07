// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaviDictation",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NaviDictation", targets: ["NaviDictation"])],
    dependencies: [.package(path: "../NaviCore")],
    targets: [
        .target(name: "NaviDictation", dependencies: ["NaviCore"]),
        .testTarget(name: "NaviDictationTests", dependencies: ["NaviDictation"]),
    ]
)
