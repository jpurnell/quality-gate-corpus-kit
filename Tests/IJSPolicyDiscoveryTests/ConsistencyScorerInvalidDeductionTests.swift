import Testing
import Foundation
import QualityGateTypes
@testable import IJSPolicyDiscovery
import CorpusKit

/// A deduction that is not finite is not a score. `checkedScore` says so with a typed error;
/// `score`, which cannot throw, answers the one value that fails every threshold.
@Suite("ConsistencyScorer — a deduction that is not finite")
struct ConsistencyScorerInvalidDeductionTests {

    private typealias InvalidDeduction = ConsistencyScorer.InvalidDeduction

    private func finding(_ matchType: ConsistencyMatchType, recurring: Bool = false) -> ConsistencyFinding {
        ConsistencyFinding(
            ruleId: "test.rule",
            checkerId: "TestAuditor",
            matchType: matchType,
            clusterRiskWeight: 0.3,
            historicalOccurrences: 1,
            isRecurringInPulse: recurring,
            explanation: "Test"
        )
    }

    private func weights(
        clusterMatch: Double = 0.15,
        anomalyPattern: Double = 0.10,
        unaddressedPolicy: Double = 0.05,
        recurrenceBonus: Double = 0.10,
        suppressionPattern: Double = 0.20
    ) -> ScorerWeights {
        ScorerWeights(
            clusterMatch: clusterMatch, anomalyPattern: anomalyPattern,
            unaddressedPolicy: unaddressedPolicy, recurrenceBonus: recurrenceBonus,
            suppressionPattern: suppressionPattern)
    }

    // MARK: - ScorerWeights names what is wrong with it

    @Test("Finite weights name no non-finite weight")
    func finiteWeightsNameNothing() {
        #expect(ScorerWeights.defaults.nonFiniteWeights == [])
        #expect(weights(clusterMatch: -0.1, anomalyPattern: 1e300).nonFiniteWeights == [])
    }

    @Test("Non-finite weights are named in declaration order")
    func nonFiniteWeightsAreNamed() {
        #expect(weights(clusterMatch: .nan).nonFiniteWeights == ["clusterMatch"])
        #expect(weights(suppressionPattern: -.infinity).nonFiniteWeights == ["suppressionPattern"])
        #expect(
            weights(
                clusterMatch: .infinity, anomalyPattern: .nan, unaddressedPolicy: -.infinity,
                recurrenceBonus: .signalingNaN, suppressionPattern: .infinity
            ).nonFiniteWeights
                == ["clusterMatch", "anomalyPattern", "unaddressedPolicy", "recurrenceBonus", "suppressionPattern"])
    }

    // MARK: - checkedScore refuses

    @Test("A NaN weight a finding uses is refused as not-a-number")
    func nanWeightThrows() {
        let scorer = ConsistencyScorer(weights: weights(clusterMatch: .nan))
        let expected = InvalidDeduction(kind: .notANumber, nonFiniteWeights: ["clusterMatch"])

        #expect(throws: expected) { try scorer.checkedScore(findings: [finding(.clusterMatch)]) }
        for validity in [StatisticalValidity.valid, .preliminary, .insufficient] {
            #expect(throws: expected) {
                try scorer.checkedScore(findings: [finding(.clusterMatch)], baselineValidity: validity)
            }
        }
    }

    @Test("A NaN recurrence bonus is refused only when a finding recurs")
    func nanRecurrenceBonus() throws {
        let scorer = ConsistencyScorer(weights: weights(recurrenceBonus: .nan))

        #expect(throws: InvalidDeduction(kind: .notANumber, nonFiniteWeights: ["recurrenceBonus"])) {
            try scorer.checkedScore(findings: [finding(.anomalyPattern, recurring: true)])
        }
        let nonRecurring = try scorer.checkedScore(findings: [finding(.anomalyPattern)])
        #expect(nonRecurring.bitPattern == (1.0 - 0.10).bitPattern)
    }

    @Test("An infinite weight is refused as positive infinity, not scored as zero")
    func positiveInfinityThrows() {
        let scorer = ConsistencyScorer(weights: weights(anomalyPattern: .infinity))
        let expected = InvalidDeduction(kind: .positiveInfinity, nonFiniteWeights: ["anomalyPattern"])

        #expect(throws: expected) { try scorer.checkedScore(findings: [finding(.anomalyPattern)]) }
        #expect(throws: expected) {
            try scorer.checkedScore(findings: [finding(.anomalyPattern)], baselineValidity: .insufficient)
        }
    }

    @Test("A negatively infinite weight is refused, not scored as fully consistent")
    func negativeInfinityThrows() {
        let scorer = ConsistencyScorer(weights: weights(unaddressedPolicy: -.infinity))
        let expected = InvalidDeduction(kind: .negativeInfinity, nonFiniteWeights: ["unaddressedPolicy"])

        #expect(throws: expected) { try scorer.checkedScore(findings: [finding(.unaddressedPolicy)]) }
        #expect(throws: expected) {
            try scorer.checkedScore(findings: [finding(.unaddressedPolicy)], baselineValidity: .preliminary)
        }
    }

    @Test("Opposite infinities cancel to not-a-number, and both weights are named")
    func oppositeInfinitiesThrow() {
        let scorer = ConsistencyScorer(weights: weights(clusterMatch: .infinity, anomalyPattern: -.infinity))

        #expect(throws: InvalidDeduction(kind: .notANumber, nonFiniteWeights: ["clusterMatch", "anomalyPattern"])) {
            try scorer.checkedScore(findings: [finding(.clusterMatch), finding(.anomalyPattern)])
        }
    }

    @Test("Finite weights whose sum overflows are refused, with no weight to blame")
    func overflowThrows() {
        let scorer = ConsistencyScorer(weights: weights(clusterMatch: 1e308))
        let findings = Array(repeating: finding(.clusterMatch), count: 20)

        #expect(throws: InvalidDeduction(kind: .positiveInfinity, nonFiniteWeights: [])) {
            try scorer.checkedScore(findings: findings)
        }
    }

    @Test("A non-finite weight no finding uses is not an error: the deduction is finite")
    func unusedNonFiniteWeightIsNotRefused() throws {
        let scorer = ConsistencyScorer(weights: weights(clusterMatch: .nan, suppressionPattern: .infinity))

        let empty = try scorer.checkedScore(findings: [])
        #expect(empty.bitPattern == (1.0).bitPattern)
        let one = try scorer.checkedScore(findings: [finding(.anomalyPattern)], baselineValidity: .preliminary)
        #expect(one.bitPattern == (1.0 - 0.10 * 0.5).bitPattern)
    }

    @Test("checkedScore and score agree bit for bit on every finite deduction",
          arguments: ConsistencyScorerFiniteParityTests.weightSets.indices)
    func checkedScoreAgreesWithScore(weightIndex: Int) throws {
        let scorer = ConsistencyScorer(weights: ConsistencyScorerFiniteParityTests.weightSets[weightIndex])
        for findings in ConsistencyScorerFiniteParityTests.findingLists {
            let checked = try scorer.checkedScore(findings: findings)
            #expect(checked.bitPattern == scorer.score(findings: findings).bitPattern)
            for validity in ConsistencyScorerFiniteParityTests.validities {
                let discounted = try scorer.checkedScore(findings: findings, baselineValidity: validity)
                #expect(
                    discounted.bitPattern
                        == scorer.score(findings: findings, baselineValidity: validity).bitPattern)
            }
        }
    }

    @Test("The error says which weights and what kind, in words")
    func errorDescription() {
        let error = InvalidDeduction(kind: .notANumber, nonFiniteWeights: ["clusterMatch", "recurrenceBonus"])
        #expect(
            error.description
                == "consistency deduction is not a number (non-finite scorer weights: clusterMatch, recurrenceBonus)")
        #expect(
            InvalidDeduction(kind: .positiveInfinity, nonFiniteWeights: []).description
                == "consistency deduction is positive infinity (every scorer weight is finite: the sum overflowed)")
        #expect(
            InvalidDeduction(kind: .negativeInfinity, nonFiniteWeights: ["anomalyPattern"]).description
                == "consistency deduction is negative infinity (non-finite scorer weights: anomalyPattern)")
    }

    // MARK: - score, which cannot throw, never reports a non-finite deduction as consistent

    @Test("score answers zero for every kind of non-finite deduction", arguments: [
        Double.nan, .signalingNaN, .infinity, -.infinity,
    ])
    func scoreIsZeroForNonFiniteDeduction(weight: Double) {
        // `-.infinity` is the case that moved: `max(0, min(1, 1 - -inf))` is 1.0, so an
        // unusable weight read as an institution with nothing to fix.
        let scorer = ConsistencyScorer(weights: weights(clusterMatch: weight))
        let findings = [finding(.clusterMatch)]

        #expect(scorer.score(findings: findings).bitPattern == (0.0).bitPattern)
        #expect(scorer.score(findings: findings, baselineValidity: .valid).bitPattern == (0.0).bitPattern)
        #expect(scorer.score(findings: findings, baselineValidity: .insufficient).bitPattern == (0.0).bitPattern)
    }
}

@Suite("PolicyDiscoveryAuditor — a score that cannot be computed")
struct PolicyDiscoveryAuditorCheckedAuditTests {

    private static let ruleId = "concurrency.unchecked-sendable"
    private static let day = Date(timeIntervalSince1970: 1_777_334_400)

    private func metadata() -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "test-project",
            timestamp: Self.day,
            environment: .local,
            decisionOwner: "tester",
            results: [
                CheckResult(
                    checkerId: "ConcurrencyAuditor",
                    status: .failed,
                    diagnostics: [Diagnostic(severity: .error, message: "Test diagnostic", ruleId: Self.ruleId)],
                    duration: .seconds(1))
            ],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil
        )
    }

    /// A pulse with one recurring cluster the metadata above violates, and enough history
    /// that the baseline is whatever `inferBaselineValidity` makes of an empty trend list.
    private func pulse() -> InstitutionalPulse {
        InstitutionalPulse(
            windowStart: Self.day.addingTimeInterval(-7 * 86_400),
            windowEnd: Self.day,
            weekLabel: "2026-W17",
            projects: ["test-project"],
            statistics: PulseStatistics(
                totalGateRuns: 10, passedRuns: 8, failedRuns: 2, totalOverrides: 1,
                totalCalibrations: 1, overridesByRiskTier: [:], failuresByChecker: [:],
                rootCauseDistribution: [:], failedStepDistribution: [:],
                meanConsistencyScore: nil, corpusTrends: [], projectTrends: [:],
                anomalies: [], corpusSnapshots: [], projectSnapshots: [:]),
            violationClusters: [
                ViolationCluster(
                    ruleId: Self.ruleId, occurrenceCount: 5, affectedProjectCount: 1,
                    dominantRootCause: "systemic", dominantFailedStep: .diagnosis, isRecurring: true)
            ],
            proposedPolicyUpdates: [],
            calibrationSummaries: [],
            narrative: nil,
            generatedAt: Self.day
        )
    }

    private func auditor(clusterMatch: Double) -> PolicyDiscoveryAuditor {
        PolicyDiscoveryAuditor(
            writer: DirectCorpusTransport(),
            scorer: ConsistencyScorer(weights: ScorerWeights(
                clusterMatch: clusterMatch, anomalyPattern: 0.10, unaddressedPolicy: 0.05, recurrenceBonus: 0.10)))
    }

    @Test("checkedAudit refuses a report whose score could not be computed")
    func checkedAuditThrows() async {
        let auditor = auditor(clusterMatch: .nan)
        let metadata = metadata()
        let pulse = pulse()

        await #expect(throws: ConsistencyScorer.InvalidDeduction(
            kind: .notANumber, nonFiniteWeights: ["clusterMatch"])
        ) {
            try await auditor.checkedAudit(metadata: metadata, against: pulse)
        }
    }

    @Test("checkedAudit returns the report audit returns when the deduction is finite")
    func checkedAuditMatchesAudit() async throws {
        let auditor = auditor(clusterMatch: 0.15)
        let metadata = metadata()
        let pulse = pulse()

        let checked = try await auditor.checkedAudit(metadata: metadata, against: pulse)
        let plain = await auditor.audit(metadata: metadata, against: pulse)

        #expect(checked == plain)
        #expect(checked.findings.count == 1)
        #expect(checked.consistencyScore.bitPattern == plain.consistencyScore.bitPattern)
    }

    @Test("audit, which cannot throw, scores an uncomputable deduction zero and keeps the findings")
    func auditScoresZero() async {
        let report = await auditor(clusterMatch: -.infinity).audit(metadata: metadata(), against: pulse())

        #expect(report.consistencyScore.bitPattern == (0.0).bitPattern)
        #expect(report.findings.map(\.ruleId) == [Self.ruleId])
    }
}
