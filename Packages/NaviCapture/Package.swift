// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaviCapture",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NaviCapture", targets: ["NaviCapture"])],
    dependencies: [.package(path: "../NaviCore")],
    targets: [
        .target(name: "NaviCapture", dependencies: ["NaviCore"]),
        .testTarget(name: "NaviCaptureTests", dependencies: ["NaviCapture"]),
    ]
)
