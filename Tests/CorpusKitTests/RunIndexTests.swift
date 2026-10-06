import Testing
import Foundation
@testable import CorpusKit
import QualityGateTypes

/// The per-project run index: one appended line per run, written when the run is.
///
/// The index is derived and the run files are the truth, so most of what is pinned here is
/// about what happens when the two disagree — a torn line, a duplicate, a line from a newer
/// schema — rather than the happy path.
@Suite("Run index")
struct RunIndexTests {

    // MARK: - Writing

    @Test("Writing a run appends one line that is the run without its diagnostics")
    func writeAppendsOutlineLine() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        let metadata = run(second: 0, notes: 3)

        try await TelemetryWriter().write(metadata: metadata, calibrations: [], to: corpus.path)

        let entries = RunIndex.read(at: corpus.indexURL).entries
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.file == "2026-04-28/143022_metadata.json")
        #expect(entry.run == CheckResultMetadata(strippingDiagnosticsFrom: metadata))
        #expect(entry.run.results.allSatisfy { $0.diagnostics.isEmpty })
        #expect(entry.counts["legibility"] == DiagnosticCounts(errors: 0, warnings: 0, notes: 3))
        let runFile = corpus.projectURL.appendingPathComponent(entry.file)
        let runFileBytes = try Data(contentsOf: runFile).count
        #expect(entry.bytes == runFileBytes)
    }

    @Test("A checker with no diagnostics has no entry in the counts — absent means zero")
    func zeroCountsOmitted() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        try await TelemetryWriter().write(metadata: run(second: 0, notes: 0), calibrations: [], to: corpus.path)

        let entry = try #require(RunIndex.read(at: corpus.indexURL).entries.first)
        #expect(entry.counts.isEmpty)
        #expect(entry.diagnosticCounts(for: "legibility") == DiagnosticCounts(errors: 0, warnings: 0, notes: 0))

        // And a rebuild agrees with the writer about it.
        try FileManager.default.removeItem(at: corpus.indexURL)
        _ = try await TelemetryWriter().rebuildIndex(for: corpus.path)
        #expect(RunIndex.read(at: corpus.indexURL).entries.first?.counts.isEmpty == true)
    }

    @Test("A second run appends a second line and leaves the first as it was")
    func secondWriteAppends() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        let writer = TelemetryWriter()

        try await writer.write(metadata: run(second: 0, notes: 1), calibrations: [], to: corpus.path)
        let afterFirst = try Data(contentsOf: corpus.indexURL)
        try await writer.write(metadata: run(second: 5, notes: 2), calibrations: [], to: corpus.path)
        let afterSecond = try Data(contentsOf: corpus.indexURL)

        #expect(afterSecond.prefix(afterFirst.count) == afterFirst)
        #expect(RunIndex.read(at: corpus.indexURL).entries.map(\.file) == [
            "2026-04-28/143022_metadata.json", "2026-04-28/143027_metadata.json",
        ])
    }

    @Test("Every line ends in a newline and holds no other")
    func oneRunOneLine() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        try await TelemetryWriter().write(metadata: run(second: 0, notes: 2), calibrations: [], to: corpus.path)

        let bytes = try Data(contentsOf: corpus.indexURL)
        #expect(bytes.last == UInt8(ascii: "\n"))
        #expect(bytes.filter { $0 == UInt8(ascii: "\n") }.count == 1)
    }

    @Test("A run is still recorded when its index line cannot be appended")
    func appendFailureDoesNotLoseTheRun() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        // A directory where the index file should be: the append cannot succeed.
        try FileManager.default.createDirectory(at: corpus.indexURL, withIntermediateDirectories: true)

        try await TelemetryWriter().write(metadata: run(second: 0, notes: 1), calibrations: [], to: corpus.path)

        let runFile = corpus.projectURL.appendingPathComponent("2026-04-28/143022_metadata.json")
        #expect(FileManager.default.fileExists(atPath: runFile.path))
    }

    // MARK: - Reading

    @Test("A missing index reads as empty, not as an error")
    func missingIndexIsEmpty() throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        let contents = RunIndex.read(at: corpus.indexURL)
        #expect(contents.entries.isEmpty)
        #expect(contents.skippedLines == 0)
    }

    @Test("A torn final line is skipped and the lines before it are kept")
    func tornLineSkipped() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        try await TelemetryWriter().write(metadata: run(second: 0, notes: 1), calibrations: [], to: corpus.path)
        var bytes = try Data(contentsOf: corpus.indexURL)
        bytes.append(Data(#"{"schemaVersion":1,"file":"2026-04-28/1430"#.utf8))
        try bytes.write(to: corpus.indexURL)

        let contents = RunIndex.read(at: corpus.indexURL)
        #expect(contents.entries.count == 1)
        #expect(contents.skippedLines == 1)
    }

    @Test("A line written by a newer schema is skipped, not misread")
    func newerSchemaSkipped() throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        var line = try RunIndex.line(for: run(second: 0, notes: 0), file: "2026-04-28/143022_metadata.json", bytes: 10)
        let text = try #require(String(data: line, encoding: .utf8))
            .replacingOccurrences(of: #"{"bytes":10"#, with: #"{"bytes":10,"futureField":true"#)
            .replacingOccurrences(of: #""schemaVersion":1}"#, with: #""schemaVersion":99}"#)
        line = Data(text.utf8)
        try FileManager.default.createDirectory(at: corpus.projectURL, withIntermediateDirectories: true)
        try line.write(to: corpus.indexURL)

        let contents = RunIndex.read(at: corpus.indexURL)
        #expect(contents.entries.isEmpty)
        #expect(contents.skippedLines == 1)
    }

    // MARK: - Rebuilding

    @Test("Rebuilding produces the index the writer would have written")
    func rebuildMatchesWriter() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        let writer = TelemetryWriter()
        try await writer.write(metadata: run(second: 0, notes: 2), calibrations: [], to: corpus.path)
        try await writer.write(metadata: run(second: 5, notes: 0), calibrations: [], to: corpus.path)
        let written = RunIndex.read(at: corpus.indexURL).entries
        try FileManager.default.removeItem(at: corpus.indexURL)

        let count = try await writer.rebuildIndex(for: corpus.path)

        #expect(count == 2)
        #expect(RunIndex.read(at: corpus.indexURL).entries == written)
    }

    @Test("Rebuilding replaces a damaged index rather than appending to it")
    func rebuildReplaces() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        let writer = TelemetryWriter()
        try await writer.write(metadata: run(second: 0, notes: 1), calibrations: [], to: corpus.path)
        try Data("garbage\n".utf8).write(to: corpus.indexURL)

        let count = try await writer.rebuildIndex(for: corpus.path)

        let contents = RunIndex.read(at: corpus.indexURL)
        #expect(count == 1)
        #expect(contents.entries.count == 1)
        #expect(contents.skippedLines == 0)
    }

    @Test("Rebuilding a project with no runs writes nothing")
    func rebuildEmptyProject() async throws {
        let corpus = try TempCorpus()
        defer { corpus.remove() }
        let count = try await TelemetryWriter().rebuildIndex(for: corpus.path)
        #expect(count == 0)
        #expect(!FileManager.default.fileExists(atPath: corpus.indexURL.path))
    }

    // MARK: - Fixtures

    private func run(second: Int, notes: Int) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "proj",
            timestamp: TestDates.utc(year: 2026, month: 4, day: 28, hour: 14, minute: 30, second: 22 + second),
            environment: .local,
            decisionOwner: "tester",
            results: [
                CheckResult(
                    checkerId: "legibility", status: .passed,
                    diagnostics: (0..<notes).map {
                        Diagnostic(severity: .note, message: "note \($0)", filePath: "/src/A.swift",
                                   lineNumber: $0 + 1, ruleId: "legibility:reserved")
                    },
                    duration: .milliseconds(40)),
            ],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: 0.9,
            commitSHA: "abc123",
            host: "builder-01.local"
        )
    }
}

/// A throwaway corpus for one project, under the system temp directory.
private struct TempCorpus {
    let base: URL
    var path: CorpusPath { CorpusPath(basePath: base.path, projectID: "proj") }
    var projectURL: URL { base.appendingPathComponent("telemetry/proj", isDirectory: true) }
    var indexURL: URL { projectURL.appendingPathComponent("index.jsonl") }

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: base)
        } catch {
            // A leftover temp directory fails no assertion; the OS reclaims it.
            print("TempCorpus cleanup skipped: \(error.localizedDescription)")
        }
    }
}
