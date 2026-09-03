// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeadReckoning",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "DeadReckoning", targets: ["DeadReckoning"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "DeadReckoning", dependencies: []),
        .testTarget(name: "DeadReckoningTests", dependencies: ["DeadReckoning"]),

    ]
)
