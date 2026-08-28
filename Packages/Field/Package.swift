// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Field",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "Field", targets: ["Field"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Location"),
        .package(path: "../Battery"),
    ],
    targets: [
        .target(
            name: "Field",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
                .product(name: "BlackoutLocation", package: "Location"),
                .product(name: "BlackoutBattery", package: "Battery"),
            ]
        ),
    ]
)
