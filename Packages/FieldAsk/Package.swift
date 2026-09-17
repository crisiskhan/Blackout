// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FieldAsk",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "FieldAsk", targets: ["FieldAsk"]),
    ],
    dependencies: [
        .package(path: "../FieldCorpus"),
    ],
    targets: [
        .target(name: "FieldAsk", dependencies: ["FieldCorpus"]),
        .testTarget(name: "FieldAskTests", dependencies: ["FieldAsk"]),
    ]
)
