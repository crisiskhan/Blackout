// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Maps",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "Maps", targets: ["Maps"]),
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
            name: "Maps",
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
