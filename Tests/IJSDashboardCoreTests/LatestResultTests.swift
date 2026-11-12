import Foundation
import Testing
import CorpusKit
import QualityGateTypes
@testable import IJSDashboardCore

/// One checker's latest result, read on demand: the diagnostics behind a "Failed", from the run that the Latest column describes, with
/// one run file read in full and nothing written.
///
/// The index drops diagnostics to stay small, so nothing here may put them back. The tests pin which run is chosen (the newest
/// *standard-mode* one containing the checker, the same fold as `TimestampedRun.latestStandardResults(of:)`), that the diagnostics arrive
/// whole, and that only the chosen file is decoded in full.
@Suite("CorpusReader.latestStandardResult")
struct LatestResultTests {

    // MARK: - Which run

    @Test("The result is the newest standard-mode run's, with every diagnostic and the run's own facts")
    func newestStandardRun() throws {
        let corpus = try makeCorpus()
        let found = try #require(try CorpusReader(corpusPath: corpus.path).latestStandardResult(of: "fallback", for: "proj"))

        // Run 3 (a later standard subset run) beats run 1; run 4 is advisory and must not count.
        #expect(found.result.checkerId == "fallback")
        #expect(found.result.status == .failed)
        #expect(found.result.diagnostics == [Fixture.second, Fixture.third])
        #expect(found.timestamp == Fixture.time(hour: 2))
        #expect(found.projectID == "proj")
        #expect(found.commitSHA == "abc123")
        #expect(found.gateMode == .standard)
    }

    @Test("A newer advisory-mode run is not the latest result")
    func advisoryIgnored() throws {
        let corpus = try makeCorpus()
        let found = try #require(try CorpusReader(corpusPath: corpus.path).latestStandardResult(of: "safety", for: "proj"))
        #expect(found.result.status == .passed)
        #expect(found.result.diagnostics.isEmpty)
        #expect(found.timestamp == Fixture.time(hour: 1))
    }

    @Test("A checker that ran only in an older run still has that run's result")
    func olderRunStillLatest() throws {
        let corpus = try makeCorpus()
        let found = try #require(try CorpusReader(corpusPath: corpus.path).latestStandardResult(of: "legibility", for: "proj"))
        #expect(found.result.diagnostics == [Fixture.note])
        #expect(found.timestamp == Fixture.time(hour: 0))
    }

    @Test("It says what loadHistory says, for every checker")
    func matchesLatestStandardResults() throws {
        let corpus = try makeCorpus()
        let reader = CorpusReader(corpusPath: corpus.path)
        let history = try reader.loadHistory(for: "proj")
        #expect(history.latestStandardResults.count == 3)
        for expected in history.latestStandardResults {
            let found = try #require(try reader.latestStandardResult(of: expected.checkerId, for: "proj"))
            #expect(found.result == expected, "\(expected.checkerId)")
        }
    }

    @Test("A checker with no standard-mode result, and a project with no telemetry, are nil")
    func nothingToFind() throws {
        let corpus = try makeCorpus()
        let reader = CorpusReader(corpusPath: corpus.path)
        #expect(try reader.latestStandardResult(of: "advisory-only", for: "proj") == nil)
        #expect(try reader.latestStandardResult(of: "no-such-checker", for: "proj") == nil)
        #expect(try reader.latestStandardResult(of: "fallback", for: "absent") == nil)
    }

    @Test("A project id that is not a single path component is refused")
    func traversalRefused() throws {
        let corpus = try makeCorpus()
        let reader = CorpusReader(corpusPath: corpus.path)
        #expect(throws: (any Error).self) { try reader.latestStandardResult(of: "fallback", for: "../proj") }
        #expect(throws: (any Error).self) { try reader.latestStandardResult(of: "fallback", for: "a/b") }
    }

    // MARK: - What arrives

    @Test("A diagnostic arrives whole: severity, rule, path, line, column, message and suggested fix, text unchanged")
    func diagnosticsAreWhole() throws {
        let corpus = try makeCorpus()
        let found = try #require(try CorpusReader(corpusPath: corpus.path).latestStandardResult(of: "fallback", for: "proj"))
        let third = try #require(found.result.diagnostics.last)
        #expect(third.severity == .error)
        #expect(third.ruleId == "fallback.int-conversion-unguarded")
        #expect(third.filePath == "/src/Models/ScoringOptions.swift")
        #expect(third.lineNumber == 140)
        #expect(third.columnNumber == 9)
        #expect(third.message == "'level' is floating-point.\nInt(.nan) stops the process — “quote” and tab\t.")
        #expect(third.suggestedFix == "guard x.isFinite first")
    }

    // MARK: - One file in full

    @Test("Only the chosen run file is decoded in full: an older file whose diagnostics cannot be decoded does not matter")
    func olderFilesAreNotDecodedInFull() throws {
        let corpus = try makeCorpus()
        try corrupt(diagnosticsIn: corpus.file("100000"))   // run 1 holds fallback too, but is not the latest
        let found = try #require(try CorpusReader(corpusPath: corpus.path).latestStandardResult(of: "fallback", for: "proj"))
        #expect(found.timestamp == Fixture.time(hour: 2))
        #expect(found.result.diagnostics.count == 2)
    }

    @Test("The chosen run file's own diagnostics being unreadable is a typed failure, not nil and not an empty success")
    func chosenFileUnreadable() throws {
        let corpus = try makeCorpus()
        try corrupt(diagnosticsIn: corpus.file("120000_std"))  // the file holding fallback's latest result
        let reader = CorpusReader(corpusPath: corpus.path)
        #expect(throws: LatestResultError.runFileUnreadable) { try reader.latestStandardResult(of: "fallback", for: "proj") }
    }

    @Test("Nothing is written: the corpus is the same after the read")
    func readOnly() throws {
        let corpus = try makeCorpus()
        let before = try snapshot(corpus.path)
        _ = try CorpusReader(corpusPath: corpus.path).latestStandardResult(of: "fallback", for: "proj")
        #expect(try snapshot(corpus.path) == before)
    }
}

// MARK: - Fixture

private enum Fixture {
    static func time(hour: Int) -> Date { Date(timeIntervalSince1970: Double(1_747_267_200 + hour * 3600)) }

    static let note = Diagnostic(severity: .note, message: "reserved word", filePath: "/src/A.swift", lineNumber: 3, ruleId: "legibility:reserved")
    static let first = Diagnostic(severity: .error, message: "old finding", filePath: "/src/Old.swift", lineNumber: 1, ruleId: "fallback.int-conversion-unguarded")
    static let second = Diagnostic(
        severity: .error, message: "'methodology.significanceLevel' is floating-point.", filePath: "/src/Models/ScoringOptions.swift",
        lineNumber: 97, columnNumber: 22, ruleId: "fallback.int-conversion-unguarded", suggestedFix: "guard x.isFinite first")
    static let third = Diagnostic(
        severity: .error, message: "'level' is floating-point.\nInt(.nan) stops the process — “quote” and tab\t.",
        filePath: "/src/Models/ScoringOptions.swift", lineNumber: 140, columnNumber: 9, ruleId: "fallback.int-conversion-unguarded",
        suggestedFix: "guard x.isFinite first")
}

/// Four runs of one project. Run 1: a full standard run (fallback fails with an old finding, legibility notes, safety fails). Run 2: a
/// standard subset run re-running only safety, clean. Run 3: a standard subset run re-running only fallback, failing with two findings.
/// Run 4: a later advisory survey reporting on fallback, safety and an advisory-only checker.
private func makeCorpus() throws -> Corpus {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("ijs-latest-\(UUID().uuidString)", isDirectory: true)
    let day = root.appendingPathComponent("telemetry/proj/2026-05-15", isDirectory: true)
    try fm.createDirectory(at: day, withIntermediateDirectories: true)

    let runs: [(name: String, metadata: CheckResultMetadata)] = [
        ("100000", metadata(hour: 0, results: [
            CheckResult(checkerId: "fallback", status: .failed, diagnostics: [Fixture.first], duration: .milliseconds(10)),
            CheckResult(checkerId: "legibility", status: .passed, diagnostics: [Fixture.note], duration: .milliseconds(40)),
            CheckResult(checkerId: "safety", status: .failed, diagnostics: [Fixture.first], duration: .milliseconds(70)),
        ])),
        ("110000", metadata(hour: 1, scope: .subset(checkers: ["safety"]), results: [
            CheckResult(checkerId: "safety", status: .passed, diagnostics: [], duration: .milliseconds(65)),
        ])),
        ("120000_std", metadata(hour: 2, scope: .subset(checkers: ["fallback"]), results: [
            CheckResult(checkerId: "fallback", status: .failed, diagnostics: [Fixture.second, Fixture.third], duration: .milliseconds(12)),
        ])),
        ("130000", metadata(hour: 3, mode: .advisory, results: [
            CheckResult(checkerId: "fallback", status: .passed, diagnostics: [], duration: .milliseconds(11)),
            CheckResult(checkerId: "safety", status: .failed, diagnostics: [Fixture.first], duration: .milliseconds(60)),
            CheckResult(checkerId: "advisory-only", status: .passed, diagnostics: [], duration: .milliseconds(5)),
        ])),
    ]

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    for run in runs {
        try encoder.encode(run.metadata).write(to: day.appendingPathComponent("\(run.name)_metadata.json"))
    }
    return Corpus(path: root.path, day: day)
}

private struct Corpus {
    let path: String
    let day: URL
    func file(_ name: String) -> URL { day.appendingPathComponent("\(name)_metadata.json") }
}

private func metadata(hour: Int, scope: RunScope = .full, mode: GateMode = .standard, results: [CheckResult]) -> CheckResultMetadata {
    CheckResultMetadata(
        projectID: "proj", timestamp: Fixture.time(hour: hour), environment: .local, decisionOwner: "tester", results: results,
        overrides: [], riskTier: .operational, ethicalFlags: [], consistencyScore: 0.9, commitSHA: "abc123", runScope: scope,
        host: "builder.example", gateMode: mode)
}

/// Makes a run file's `diagnostics` undecodable while leaving everything an outline reads intact.
private func corrupt(diagnosticsIn url: URL) throws {
    let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var results = try #require(object["results"] as? [[String: Any]])
    for index in results.indices { results[index]["diagnostics"] = "not a list of diagnostics" }
    var changed = object
    changed["results"] = results
    try JSONSerialization.data(withJSONObject: changed).write(to: url)
}

/// Every file's path and bytes, for comparing a corpus before and after a read.
private func snapshot(_ path: String) throws -> [String: Data] {
    var found: [String: Data] = [:]
    let root = URL(fileURLWithPath: path)
    let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
    for case let url as URL in enumerator {
        let isFile = Result(catching: { try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile })
        guard case .success(true?) = isFile else { continue }
        found[url.path] = try Data(contentsOf: url)
    }
    return found
}
