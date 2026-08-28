// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Location",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BlackoutLocation", targets: ["BlackoutLocation"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
    ],
    targets: [
        .target(
            name: "BlackoutLocation",
            dependencies: [
                "BlackoutCore",
            ]
        ),
    ]
)
