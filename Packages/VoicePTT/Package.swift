// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoicePTT",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "VoicePTT", targets: ["VoicePTT"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "VoicePTT",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
            ]
        ),
        .testTarget(
            name: "VoicePTTTests",
            dependencies: ["VoicePTT"]
        ),
    ]
)
