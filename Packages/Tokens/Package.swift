// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tokens",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "Tokens", targets: ["Tokens"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "Tokens", dependencies: []),
        .testTarget(name: "TokensTests", dependencies: ["Tokens"]),

    ]
)
