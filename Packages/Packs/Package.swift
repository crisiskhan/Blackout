// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Packs",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BlackoutPacks", targets: ["BlackoutPacks"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "BlackoutPacks",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
            ],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "PacksTests",
            dependencies: ["BlackoutPacks"]
        ),
    ]
)
