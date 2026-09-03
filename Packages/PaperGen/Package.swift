// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PaperGen",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "PaperGen", targets: ["PaperGen"]),
    ],
    dependencies: [
        .package(path: "../TripBrief"),
        .package(path: "../RosterRoles"),
        .package(path: "../PackIO"),
    ],
    targets: [
        .target(name: "PaperGen", dependencies: ["TripBrief", "RosterRoles", "PackIO"]),
        .testTarget(name: "PaperGenTests", dependencies: ["PaperGen"]),

    ]
)
