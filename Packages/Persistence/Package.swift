// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BlackoutPersistence", targets: ["BlackoutPersistence"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
    ],
    targets: [
        .target(
            name: "BlackoutPersistence",
            dependencies: [
                "BlackoutCore",
            ]
        ),
    ]
)
