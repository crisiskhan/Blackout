// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TripBrief",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "TripBrief", targets: ["TripBrief"]),
    ],
    targets: [
        .target(name: "TripBrief"),
        .testTarget(name: "TripBriefTests", dependencies: ["TripBrief"]),
    ]
)
