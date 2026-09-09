// swift-tools-version: 5.10
import PackageDescription

// A Linux stand-in for the parts of the app that are only Foundation.
//
// Every package under Packages/ declares `platforms: [.iOS(...)]`, so SwiftPM
// on Linux refuses them outright and the whole Swift suite can only be run from
// a Mac with a simulator. Most of what those packages contain has nothing to do
// with iOS — the water index, the map chrome, the router, the pack catalogue —
// and waiting on CI to find out that a pure function is wrong is a slow way to
// work.
//
// So this manifest points at the same source files with no platform floor. It
// is a harness, not a product: it ships nothing, CI does not run it, and the
// symlinked source directories, and the
// iOS-only files are left out by the `#if canImport(UIKit)` they already carry.
//
//     swift test --package-path tools/swiftcheck
//
let package = Package(
    name: "swiftcheck",
    targets: [
        .target(name: "BlackBox", path: "Sources/BlackBox"),
        .target(
            name: "PackIO",
            dependencies: ["BlackBox"],
            path: "Sources/PackIO"
        ),
        .target(name: "Search", path: "Sources/Search"),
        .target(name: "Router", path: "Sources/Router"),
        .target(
            name: "DeadReckoning",
            path: "Sources/DeadReckoning"
        ),
        .target(name: "Almanac", path: "Sources/Almanac"),
        .target(
            name: "MapLibreMap",
            dependencies: ["PackIO", "Search", "Router", "DeadReckoning", "Almanac", "BlackBox"],
            path: "Sources/MapLibreMap"
        ),
        .testTarget(
            name: "MapLibreMapTests",
            dependencies: ["MapLibreMap", "PackIO", "Router"],
            path: "Tests/MapLibreMapTests"
        ),
        .testTarget(
            name: "PackIOTests",
            dependencies: ["PackIO"],
            path: "Tests/PackIOTests"
        ),
        // RouterTests is not here: it measures resident memory through Mach,
        // which does not exist off Darwin. It runs on the simulator in CI.
    ]
)
