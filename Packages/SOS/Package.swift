// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SOS",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "SOS", targets: ["SOS"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Location"),
        .package(path: "../Mesh"),
        .package(path: "../Battery"),
    ],
    targets: [
        .target(
            name: "SOS",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
                "BlackoutLocation",
                "BlackoutMesh",
                "BlackoutBattery",
            ]
        ),
    ]
)
