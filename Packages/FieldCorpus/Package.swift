// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FieldCorpus",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "FieldCorpus", targets: ["FieldCorpus"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(name: "FieldCorpus", dependencies: []),
        .testTarget(name: "FieldCorpusTests", dependencies: ["FieldCorpus"]),

    ]
)
