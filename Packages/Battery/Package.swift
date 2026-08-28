// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Battery",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BlackoutBattery", targets: ["BlackoutBattery"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
    ],
    targets: [
        .target(
            name: "BlackoutBattery",
            dependencies: [
                "BlackoutCore",
            ]
        ),
    ]
)
