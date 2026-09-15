// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Router",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "Router", targets: ["Router"]),
    ],
    dependencies: [
        .package(path: "../Tokens"),
    ],
    targets: [
        .target(name: "Router", dependencies: ["Tokens"]),
        .testTarget(name: "RouterTests", dependencies: ["Router"]),

    ]
)
