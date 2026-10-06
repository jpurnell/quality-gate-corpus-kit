import Foundation
import Testing
import CorpusKit
import QualityGateTypes
@testable import IJSDashboardCore

/// A project's history, read without holding every finding it ever recorded.
///
/// Diagnostics are nearly all of a run file's bytes and almost none of what a summary needs:
/// pass rates, trends and the writer census read statuses and timestamps. `loadHistory` decodes
/// every run without them, and reads in full only the files that hold a checker's latest
/// standard-mode result. These tests pin that the cheap reading says exactly what the full one
/// does — the outline is `loadRuns` minus diagnostics, and the latest results are
/// `TimestampedRun.latestStandardResults(of:)`.
@Suite("CorpusReader.loadHistory")
struct ProjectHistoryTests {

    @Test("Outline runs are the full runs with their diagnostics removed, and nothing else")
    func outlineMatchesFullRunsMinusDiagnostics() throws {
        let corpus = try makeHistoryCorpus()
        let reader = CorpusReader(corpusPath: corpus)

        let full = try reader.loadRuns(for: "proj")
        let history = try reader.loadHistory(for: "proj")

        #expect(history.runs.count == 3)
        #expect(history.runs.map(\.metadata) == full.map { withoutDiagnostics($0.metadata) })
        #expect(history.runs.allSatisfy { run in
            run.metadata.results.allSatisfy(\.diagnostics.isEmpty)
        })
    }

    @Test("Latest standard results carry their diagnostics and match the in-memory composition")
    func latestResultsMatchComposition() throws {
        let corpus = try makeHistoryCorpus()
        let reader = CorpusReader(corpusPath: corpus)

        let expected = TimestampedRun.latestStandardResults(of: try reader.loadRuns(for: "proj"))
        let history = try reader.loadHistory(for: "proj")

        #expect(byChecker(history.latestStandardResults) == byChecker(expected))
        // legibility ran only in the full run; the later subset run must not blank its note.
        #expect(byChecker(history.latestStandardResults)["legibility"]?.diagnostics.count == 1)
        // safety's newest *standard* result is the clean subset run, not the advisory survey.
        #expect(byChecker(history.latestStandardResults)["safety"]?.diagnostics.isEmpty == true)
    }

    @Test("A project with no telemetry has an empty history")
    func missingProjectIsEmpty() throws {
        let corpus = try makeHistoryCorpus()
        let history = try CorpusReader(corpusPath: corpus).loadHistory(for: "absent")
        #expect(history.runs.isEmpty)
        #expect(history.latestStandardResults.isEmpty)
    }

    @Test("A malformed run file is skipped, not fatal")
    func malformedFileSkipped() throws {
        let corpus = try makeHistoryCorpus()
        let dateDir = URL(fileURLWithPath: corpus)
            .appendingPathComponent("telemetry/proj/2026-05-15", isDirectory: true)
        try "not json".write(
            to: dateDir.appendingPathComponent("235959_metadata.json"),
            atomically: true, encoding: .utf8)

        let history = try CorpusReader(corpusPath: corpus).loadHistory(for: "proj")
        #expect(history.runs.count == 3)
    }

    @Test("A project id that is not a single path component is refused")
    func traversalRefused() throws {
        let corpus = try makeHistoryCorpus()
        #expect(throws: (any Error).self) {
            try CorpusReader(corpusPath: corpus).loadHistory(for: "../proj")
        }
    }
}

// MARK: - Helpers

private func byChecker(_ results: [CheckResult]) -> [String: CheckResult] {
    Dictionary(results.map { ($0.checkerId, $0) }) { _, newer in newer }
}

private func withoutDiagnostics(_ metadata: CheckResultMetadata) -> CheckResultMetadata {
    CheckResultMetadata(
        projectID: metadata.projectID,
        timestamp: metadata.timestamp,
        environment: metadata.environment,
        decisionOwner: metadata.decisionOwner,
        results: metadata.results.map {
            CheckResult(checkerId: $0.checkerId, status: $0.status, diagnostics: [],
                        overrides: $0.overrides, complianceRecords: $0.complianceRecords,
                        duration: $0.duration)
        },
        overrides: metadata.overrides,
        riskTier: metadata.riskTier,
        ethicalFlags: metadata.ethicalFlags,
        consistencyScore: metadata.consistencyScore,
        complianceCount: metadata.complianceCount,
        commitSHA: metadata.commitSHA,
        runScope: metadata.runScope,
        gateBuild: metadata.gateBuild,
        identityKind: metadata.identityKind,
        ciIdentity: metadata.ciIdentity,
        host: metadata.host,
        gateMode: metadata.gateMode,
        baseline: metadata.baseline,
        truncation: metadata.truncation
    )
}

/// Three runs of one project: a full standard run with findings, a later subset run that
/// re-runs only `safety` cleanly, and a later advisory survey that reports on `safety` again.
private func makeHistoryCorpus() throws -> String {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory
        .appendingPathComponent("ijs-history-\(UUID().uuidString)", isDirectory: true)
    let dateDir = tmp.appendingPathComponent("telemetry/proj/2026-05-15", isDirectory: true)
    try fm.createDirectory(at: dateDir, withIntermediateDirectories: true)

    let note = Diagnostic(severity: .note, message: "reserved word", filePath: "/src/A.swift",
                          lineNumber: 3, ruleId: "legibility:reserved")
    let failure = Diagnostic(severity: .error, message: "force unwrap", filePath: "/src/B.swift",
                             lineNumber: 9, ruleId: "no-force-unwrap")
    let override = DiagnosticOverride(ruleId: "no-force-unwrap", justification: "validated above",
                                      filePath: "/src/B.swift", lineNumber: 12)

    let runs: [(name: String, metadata: CheckResultMetadata)] = [
        ("100000", metadata(hour: 0, results: [
            CheckResult(checkerId: "legibility", status: .passed, diagnostics: [note],
                        duration: .milliseconds(40)),
            CheckResult(checkerId: "safety", status: .failed, diagnostics: [failure],
                        overrides: [override], duration: .milliseconds(70)),
        ])),
        ("110000", metadata(hour: 1, scope: .subset(checkers: ["safety"]), results: [
            CheckResult(checkerId: "safety", status: .passed, diagnostics: [],
                        duration: .milliseconds(65)),
        ])),
        ("120000", metadata(hour: 2, mode: .advisory, results: [
            CheckResult(checkerId: "safety", status: .passed, diagnostics: [failure],
                        duration: .milliseconds(60)),
        ])),
    ]

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    for run in runs {
        try encoder.encode(run.metadata)
            .write(to: dateDir.appendingPathComponent("\(run.name)_metadata.json"))
    }
    return tmp.path
}

private func metadata(
    hour: Int,
    scope: RunScope = .full,
    mode: GateMode = .standard,
    results: [CheckResult]
) -> CheckResultMetadata {
    CheckResultMetadata(
        projectID: "proj",
        timestamp: Date(timeIntervalSince1970: Double(1_747_267_200 + hour * 3600)),
        environment: .local,
        decisionOwner: "tester",
        results: results,
        overrides: [],
        riskTier: .operational,
        ethicalFlags: [],
        consistencyScore: 0.9,
        commitSHA: "abc123",
        runScope: scope,
        host: "builder.example",
        gateMode: mode
    )
}
