import Foundation
import CorpusKit
import QualityGateLogging

/// Computes institutional consistency scores from ConsistencyReport findings.
///
/// Scoring algorithm:
/// 1. Start at 1.0 (fully consistent)
/// 2. For each finding, deduct based on type and recurrence
/// 3. Optionally discount by baseline validity
/// 4. Clamp to [0.0, 1.0]
///
/// A deduction that is not finite is not a score. ``checkedScore(findings:)`` throws
/// ``InvalidDeduction``; ``score(findings:)``, which predates it and cannot throw, answers
/// `0.0` and logs.
public struct ConsistencyScorer: Sendable {
    private static let logger = Logger(subsystem: "com.quality-gate", category: "ConsistencyScorer")

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

    /// A deduction that is not a finite number, and so cannot be turned into a score.
    ///
    /// Thrown by ``ConsistencyScorer/checkedScore(findings:)`` and
    /// ``ConsistencyScorer/checkedScore(findings:baselineValidity:)``. A deduction is a sum of
    /// weights, so it is non-finite when a weight a finding uses is, or — with every weight
    /// finite — when the sum overflows.
    public struct InvalidDeduction: Error, Equatable, Sendable, CustomStringConvertible {

        /// Which non-finite value the deduction was. Each means something different.
        public enum Kind: String, Sendable, Equatable {
            /// A NaN: a NaN weight, or infinite weights of opposite sign cancelling.
            case notANumber
            /// `+∞`: an infinite weight, or finite weights whose sum overflowed. The clamp
            /// would have scored this `0.0`.
            case positiveInfinity
            /// `-∞`: a negatively infinite weight. The clamp would have scored this `1.0` —
            /// fully consistent.
            case negativeInfinity
        }

        /// Which non-finite value the deduction was.
        public let kind: Kind
        /// The scorer's non-finite weights, by name, in declaration order. Empty when every
        /// weight is finite and the sum overflowed.
        public let nonFiniteWeights: [String]

        /// Creates an invalid-deduction error.
        /// - Parameters:
        ///   - kind: Which non-finite value the deduction was.
        ///   - nonFiniteWeights: The names of the scorer's non-finite weights.
        public init(kind: Kind, nonFiniteWeights: [String]) {
            self.kind = kind
            self.nonFiniteWeights = nonFiniteWeights
        }

        /// The kind of value and the weights responsible, in words.
        public var description: String {
            let what: String
            switch kind {
            case .notANumber: what = "not a number"
            case .positiveInfinity: what = "positive infinity"
            case .negativeInfinity: what = "negative infinity"
            }
            let why = nonFiniteWeights.isEmpty
                ? "every scorer weight is finite: the sum overflowed"
                : "non-finite scorer weights: " + nonFiniteWeights.joined(separator: ", ")
            return "consistency deduction is \(what) (\(why))"
        }
    }

    /// Computes a consistency score from findings with full-weight deductions.
    ///
    /// This method cannot throw, so it cannot say that a score could not be computed. Prefer
    /// ``checkedScore(findings:)``, which can.
    ///
    /// - Returns: `1 - deduction` held to `[0, 1]`, or `0.0` if the deduction is not finite
    ///   (a NaN or either infinity; see ``InvalidDeduction``). Zero fails every threshold, so
    ///   the run is looked at; it is also logged as an error.
    public func score(findings: [ConsistencyFinding]) -> Double {
        do {
            return try checkedScore(findings: findings)
        } catch {
            Self.logger.error("Consistency score reported as 0.0: \(error.description, privacy: .public)")
            return 0.0
        }
    }

    /// Computes a consistency score, discounting by baseline validity.
    ///
    /// This method cannot throw, so it cannot say that a score could not be computed. Prefer
    /// ``checkedScore(findings:baselineValidity:)``, which can.
    ///
    /// - Returns: `1 - deduction` held to `[0, 1]`, or `0.0` if the deduction is not finite
    ///   (a NaN or either infinity; see ``InvalidDeduction``). Zero fails every threshold, so
    ///   the run is looked at; it is also logged as an error.
    public func score(
        findings: [ConsistencyFinding],
        baselineValidity: StatisticalValidity
    ) -> Double {
        do {
            return try checkedScore(findings: findings, baselineValidity: baselineValidity)
        } catch {
            Self.logger.error("Consistency score reported as 0.0: \(error.description, privacy: .public)")
            return 0.0
        }
    }

    /// Computes a consistency score from findings with full-weight deductions, or refuses.
    ///
    /// For every finite deduction the result is bit-for-bit what ``score(findings:)`` returns.
    ///
    /// - Parameter findings: The findings to deduct for.
    /// - Returns: `1 - deduction`, held to `[0, 1]`.
    /// - Throws: ``InvalidDeduction`` if the deduction is a NaN or either infinity.
    public func checkedScore(findings: [ConsistencyFinding]) throws(InvalidDeduction) -> Double {
        let totalDeduction = findings.reduce(0.0) { total, finding in
            total + deduction(for: finding)
        }
        return try score(deducting: totalDeduction)
    }

    /// Computes a consistency score discounted by baseline validity, or refuses.
    ///
    /// For every finite deduction the result is bit-for-bit what
    /// ``score(findings:baselineValidity:)`` returns.
    ///
    /// - Parameters:
    ///   - findings: The findings to deduct for.
    ///   - baselineValidity: How far the Pulse baseline can be trusted; a weaker baseline
    ///     deducts less.
    /// - Returns: `1 - deduction`, held to `[0, 1]`.
    /// - Throws: ``InvalidDeduction`` if the deduction is a NaN or either infinity.
    public func checkedScore(
        findings: [ConsistencyFinding],
        baselineValidity: StatisticalValidity
    ) throws(InvalidDeduction) -> Double {
        let totalDeduction = findings.reduce(0.0) { total, finding in
            total + deduction(for: finding)
        }
        return try score(deducting: totalDeduction * validityMultiplier(for: baselineValidity))
    }

    /// `1 - deduction`, held to `[0, 1]` — for a deduction that is a number.
    ///
    /// The clamp alone answers a non-finite deduction with a score: `1.0` for a NaN (`min`
    /// returns its first argument when either is one) and for `-∞`, `0.0` for `+∞`. None of
    /// those was computed from anything, so none is returned.
    private func score(deducting deduction: Double) throws(InvalidDeduction) -> Double {
        guard deduction.isFinite else {
            let kind: InvalidDeduction.Kind
            if deduction.isNaN {
                kind = .notANumber
            } else if deduction > 0 {
                kind = .positiveInfinity
            } else {
                kind = .negativeInfinity
            }
            throw InvalidDeduction(kind: kind, nonFiniteWeights: weights.nonFiniteWeights)
        }
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
