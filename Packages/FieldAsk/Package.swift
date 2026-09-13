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
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b8638/llama-b8638-xcframework.zip",
            checksum: "7d7d44e35550ebf5ac803173f1897d9dd3dd9a5f8d44218559228cfe966399b7"
        ),
        .target(name: "FieldAsk", dependencies: ["FieldCorpus", "llama"]),
        .testTarget(name: "FieldAskTests", dependencies: ["FieldAsk"]),
    ]
)
