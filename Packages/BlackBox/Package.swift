// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BlackBox",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "BlackBox", targets: ["BlackBox"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "BlackBox", dependencies: []),
        .testTarget(name: "BlackBoxTests", dependencies: ["BlackBox"]),

    ]
)
