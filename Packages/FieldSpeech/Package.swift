// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FieldSpeech",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "FieldSpeech", targets: ["FieldSpeech"]),
    ],
    dependencies: [
        .package(path: "../FieldCorpus"),
        .package(path: "../OfflineSpeech"),
    ],
    targets: [
        .target(name: "FieldSpeech", dependencies: ["FieldCorpus", "OfflineSpeech"]),
        .testTarget(name: "FieldSpeechTests", dependencies: ["FieldSpeech"]),

    ]
)
