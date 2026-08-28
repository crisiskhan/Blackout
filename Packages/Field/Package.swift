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
    ],
    targets: [
        .target(
            name: "Field",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
            ]
        ),
    ]
)
