// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VisionCoreML",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "VisionCoreML", targets: ["VisionCoreML"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "VisionCoreML", dependencies: []),
        .testTarget(name: "VisionCoreMLTests", dependencies: ["VisionCoreML"]),

    ]
)
