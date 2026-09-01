// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Crypto",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BlackoutCrypto", targets: ["BlackoutCrypto"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
    ],
    targets: [
        .target(
            name: "BlackoutCrypto",
            dependencies: [
                "BlackoutCore",
            ]
        ),
        .testTarget(
            name: "CryptoTests",
            dependencies: ["BlackoutCrypto"]
        ),
    ]
)
