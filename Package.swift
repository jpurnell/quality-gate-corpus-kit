// swift-tools-version: 6.2
// legibility:description: The one implementation of the quality-gate corpus — schema types, deterministic paths, telemetry I/O, and git sync — shared by quality-gate-swift and org-judgement-system.
import PackageDescription

let package = Package(
    name: "quality-gate-corpus-kit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CorpusKit", targets: ["CorpusKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpurnell/quality-gate-types.git", from: "1.1.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "CorpusKit",
            dependencies: [
                .product(name: "QualityGateTypes", package: "quality-gate-types"),
                .product(name: "Yams", package: "Yams"),
            ],
            // The catalogue is built by the docc plugin, not compiled into the
            // target; excluding it keeps SwiftPM from warning it is unhandled.
            exclude: ["CorpusKit.docc"]
        ),
        .testTarget(name: "CorpusKitTests", dependencies: ["CorpusKit"]),
    ]
)
