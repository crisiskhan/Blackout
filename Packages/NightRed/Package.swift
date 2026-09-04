// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NightRed",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "NightRed", targets: ["NightRed"]),
    ],
    dependencies: [
        .package(path: "../Tokens"),
    ],
    targets: [
        .target(name: "NightRed", dependencies: ["Tokens"]),
        .testTarget(name: "NightRedTests", dependencies: ["NightRed"]),

    ]
)
