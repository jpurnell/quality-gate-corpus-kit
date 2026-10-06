import Foundation
import Testing
import CorpusKit
import QualityGateTypes
@testable import IJSDashboardCore

/// `loadHistory` reads the run index when there is one — and says exactly what it said before.
///
/// The index is an optimisation that has to degrade to the scan, never to a different answer.
/// So the reference truth for every test here is the same call against the same run files with
/// no index at all.
@Suite("CorpusReader over a run index")
struct IndexedHistoryTests {

    @Test("History is identical with an index, without one, and with a partial one")
    func historyIdenticalAcrossIndexStates() async throws {
        let corpus = try await IndexedCorpus(runs: 4)
        defer { corpus.remove() }
        let reader = CorpusReader(corpusPath: corpus.base.path)
        let indexed = try reader.loadHistory(for: "proj")

        // Partial: drop the last two lines, as if two runs came from a gate that wrote no index.
        let lines = try corpus.indexLines()
        try corpus.writeIndex(lines: Array(lines.prefix(2)))
        let partial = try reader.loadHistory(for: "proj")

        try FileManager.default.removeItem(at: corpus.indexURL)
        let scanned = try reader.loadHistory(for: "proj")

        #expect(scanned.runs.count == 4)
        #expect(indexed.runs.map(\.metadata) == scanned.runs.map(\.metadata))
        #expect(partial.runs.map(\.metadata) == scanned.runs.map(\.metadata))
        #expect(byChecker(indexed.latestStandardResults) == byChecker(scanned.latestStandardResults))
        #expect(byChecker(partial.latestStandardResults) == byChecker(scanned.latestStandardResults))
    }

    @Test("An indexed run is not re-read: its outline comes from the line")
    func indexedRunsAreNotReopened() async throws {
        let corpus = try await IndexedCorpus(runs: 3)
        defer { corpus.remove() }
        // Corrupt the oldest run file. Its outline is in the index, and it does not hold any
        // checker's latest result, so nothing needs to open it.
        try Data("not json".utf8).write(to: corpus.runFile(0))

        let history = try CorpusReader(corpusPath: corpus.base.path).loadHistory(for: "proj")

        #expect(history.runs.count == 3)
    }

    @Test("A line naming a run file that is not there is dropped")
    func lineWithoutFileDropped() async throws {
        let corpus = try await IndexedCorpus(runs: 3)
        defer { corpus.remove() }
        try FileManager.default.removeItem(at: corpus.runFile(1))

        let history = try CorpusReader(corpusPath: corpus.base.path).loadHistory(for: "proj")

        #expect(history.runs.count == 2)
    }

    @Test("A line naming a path outside the project is never opened")
    func traversalLineIgnored() async throws {
        let corpus = try await IndexedCorpus(runs: 1)
        defer { corpus.remove() }
        // A real run file beside the corpus, and a line pointing at it.
        let outside = corpus.base.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString)_metadata.json")
        try FileManager.default.copyItem(at: corpus.runFile(0), to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let line = try RunIndex.line(
            for: corpus.metadata(1), file: "../../../\(outside.lastPathComponent)", bytes: 1)
        let handle = try FileHandle(forWritingTo: corpus.indexURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()

        let history = try CorpusReader(corpusPath: corpus.base.path).loadHistory(for: "proj")

        #expect(history.runs.count == 1)
    }

    @Test("Duplicate lines for one run count once, and out-of-order lines are sorted")
    func duplicatesAndOrder() async throws {
        let corpus = try await IndexedCorpus(runs: 3)
        defer { corpus.remove() }
        let lines = try corpus.indexLines()
        // As a union merge would leave it: reversed, with one line twice.
        try corpus.writeIndex(lines: [lines[2], lines[0], lines[1], lines[0]])

        let history = try CorpusReader(corpusPath: corpus.base.path).loadHistory(for: "proj")

        #expect(history.runs.count == 3)
        #expect(history.runs.map(\.metadata.timestamp) == history.runs.map(\.metadata.timestamp).sorted())
    }

    @Test("The latest run comes back whole, findings included")
    func latestRun() async throws {
        let corpus = try await IndexedCorpus(runs: 3)
        defer { corpus.remove() }
        let reader = CorpusReader(corpusPath: corpus.base.path)

        let latest = try #require(try reader.loadLatestRun(for: "proj"))

        #expect(latest.metadata == corpus.metadata(2))
        #expect(latest.metadata.results.first?.diagnostics.count == 3)
        #expect(try reader.loadLatestRun(for: "absent") == nil)
    }

    @Test("The latest run is the same without an index")
    func latestRunWithoutIndex() async throws {
        let corpus = try await IndexedCorpus(runs: 3)
        defer { corpus.remove() }
        try FileManager.default.removeItem(at: corpus.indexURL)

        let latest = try CorpusReader(corpusPath: corpus.base.path).loadLatestRun(for: "proj")

        #expect(latest?.metadata == corpus.metadata(2))
    }

    @Test("The history signature changes when a run is added, indexed or not")
    func signatureTracksRuns() async throws {
        let corpus = try await IndexedCorpus(runs: 2)
        defer { corpus.remove() }
        let reader = CorpusReader(corpusPath: corpus.base.path)
        let before = try reader.historySignature(for: "proj")
        #expect(before == (try reader.historySignature(for: "proj")))
        #expect(before.runFileCount == 2)

        // Indexed: written through the writer.
        try await TelemetryWriter().write(metadata: corpus.metadata(2), calibrations: [], to: corpus.path)
        let afterIndexed = try reader.historySignature(for: "proj")
        #expect(afterIndexed != before)
        #expect(afterIndexed.runFileCount == 3)

        // Unindexed: a run file that arrived with no line — the count still moves.
        try FileManager.default.copyItem(
            at: corpus.runFile(0),
            to: corpus.projectURL.appendingPathComponent("2026-04-28/235959_metadata.json"))
        let afterUnindexed = try reader.historySignature(for: "proj")
        #expect(afterUnindexed != afterIndexed)
        #expect(afterUnindexed.runFileCount == 4)
        #expect(afterUnindexed.indexBytes == afterIndexed.indexBytes)
    }

    @Test("A project with no telemetry has the empty signature")
    func emptySignature() async throws {
        let corpus = try await IndexedCorpus(runs: 0)
        defer { corpus.remove() }
        let signature = try CorpusReader(corpusPath: corpus.base.path).historySignature(for: "absent")
        #expect(signature.runFileCount == 0)
        #expect(signature.indexBytes == nil)
    }
}

private func byChecker(_ results: [CheckResult]) -> [String: CheckResult] {
    Dictionary(results.map { ($0.checkerId, $0) }) { _, newer in newer }
}

/// A one-project corpus whose runs were written through `TelemetryWriter`, so it has an index.
private struct IndexedCorpus {
    let base: URL
    var path: CorpusPath { CorpusPath(basePath: base.path, projectID: "proj") }
    var projectURL: URL { base.appendingPathComponent("telemetry/proj", isDirectory: true) }
    var indexURL: URL { projectURL.appendingPathComponent("index.jsonl") }

    init(runs: Int) async throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("indexed-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent("telemetry", isDirectory: true),
            withIntermediateDirectories: true)
        let writer = TelemetryWriter()
        for index in 0..<runs {
            try await writer.write(metadata: metadata(index), calibrations: [], to: path)
        }
    }

    /// Run `index`: full and standard, one minute after the previous, with `index + 1` notes.
    func metadata(_ index: Int) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "proj",
            // 2026-04-28 14:00:00 UTC, plus a minute per run.
            timestamp: Date(timeIntervalSince1970: Double(1_777_384_800 + index * 60)),
            environment: .local,
            decisionOwner: "tester",
            results: [
                CheckResult(
                    checkerId: "legibility", status: .passed,
                    diagnostics: (0...index).map {
                        Diagnostic(severity: .note, message: "note \($0)", filePath: "/src/A.swift",
                                   lineNumber: $0 + 1, ruleId: "legibility:reserved")
                    },
                    duration: .milliseconds(40)),
            ],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: 0.9,
            host: "builder-01.local"
        )
    }

    /// The index's lines as raw bytes, split on the newline byte the writer terminates each with.
    func indexLines() throws -> [Data] {
        try Data(contentsOf: indexURL).split(separator: UInt8(ascii: "\n")).map { Data($0) }
    }

    /// Replaces the index with exactly these lines, each newline-terminated.
    func writeIndex(lines: [Data]) throws {
        var bytes = Data()
        for line in lines {
            bytes.append(line)
            bytes.append(UInt8(ascii: "\n"))
        }
        try bytes.write(to: indexURL)
    }

    func runFile(_ index: Int) -> URL {
        URL(fileURLWithPath: path.metadataPath(for: metadata(index).timestamp))
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: base)
        } catch {
            // A leftover temp directory fails no assertion; the OS reclaims it.
            print("IndexedCorpus cleanup skipped: \(error.localizedDescription)")
        }
    }
}
