// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "Settings", targets: ["Settings"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Battery"),
        .package(path: "../Location"),
        .package(path: "../Mesh"),
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
                "BlackoutBattery",
                "BlackoutLocation",
                "BlackoutMesh",
            ]
        ),
    ]
)
