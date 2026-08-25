import Foundation
import Testing
@testable import CorpusKit
import QualityGateTypes

/// Phase 3a §8 — fail-open enforcement's pulled-network guarantee.
///
/// The transport is never in the enforcement path: a write against an
/// unreachable upstream spools locally instead of throwing, spooled entries
/// drain on reconnect in timestamp order, and a second drain is a no-op
/// (idempotent by timestamp key). A gate that cannot gate because a server
/// is down would be an architectural failure.
@Suite("SpoolingCorpusTransport", .serialized)
struct SpoolingTransportTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// State for an upstream that can be pulled off the network.
    private actor FlakyUpstream {
        var reachable = false
        var metadataWrites: [CheckResultMetadata] = []
        var workEventWrites: [WorkEvent] = []

        func setReachable(_ value: Bool) { reachable = value }
        func recordMetadata(_ metadata: CheckResultMetadata) throws {
            guard reachable else { throw IJSError.telemetryWriteFailed(reason: "network pulled") }
            metadataWrites.append(metadata)
        }
        func recordWorkEvent(_ event: WorkEvent) throws {
            guard reachable else { throw IJSError.telemetryWriteFailed(reason: "network pulled") }
            workEventWrites.append(event)
        }
    }

    /// The minimal transport face over ``FlakyUpstream`` — only the write
    /// paths under test do anything; reads return empty.
    private struct RecordingTransport: CorpusTransport {
        let recorder: FlakyUpstream

        func write(metadata: CheckResultMetadata, calibrations: [JudgmentCalibration], to corpus: CorpusPath) async throws {
            try await recorder.recordMetadata(metadata)
        }
        func writeWorkEvent(_ event: WorkEvent, to corpus: CorpusPath) async throws {
            try await recorder.recordWorkEvent(event)
        }
        func writeSkip(_ record: SkipRecord, to corpus: CorpusPath) async throws {}
        func writePulse(_ pulse: InstitutionalPulse, to corpus: CorpusPath) async throws {}
        func writeSnapshot(_ snapshot: DailySnapshot, to corpus: CorpusPath) async throws {}
        func writeComplexityReport(_ report: ComplexityReport, to corpus: CorpusPath) async throws {}
        func writeOrientationReport(_ report: OrientationReport, to corpus: CorpusPath) async throws {}
        func writeManifest(_ manifest: CorpusManifest, to basePath: String) async throws {}
        func readMetadata(from corpus: CorpusPath, startDate: Date, endDate: Date) async throws -> [CheckResultMetadata] { [] }
        func readLatestMetadata(from corpus: CorpusPath) async throws -> CheckResultMetadata? { nil }
        func readCalibrations(from corpus: CorpusPath, startDate: Date, endDate: Date) async throws -> [JudgmentCalibration] { [] }
        func readLatestPulse(from corpus: CorpusPath, beforeWeek: String?) async throws -> InstitutionalPulse? { nil }
        func readSnapshots(from corpus: CorpusPath, scope: String, startDate: Date, endDate: Date) async throws -> [DailySnapshot] { [] }
        func readComplexityReports(from corpus: CorpusPath, startDate: Date, endDate: Date) async throws -> [ComplexityReport] { [] }
        func readSkipRecords(from corpus: CorpusPath, startDate: Date, endDate: Date) async throws -> [SkipRecord] { [] }
        func readWorkLog(from corpus: CorpusPath) async throws -> [WorkEvent] { [] }
        func discoverProjects(in basePath: String) async throws -> [CorpusPath] { [] }
        func loadManifest(from basePath: String) async throws -> CorpusManifest { CorpusManifest() }
    }

    private func makeSpoolDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeCorpus() throws -> CorpusPath {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spool-corpus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return CorpusPath(basePath: dir.path, projectID: "fixture")
    }

    private func makeMetadata(timestamp: Date) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "fixture",
            timestamp: timestamp,
            environment: .local,
            decisionOwner: "jpurnell",
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil)
    }

    @Test("a write against a pulled network spools instead of throwing")
    func pulledNetworkSpools() async throws {
        let upstream = FlakyUpstream()
        let spoolDir = try makeSpoolDir()
        let transport = SpoolingCorpusTransport(
            upstream: RecordingTransport(recorder: upstream), spoolDirectory: spoolDir)
        let corpus = try makeCorpus()

        // The gate's write path must complete normally — fail-open.
        try await transport.write(metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)

        let recorded = await upstream.metadataWrites
        #expect(recorded.isEmpty)
        // SAFETY: Read-only listing of a spool directory this test created under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input [CWE-22].
        let spooled = try FileManager.default.contentsOfDirectory(atPath: spoolDir.path)
        #expect(spooled.count == 1)
    }

    @Test("reconnect drains spooled writes in timestamp order")
    func drainInOrder() async throws {
        let upstream = FlakyUpstream()
        let spoolDir = try makeSpoolDir()
        let transport = SpoolingCorpusTransport(
            upstream: RecordingTransport(recorder: upstream), spoolDirectory: spoolDir)
        let corpus = try makeCorpus()

        // Spool three writes out of chronological order while down.
        try await transport.write(metadata: makeMetadata(timestamp: base.addingTimeInterval(120)), calibrations: [], to: corpus)
        try await transport.write(metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)
        try await transport.write(metadata: makeMetadata(timestamp: base.addingTimeInterval(60)), calibrations: [], to: corpus)

        await upstream.setReachable(true)
        let drained = try await transport.drainSpool()
        #expect(drained == 3)

        let recorded = await upstream.metadataWrites
        #expect(recorded.map(\.timestamp) == [base, base.addingTimeInterval(60), base.addingTimeInterval(120)])
        // SAFETY: Read-only listing of a spool directory this test created under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input [CWE-22].
        let remaining = try FileManager.default.contentsOfDirectory(atPath: spoolDir.path)
        #expect(remaining.isEmpty)
    }

    @Test("a second drain is a no-op — replay is idempotent")
    func idempotentDrain() async throws {
        let upstream = FlakyUpstream()
        let spoolDir = try makeSpoolDir()
        let transport = SpoolingCorpusTransport(
            upstream: RecordingTransport(recorder: upstream), spoolDirectory: spoolDir)
        let corpus = try makeCorpus()

        try await transport.write(metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)
        await upstream.setReachable(true)
        let first = try await transport.drainSpool()
        let second = try await transport.drainSpool()
        #expect(first == 1)
        #expect(second == 0)
        let recorded = await upstream.metadataWrites
        #expect(recorded.count == 1)
    }

    @Test("a reachable upstream is written through directly — nothing spools")
    func reachablePassthrough() async throws {
        let upstream = FlakyUpstream()
        await upstream.setReachable(true)
        let spoolDir = try makeSpoolDir()
        let transport = SpoolingCorpusTransport(
            upstream: RecordingTransport(recorder: upstream), spoolDirectory: spoolDir)
        let corpus = try makeCorpus()

        try await transport.write(metadata: makeMetadata(timestamp: base), calibrations: [], to: corpus)
        try await transport.writeWorkEvent(
            WorkEvent(date: base, commitSHA: "abc", commitSubjects: [], changelogDelta: nil, sessionSummary: nil),
            to: corpus)

        let metadata = await upstream.metadataWrites
        let events = await upstream.workEventWrites
        #expect(metadata.count == 1)
        #expect(events.count == 1)
        // SAFETY: Read-only listing of a spool directory this test created under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input [CWE-22].
        let spooled = try FileManager.default.contentsOfDirectory(atPath: spoolDir.path)
        #expect(spooled.isEmpty)
    }

    @Test("work events spool and drain like metadata")
    func workEventSpools() async throws {
        let upstream = FlakyUpstream()
        let spoolDir = try makeSpoolDir()
        let transport = SpoolingCorpusTransport(
            upstream: RecordingTransport(recorder: upstream), spoolDirectory: spoolDir)
        let corpus = try makeCorpus()

        try await transport.writeWorkEvent(
            WorkEvent(date: base, commitSHA: "def", commitSubjects: ["fix: y"], changelogDelta: nil, sessionSummary: nil),
            to: corpus)
        await upstream.setReachable(true)
        let drained = try await transport.drainSpool()
        #expect(drained == 1)
        let events = await upstream.workEventWrites
        #expect(events.first?.commitSHA == "def")
    }
}
