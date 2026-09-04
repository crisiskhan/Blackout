// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RosterRoles",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "RosterRoles", targets: ["RosterRoles"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "RosterRoles", dependencies: []),
        .testTarget(name: "RosterRolesTests", dependencies: ["RosterRoles"]),

    ]
)
