// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "Vitals", targets: ["Vitals"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "Vitals", dependencies: []),
        .testTarget(name: "VitalsTests", dependencies: ["Vitals"]),

    ]
)
