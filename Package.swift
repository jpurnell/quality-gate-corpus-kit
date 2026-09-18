// swift-tools-version: 6.2
// legibility:description: The one implementation of the quality-gate corpus — schema types, deterministic paths, telemetry I/O, and git sync — shared by quality-gate-swift and org-judgement-system.
import PackageDescription

let package = Package(
    name: "quality-gate-corpus-kit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CorpusKit", targets: ["CorpusKit"]),
        .library(name: "IJSAggregator", targets: ["IJSAggregator"]),
        .library(name: "IJSPolicyDiscovery", targets: ["IJSPolicyDiscovery"]),
        .library(name: "IJSDashboardCore", targets: ["IJSDashboardCore"]),
    ],
    dependencies: [
        // 1.5.0, not 1.1.0: the absorbed IJS layer uses `Diagnostic.isViolation`, which
        // arrived after 1.1.x. The old floor resolved to 1.1.1 through Package.resolved and
        // compiled only because nothing here needed the newer surface.
        .package(url: "https://github.com/jpurnell/quality-gate-types.git", from: "1.5.0"),
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

        // MARK: - The IJS sensing and reading layer
        //
        // Moved out of quality-gate-swift on 2026-09-17. These read a corpus and compute over
        // it; they are shared by the gate (three checkers consult corpus history), by
        // ijs-mcp-server, and by quality-gate-dashboard. Belonging to none of those, they live
        // beside the format they read. See the companion's
        // plans/proposals/SeparatingTheJudgmentLayer.md §3.1.
        //
        // `IJSSensor` is gone. It was one line — `@_exported import CorpusKit` — kept because
        // it cost nothing, and it cost two builds in one evening: it failed to forward
        // `CorpusPath` where that was wanted, and it forwarded CorpusKit's new `ProcessRunner`
        // into 29 gate files where it collided with the `swift-process-kernel` package that
        // owns that name. A re-export makes a namespace leak invisible at the call site, which
        // is exactly what made both failures hard to read. Consumers now `import CorpusKit`.
        //
        // The module names are otherwise unchanged, including `IJSDashboardCore` — which is now a
        // misnomer, since the one dashboard-specific file (`DashboardLoader`) stayed behind.
        // Renaming it would touch every import in three packages for no behavioural gain, so
        // it is recorded here as a follow-up rather than bundled into a move whose value is
        // that it is mechanical.
        .target(
            name: "IJSAggregator",
            dependencies: [
                "CorpusKit",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(
            name: "IJSPolicyDiscovery",
            dependencies: [
                "IJSAggregator", "CorpusKit",
                .product(name: "QualityGateTypes", package: "quality-gate-types"),
            ]
        ),
        .target(
            name: "IJSDashboardCore",
            dependencies: [
                // CorpusKit explicitly rather than relying on IJSSensor's `@_exported import`.
                // The containment helpers are an extension on `CorpusPath` in a file named
                // CorpusPathContainment.swift — there is no type of that name, which cost a
                // build to discover.
                "IJSAggregator", "CorpusKit",
                .product(name: "QualityGateTypes", package: "quality-gate-types"),
            ]
        ),
        .testTarget(name: "IJSAggregatorTests", dependencies: ["IJSAggregator"]),
        .testTarget(
            name: "IJSPolicyDiscoveryTests",
            dependencies: ["IJSPolicyDiscovery", "IJSAggregator", "CorpusKit"]
        ),
        .testTarget(
            name: "IJSDashboardCoreTests",
            dependencies: ["IJSDashboardCore", "IJSAggregator", "CorpusKit"]
        ),
    ]
)
