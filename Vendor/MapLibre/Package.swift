// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MapLibre",
    platforms: [.iOS("12.0")],
    products: [
        .library(name: "MapLibre", targets: ["MapLibre"]),
    ],
    targets: [
        .binaryTarget(
            name: "MapLibre",
            path: "MapLibre.xcframework"
        ),
    ]
)
