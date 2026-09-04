// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MapLibreMap",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "MapLibreMap", targets: ["MapLibreMap"]),
    ],
    dependencies: [
        .package(path: "../PackIO"),
        .package(path: "../Search"),
        .package(path: "../Router"),
        .package(path: "../DeadReckoning"),
        .package(path: "../Almanac"),
        .package(path: "../BlackBox"),
        .package(path: "../../Vendor/MapLibre"),
    ],
    targets: [
        .target(name: "MapLibreMap", dependencies: ["PackIO", "Search", "Router", "DeadReckoning", "Almanac", "BlackBox", "MapLibre"]),
        .testTarget(name: "MapLibreMapTests", dependencies: ["MapLibreMap"]),
    ]
)
