// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KitStore",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "KitStore", targets: ["KitStore"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "KitStore", dependencies: []),
        .testTarget(name: "KitStoreTests", dependencies: ["KitStore"]),

    ]
)
