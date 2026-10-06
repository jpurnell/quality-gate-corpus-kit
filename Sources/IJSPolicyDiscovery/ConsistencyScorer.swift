import Foundation
import CorpusKit

/// Computes institutional consistency scores from ConsistencyReport findings.
///
/// Scoring algorithm:
/// 1. Start at 1.0 (fully consistent)
/// 2. For each finding, deduct based on type and recurrence
/// 3. Optionally discount by baseline validity
/// 4. Clamp to [0.0, 1.0]
public struct ConsistencyScorer: Sendable {

    /// The weights used for scoring deductions.
    public let weights: ScorerWeights

    /// Creates a scorer with default weights.
    public init() {
        self.weights = .defaults
    }

    /// Creates a scorer with custom weights.
    /// - Parameter weights: The deduction weights to use.
    public init(weights: ScorerWeights) {
        self.weights = weights
    }

    /// Computes a consistency score from findings with full-weight deductions.
    public func score(findings: [ConsistencyFinding]) -> Double {
        let totalDeduction = findings.reduce(0.0) { total, finding in
            total + deduction(for: finding)
        }
        return score(deducting: totalDeduction)
    }

    /// Computes a consistency score, discounting by baseline validity.
    public func score(
        findings: [ConsistencyFinding],
        baselineValidity: StatisticalValidity
    ) -> Double {
        let totalDeduction = findings.reduce(0.0) { total, finding in
            total + deduction(for: finding)
        }
        return score(deducting: totalDeduction * validityMultiplier(for: baselineValidity))
    }

    /// `1 - deduction`, held to `[0, 1]`.
    ///
    /// A deduction that is not a number — which only a NaN weight can produce — scores `0.0`.
    /// The clamp alone would have answered `1.0`, because `min` returns its first argument
    /// when either is a NaN: a scorer that could not compute a score reported an institution
    /// with nothing to fix. Zero is the answer that gets looked at.
    private func score(deducting deduction: Double) -> Double {
        guard !deduction.isNaN else { return 0.0 }
        return max(0.0, min(1.0, 1.0 - deduction))
    }

    private func deduction(for finding: ConsistencyFinding) -> Double {
        let base: Double
        switch finding.matchType {
        case .clusterMatch:
            base = weights.clusterMatch
        case .anomalyPattern:
            base = weights.anomalyPattern
        case .unaddressedPolicy:
            base = weights.unaddressedPolicy
        case .suppressionPattern:
            base = weights.suppressionPattern
        }
        return finding.isRecurringInPulse ? base + weights.recurrenceBonus : base
    }

    private func validityMultiplier(for validity: StatisticalValidity) -> Double {
        switch validity {
        case .valid:
            return 1.0
        case .preliminary:
            return 0.5
        case .insufficient:
            return 0.25
        }
    }
}
