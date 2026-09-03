// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CommsUI",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "CommsUI", targets: ["CommsUI"]),
    ],
    dependencies: [
        .package(path: "../MeshDTN"),
        .package(path: "../CryptoParty"),
        .package(path: "../PTTAudio"),
        .package(path: "../RosterRoles"),
        .package(path: "../Tokens"),
    ],
    targets: [
        .target(name: "CommsUI", dependencies: ["MeshDTN", "CryptoParty", "PTTAudio", "RosterRoles", "Tokens"]),
        .testTarget(name: "CommsUITests", dependencies: ["CommsUI"]),

    ]
)
