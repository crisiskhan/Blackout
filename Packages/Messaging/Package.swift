// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Messaging",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "Messaging", targets: ["Messaging"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Mesh"),
    ],
    targets: [
        .target(
            name: "Messaging",
            dependencies: [
                "BlackoutCore",
                "DesignSystem",
                "BlackoutMesh",
            ]
        ),
    ]
)
