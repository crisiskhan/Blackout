// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TimerSync",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "TimerSync", targets: ["TimerSync"]),
    ],
    dependencies: [
        .package(path: "../BlackBox"),
        .package(path: "../CryptoParty"),
    ],
    targets: [
        .target(name: "TimerSync", dependencies: ["BlackBox", "CryptoParty"]),
        .testTarget(name: "TimerSyncTests", dependencies: ["TimerSync"]),

    ]
)
