// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PackIO",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "PackIO", targets: ["PackIO"]),
    ],
    dependencies: [
        .package(path: "../BlackBox"),
    ],
    targets: [
        .target(name: "PackIO", dependencies: ["BlackBox"]),
        .testTarget(name: "PackIOTests", dependencies: ["PackIO"]),

    ]
)
