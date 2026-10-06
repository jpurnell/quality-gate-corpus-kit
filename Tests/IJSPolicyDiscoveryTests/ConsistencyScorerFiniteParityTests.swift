import Testing
import Foundation
@testable import IJSPolicyDiscovery
import CorpusKit

/// The scorer's answer for finite input is consumed by the `consistency` checker in every
/// repository the gate runs in. These tests pin it bit for bit, so a change to how a
/// non-finite deduction is handled cannot move a finite score by one ulp unnoticed.
@Suite("ConsistencyScorer — finite scores are unchanged")
struct ConsistencyScorerFiniteParityTests {

    /// Every finding shape the scorer distinguishes: four match types, recurring or not.
    private static func finding(_ matchType: ConsistencyMatchType, recurring: Bool) -> ConsistencyFinding {
        ConsistencyFinding(
            ruleId: "test.rule",
            checkerId: "TestAuditor",
            matchType: matchType,
            clusterRiskWeight: 0.3,
            historicalOccurrences: recurring ? 5 : 1,
            isRecurringInPulse: recurring,
            explanation: "Test"
        )
    }

    /// Finding lists that reach each region of the clamp: nothing deducted, a partial
    /// deduction of every kind, and enough deducted to pin the score at zero.
    static let findingLists: [[ConsistencyFinding]] = [
        [],
        [finding(.clusterMatch, recurring: false)],
        [finding(.anomalyPattern, recurring: false)],
        [finding(.unaddressedPolicy, recurring: false)],
        [finding(.suppressionPattern, recurring: false)],
        [finding(.clusterMatch, recurring: true)],
        [finding(.anomalyPattern, recurring: true)],
        [finding(.unaddressedPolicy, recurring: true)],
        [finding(.suppressionPattern, recurring: true)],
        [
            finding(.clusterMatch, recurring: true),
            finding(.anomalyPattern, recurring: false),
            finding(.unaddressedPolicy, recurring: true),
        ],
        Array(repeating: finding(.clusterMatch, recurring: false), count: 7),
        Array(repeating: finding(.unaddressedPolicy, recurring: false), count: 10),
    ]

    /// Finite weight sets, including ones no sane configuration holds: a negative weight
    /// (a score above one before the clamp) and weights large enough to pin it at zero.
    static let weightSets: [ScorerWeights] = [
        .defaults,
        ScorerWeights(clusterMatch: 0.20, anomalyPattern: 0.15, unaddressedPolicy: 0.10, recurrenceBonus: 0.05),
        ScorerWeights(
            clusterMatch: 0.001, anomalyPattern: 0.003, unaddressedPolicy: 0.007,
            recurrenceBonus: 0.011, suppressionPattern: 0.013),
        ScorerWeights(
            clusterMatch: -0.10, anomalyPattern: 0.10, unaddressedPolicy: 0.05,
            recurrenceBonus: 0.10, suppressionPattern: 0.20),
        ScorerWeights(
            clusterMatch: 1e300, anomalyPattern: 1e300, unaddressedPolicy: 1e300,
            recurrenceBonus: 1e300, suppressionPattern: 1e300),
    ]

    static let validities: [StatisticalValidity] = [.valid, .preliminary, .insufficient]

    /// The scoring arithmetic as it stood before any handling of a non-finite deduction,
    /// written out independently of the scorer.
    private static func reference(
        _ findings: [ConsistencyFinding],
        weights: ScorerWeights,
        multiplier: Double?
    ) -> Double {
        let total = findings.reduce(0.0) { sum, finding in
            let base: Double
            switch finding.matchType {
            case .clusterMatch: base = weights.clusterMatch
            case .anomalyPattern: base = weights.anomalyPattern
            case .unaddressedPolicy: base = weights.unaddressedPolicy
            case .suppressionPattern: base = weights.suppressionPattern
            }
            return sum + (finding.isRecurringInPulse ? base + weights.recurrenceBonus : base)
        }
        guard let multiplier else { return max(0.0, min(1.0, 1.0 - total)) }
        return max(0.0, min(1.0, 1.0 - total * multiplier))
    }

    private static func multiplier(for validity: StatisticalValidity) -> Double {
        switch validity {
        case .valid: return 1.0
        case .preliminary: return 0.5
        case .insufficient: return 0.25
        }
    }

    /// Bit patterns of every default-weight score, one row per finding list:
    /// `[score(findings:), .valid, .preliminary, .insufficient]`.
    static func defaultWeightBitPatterns() -> [[UInt64]] {
        let scorer = ConsistencyScorer()
        return findingLists.map { findings in
            [scorer.score(findings: findings).bitPattern]
                + validities.map { scorer.score(findings: findings, baselineValidity: $0).bitPattern }
        }
    }

    /// Captured from `origin/main` at 1abee27 (1.22.1), before this file's subject changed.
    static let goldenDefaultWeightBitPatterns: [[UInt64]] = [
        [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
        [0x3FEB333333333333, 0x3FEB333333333333, 0x3FED99999999999A, 0x3FEECCCCCCCCCCCD],
        [0x3FECCCCCCCCCCCCD, 0x3FECCCCCCCCCCCCD, 0x3FEE666666666666, 0x3FEF333333333333],
        [0x3FEE666666666666, 0x3FEE666666666666, 0x3FEF333333333333, 0x3FEF99999999999A],
        [0x3FE999999999999A, 0x3FE999999999999A, 0x3FECCCCCCCCCCCCD, 0x3FEE666666666666],
        [0x3FE8000000000000, 0x3FE8000000000000, 0x3FEC000000000000, 0x3FEE000000000000],
        [0x3FE999999999999A, 0x3FE999999999999A, 0x3FECCCCCCCCCCCCD, 0x3FEE666666666666],
        [0x3FEB333333333333, 0x3FEB333333333333, 0x3FED99999999999A, 0x3FEECCCCCCCCCCCD],
        [0x3FE6666666666666, 0x3FE6666666666666, 0x3FEB333333333333, 0x3FED99999999999A],
        [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE8000000000000, 0x3FEC000000000000],
        [0x0000000000000000, 0x0000000000000000, 0x3FDE666666666666, 0x3FE799999999999A],
        [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE8000000000000, 0x3FEC000000000000],
    ]

    @Test("Default-weight scores match the bit patterns recorded before the change")
    func defaultWeightScoresAreByteIdentical() {
        #expect(Self.defaultWeightBitPatterns() == Self.goldenDefaultWeightBitPatterns)
    }

    @Test("Every finite score matches the original arithmetic bit for bit", arguments: weightSets.indices)
    func finiteScoresMatchTheOriginalArithmetic(weightIndex: Int) {
        let weights = Self.weightSets[weightIndex]
        let scorer = ConsistencyScorer(weights: weights)
        for findings in Self.findingLists {
            let plain = Self.reference(findings, weights: weights, multiplier: nil)
            #expect(scorer.score(findings: findings).bitPattern == plain.bitPattern)
            for validity in Self.validities {
                let discounted = Self.reference(
                    findings, weights: weights, multiplier: Self.multiplier(for: validity))
                #expect(
                    scorer.score(findings: findings, baselineValidity: validity).bitPattern
                        == discounted.bitPattern)
            }
        }
    }
}
