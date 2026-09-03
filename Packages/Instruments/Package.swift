// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Instruments",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "Instruments", targets: ["Instruments"]),
    ],
    dependencies: [
        .package(path: "../BlackBox"),
    ],
    targets: [
        .target(name: "Instruments", dependencies: ["BlackBox"]),
        .testTarget(name: "InstrumentsTests", dependencies: ["Instruments"]),

    ]
)
