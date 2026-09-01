// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mesh",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BlackoutMesh", targets: ["BlackoutMesh"]),
    ],
    dependencies: [
        .package(path: "../BlackoutCore"),
    ],
    targets: [
        .target(
            name: "BlackoutMesh",
            dependencies: [
                "BlackoutCore",
            ],
            linkerSettings: [
                .linkedFramework("MultipeerConnectivity"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("Network"),
            ]
        ),
        .testTarget(
            name: "MeshTests",
            dependencies: ["BlackoutMesh"]
        ),
    ]
)
