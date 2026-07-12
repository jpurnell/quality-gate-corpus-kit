import Foundation
import Testing
@testable import CorpusKit
import QualityGateTypes

/// Phase 3a §1 — `CorpusTransport` and its `.direct` implementation.
///
/// The protocol is the seam Phase 3b's service slots into; `.direct` must
/// reproduce today's `TelemetryWriter` behavior exactly — artifacts written
/// through the transport are readable by the writer and vice versa, so
/// existing corpora need no migration and existing callers can switch
/// mechanically.
@Suite("CorpusTransport .direct")
struct CorpusTransportTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeCorpus() throws -> CorpusPath {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("transport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return CorpusPath(basePath: dir.path, projectID: "fixture")
    }

    private func makeMetadata(timestamp: Date) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "fixture",
            timestamp: timestamp,
            environment: .local,
            decisionOwner: "jpurnell",
            results: [CheckResult(checkerId: "safety", status: .passed, diagnostics: [], duration: .milliseconds(1))],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil)
    }

    @Test("metadata written through the transport reads back through the writer — and vice versa")
    func metadataParity() async throws {
        let corpus = try makeCorpus()
        let transport = DirectCorpusTransport()
        let writer = TelemetryWriter()

        try await transport.write(
            metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)
        let viaWriter = try await writer.readMetadata(
            from: corpus, startDate: base.addingTimeInterval(-60), endDate: base.addingTimeInterval(60))
        #expect(viaWriter.count == 1)
        #expect(viaWriter.first?.decisionOwner == "jpurnell")

        let later = base.addingTimeInterval(3600)
        try await writer.write(metadata: makeMetadata(timestamp: later), calibrations: [], to: corpus)
        let viaTransport = try await transport.readMetadata(
            from: corpus, startDate: base.addingTimeInterval(-60), endDate: later.addingTimeInterval(60))
        #expect(viaTransport.count == 2)
        #expect(viaTransport.map(\.timestamp) == [base, later])
    }

    @Test("latest-metadata, work-log, and skip-record surfaces round-trip through the transport")
    func auxiliarySurfaces() async throws {
        let corpus = try makeCorpus()
        let transport = DirectCorpusTransport()

        let event = WorkEvent(
            date: base, commitSHA: "abc1234", commitSubjects: ["feat: x"],
            changelogDelta: nil, sessionSummary: nil)
        try await transport.writeWorkEvent(event, to: corpus)
        let log = try await transport.readWorkLog(from: corpus)
        #expect(log.count == 1)
        #expect(log.first?.commitSHA == "abc1234")

        let skip = SkipRecord(
            projectID: "fixture", timestamp: base, issueReference: "QG-1",
            author: "jpurnell", environment: .local)
        try await transport.writeSkip(skip, to: corpus)
        let skips = try await transport.readSkipRecords(
            from: corpus, startDate: base.addingTimeInterval(-60), endDate: base.addingTimeInterval(60))
        #expect(skips.count == 1)
        #expect(skips.first?.issueReference == "QG-1")

        try await transport.write(metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)
        let latest = try await transport.readLatestMetadata(from: corpus)
        #expect(latest?.timestamp == base)
    }

    @Test("readMetadataUnion is available on any transport via the protocol extension")
    func unionDefault() async throws {
        let corpus = try makeCorpus()
        let transport = DirectCorpusTransport()
        try await transport.write(metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)

        let union = try await (transport as any CorpusTransport).readMetadataUnion(
            identity: "fixture", basePath: corpus.basePath, manifest: CorpusManifest(),
            startDate: base.addingTimeInterval(-60), endDate: base.addingTimeInterval(60))
        #expect(union.count == 1)
    }

    @Test("discoverProjects and manifest surfaces delegate through the transport")
    func discoveryAndManifest() async throws {
        let corpus = try makeCorpus()
        let transport = DirectCorpusTransport()
        try await transport.write(metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)

        let projects = try await transport.discoverProjects(in: corpus.basePath)
        #expect(projects.map(\.projectID) == ["fixture"])

        var manifest = CorpusManifest()
        manifest.aliases["old-fixture"] = "fixture"
        try await transport.writeManifest(manifest, to: corpus.basePath)
        let loaded = try await transport.loadManifest(from: corpus.basePath)
        #expect(loaded.aliases["old-fixture"] == "fixture")
    }
}
