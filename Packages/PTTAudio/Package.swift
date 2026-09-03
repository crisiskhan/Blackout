// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PTTAudio",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "PTTAudio", targets: ["PTTAudio"]),
    ],
    dependencies: [
        .package(path: "../BlackBox"),
    ],
    targets: [
        .target(name: "PTTAudio", dependencies: ["BlackBox"]),
        .testTarget(name: "PTTAudioTests", dependencies: ["PTTAudio"]),

    ]
)
