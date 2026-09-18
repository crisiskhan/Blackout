// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MeshDTN",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "MeshDTN", targets: ["MeshDTN"]),
    ],
    dependencies: [
        .package(path: "../BlackBox"),
        .package(path: "../CryptoParty"),
    ],
    targets: [
        .target(name: "MeshDTN", dependencies: ["BlackBox", "CryptoParty"]),
        .testTarget(name: "MeshDTNTests", dependencies: ["MeshDTN", "CryptoParty"]),

    ]
)
