// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VisionCapture",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "VisionCapture", targets: ["VisionCapture"]),
    ],
    dependencies: [
        .package(path: "../VisionCoreML"),
    ],
    targets: [
        .target(name: "VisionCapture", dependencies: ["VisionCoreML"]),
        .testTarget(name: "VisionCaptureTests", dependencies: ["VisionCapture"]),

    ]
)
