// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FieldStepper",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "FieldStepper", targets: ["FieldStepper"]),
    ],
    dependencies: [
        .package(path: "../FieldCorpus"),
    ],
    targets: [
        .target(name: "FieldStepper", dependencies: ["FieldCorpus"]),
        .testTarget(name: "FieldStepperTests", dependencies: ["FieldStepper"]),

    ]
)
