// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BatteryAuction",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "BatteryAuction", targets: ["BatteryAuction"]),
    ],
    dependencies: [
        .package(path: "../BlackBox"),
    ],
    targets: [
        .target(name: "BatteryAuction", dependencies: ["BlackBox"]),
        .testTarget(name: "BatteryAuctionTests", dependencies: ["BatteryAuction"]),

    ]
)
