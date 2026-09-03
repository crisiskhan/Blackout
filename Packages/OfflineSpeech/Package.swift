// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OfflineSpeech",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "OfflineSpeech", targets: ["OfflineSpeech"]),
    ],
    dependencies: [
        .package(path: "../BlackBox"),
    ],
    targets: [
        .target(name: "OfflineSpeech", dependencies: ["BlackBox"]),
        .testTarget(name: "OfflineSpeechTests", dependencies: ["OfflineSpeech"]),

    ]
)
