// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Almanac",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "Almanac", targets: ["Almanac"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "Almanac", dependencies: []),
        .testTarget(name: "AlmanacTests", dependencies: ["Almanac"]),

    ]
)
