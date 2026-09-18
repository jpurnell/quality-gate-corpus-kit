import Foundation
import Testing
import CorpusKit
import QualityGateTypes
@testable import IJSDashboardCore

/// A project's state is not its newest run.
///
/// A one-checker invocation, run while iterating, is newer than the last full sweep — and
/// reading it as the whole picture blanks every other checker's findings. This composes
/// instead: latest result *per checker*, across standard-mode runs only.
@Suite("TimestampedRun.latestStandardResults")
struct LatestStandardResultsTests {

    private func run(
        at seconds: TimeInterval,
        mode: GateMode = .standard,
        checkers: [String]
    ) -> TimestampedRun {
        TimestampedRun(metadata: CheckResultMetadata(
            projectID: "p",
            timestamp: Date(timeIntervalSince1970: seconds),
            environment: .local,
            decisionOwner: "tester",
            results: checkers.map {
                CheckResult(checkerId: $0, status: .passed, diagnostics: [], duration: .zero)
            },
            overrides: [],
            riskTier: .informational,
            ethicalFlags: [],
            consistencyScore: nil,
            gateMode: mode
        ))
    }

    @Test("A newer partial run does not blank the checkers it did not run")
    func partialRunDoesNotBlankOthers() {
        let results = TimestampedRun.latestStandardResults(of: [
            run(at: 0, checkers: ["safety", "legibility"]),
            run(at: 100, checkers: ["safety"]),
        ])
        #expect(Set(results.map(\.checkerId)) == ["safety", "legibility"])
    }

    @Test("The newest standard run wins for a checker that appears in several")
    func newestWinsPerChecker() throws {
        let older = CheckResult(checkerId: "safety", status: .failed, diagnostics: [], duration: .zero)
        let newer = CheckResult(checkerId: "safety", status: .passed, diagnostics: [], duration: .zero)
        let runs = [
            TimestampedRun(metadata: metadata(at: 200, results: [newer])),
            TimestampedRun(metadata: metadata(at: 100, results: [older])),
        ]
        let results = TimestampedRun.latestStandardResults(of: runs)
        #expect(results.count == 1)
        #expect(try #require(results.first).status == .passed)
    }

    @Test("Input order does not matter — runs are sorted before folding")
    func orderIndependent() {
        let ascending = TimestampedRun.latestStandardResults(of: [
            run(at: 0, checkers: ["a"]), run(at: 100, checkers: ["b"]),
        ])
        let descending = TimestampedRun.latestStandardResults(of: [
            run(at: 100, checkers: ["b"]), run(at: 0, checkers: ["a"]),
        ])
        #expect(Set(ascending.map(\.checkerId)) == Set(descending.map(\.checkerId)))
    }

    @Test("Advisory runs are excluded, so a narrowing cannot overwrite a standard verdict")
    func advisoryExcluded() {
        let results = TimestampedRun.latestStandardResults(of: [
            run(at: 0, checkers: ["safety"]),
            run(at: 100, mode: .advisory, checkers: ["safety", "legibility"]),
        ])
        #expect(results.map(\.checkerId) == ["safety"])
    }

    @Test("No standard runs yields nothing, rather than falling back to advisory")
    func noStandardRuns() {
        #expect(TimestampedRun.latestStandardResults(of: [
            run(at: 0, mode: .advisory, checkers: ["safety"]),
        ]).isEmpty)
        #expect(TimestampedRun.latestStandardResults(of: []).isEmpty)
    }

    private func metadata(at seconds: TimeInterval, results: [CheckResult]) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "p",
            timestamp: Date(timeIntervalSince1970: seconds),
            environment: .local,
            decisionOwner: "tester",
            results: results,
            overrides: [],
            riskTier: .informational,
            ethicalFlags: [],
            consistencyScore: nil,
            gateMode: .standard
        )
    }
}
