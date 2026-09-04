// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Search",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "Search", targets: ["Search"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "Search", dependencies: []),
        .testTarget(name: "SearchTests", dependencies: ["Search"]),

    ]
)
