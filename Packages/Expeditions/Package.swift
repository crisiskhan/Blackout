// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Expeditions",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "Expeditions", targets: ["Expeditions"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Location"),
    ],
    targets: [
        .target(
            name: "Expeditions",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
                .product(name: "BlackoutLocation", package: "Location"),
            ]
        ),
        .testTarget(
            name: "ExpeditionsTests",
            dependencies: [
                "Expeditions",
                "BlackoutCore",
                "DesignSystem",
            ]
        ),
    ]
)
