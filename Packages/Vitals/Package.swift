// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "Vitals", targets: ["Vitals"]),
    ],
    dependencies: [
        .package(path: "../CryptoParty"),
    ],
    targets: [
        .target(name: "Vitals", dependencies: ["CryptoParty"]),
        .testTarget(name: "VitalsTests", dependencies: ["Vitals"]),

    ]
)
