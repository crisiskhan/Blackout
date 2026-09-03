// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RegionalPacks",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "RegionalPacks", targets: ["RegionalPacks"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "RegionalPacks", dependencies: []),
        .testTarget(name: "RegionalPacksTests", dependencies: ["RegionalPacks"]),

    ]
)
