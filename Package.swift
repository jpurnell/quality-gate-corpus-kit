// swift-tools-version: 6.2
// legibility:description: The one implementation of the quality-gate corpus — schema types, deterministic paths, telemetry I/O, and git sync — shared by quality-gate-swift and org-judgement-system.
import PackageDescription

let package = Package(
    name: "quality-gate-corpus-kit",
    platforms: [.macOS(.v14)],
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
            // Declared as a resource, not excluded. `exclude:` silences SwiftPM's
            // unhandled-file warning by removing the catalogue from `sourceFiles`,
            // which is exactly where swift-docc-plugin looks for it — so DocC received
            // nothing and `doc-lint` passed vacuously on a package that has a catalogue.
            // The CHANGELOG entry for 1.16.0 claimed the catalogue gave doc-lint
            // something to examine; until this line changed, it did not.
            resources: [.copy("CorpusKit.docc")]
        ),
        .testTarget(name: "CorpusKitTests", dependencies: ["CorpusKit"]),
    ]
)
