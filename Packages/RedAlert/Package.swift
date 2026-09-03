// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RedAlert",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "RedAlert", targets: ["RedAlert"]),
    ],
    dependencies: [
        .package(path: "../Vitals"),
        .package(path: "../BlackBox"),
    ],
    targets: [
        .target(name: "RedAlert", dependencies: ["Vitals", "BlackBox"]),
        .testTarget(name: "RedAlertTests", dependencies: ["RedAlert"]),

    ]
)
