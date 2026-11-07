// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaviRecording",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NaviRecording", targets: ["NaviRecording"])],
    dependencies: [.package(path: "../NaviCore")],
    targets: [
        .target(name: "NaviRecording", dependencies: ["NaviCore"]),
        .testTarget(name: "NaviRecordingTests", dependencies: ["NaviRecording"]),
    ]
)
