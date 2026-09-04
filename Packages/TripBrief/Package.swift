// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TripBrief",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "TripBrief", targets: ["TripBrief"]),
    ],
    dependencies: [
        .package(path: "../TimerSync"),
    ],
    targets: [
        .target(name: "TripBrief", dependencies: ["TimerSync"]),
        .testTarget(name: "TripBriefTests", dependencies: ["TripBrief"]),

    ]
)
