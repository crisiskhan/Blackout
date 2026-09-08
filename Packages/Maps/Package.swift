// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Maps",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "Maps", targets: ["Maps"]),
        .library(name: "MapsChrome", targets: ["MapsChrome"]),
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
            name: "MapsRouting",
            dependencies: []
        ),
        .target(
            name: "MapsChrome",
            dependencies: []
        ),
        .target(
            name: "Maps",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
                "MapsRouting",
                "MapsChrome",
                .product(name: "BlackoutLocation", package: "Location"),
                .product(name: "BlackoutMesh", package: "Mesh"),
                .product(name: "BlackoutBattery", package: "Battery"),
            ]
        ),
        .testTarget(
            name: "MapsTests",
            dependencies: ["MapsRouting", "MapsChrome"]
        ),
    ]
)
