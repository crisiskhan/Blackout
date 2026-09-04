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
    ],
    targets: [
        .target(name: "MeshDTN", dependencies: ["BlackBox"]),
        .testTarget(name: "MeshDTNTests", dependencies: ["MeshDTN"]),

    ]
)
