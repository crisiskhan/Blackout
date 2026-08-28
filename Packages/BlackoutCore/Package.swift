// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BlackoutCore",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BlackoutCore", targets: ["BlackoutCore"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(
            name: "BlackoutCore",
            dependencies: [

            ]
        ),
    ]
)
