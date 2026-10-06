import Foundation

/// Configurable deduction weights for the consistency scoring algorithm.
///
/// These weights determine how much each finding type deducts from the
/// perfect score of 1.0. Loaded from `.quality-gate.yml` or use defaults.
public struct ScorerWeights: Sendable, Codable, Equatable {
    /// Deduction for a non-recurring cluster match. Default: 0.15.
    public let clusterMatch: Double
    /// Deduction for a non-recurring anomaly pattern. Default: 0.10.
    public let anomalyPattern: Double
    /// Deduction for a non-recurring unaddressed policy. Default: 0.05.
    public let unaddressedPolicy: Double
    /// Additional deduction added when a finding is recurring. Default: 0.10.
    public let recurrenceBonus: Double
    /// Deduction for a suppression pattern (overrides without fixes). Default: 0.20.
    public let suppressionPattern: Double

    /// Default weights — calibrated for intuitive meaning at system launch.
    public static let defaults = ScorerWeights(
        clusterMatch: 0.15,
        anomalyPattern: 0.10,
        unaddressedPolicy: 0.05,
        recurrenceBonus: 0.10,
        suppressionPattern: 0.20
    )

    /// Creates custom scorer weights.
    /// - Parameters:
    ///   - clusterMatch: Deduction per non-recurring cluster match.
    ///   - anomalyPattern: Deduction per non-recurring anomaly pattern.
    ///   - unaddressedPolicy: Deduction per non-recurring unaddressed policy.
    ///   - recurrenceBonus: Additional deduction when a finding is recurring.
    ///   - suppressionPattern: Deduction for override-heavy reduction pattern.
    public init(
        clusterMatch: Double,
        anomalyPattern: Double,
        unaddressedPolicy: Double,
        recurrenceBonus: Double,
        suppressionPattern: Double = 0.20
    ) {
        self.clusterMatch = clusterMatch
        self.anomalyPattern = anomalyPattern
        self.unaddressedPolicy = unaddressedPolicy
        self.recurrenceBonus = recurrenceBonus
        self.suppressionPattern = suppressionPattern
    }

    /// The names of the weights that are not finite — a NaN or either infinity — in
    /// declaration order. Empty for every usable set of weights.
    ///
    /// A weight is a deduction from a score in `[0, 1]`, and no deduction of that kind is a
    /// number of points. Nothing in this type prevents one: `.nan` and `.inf` are valid YAML
    /// scalars, and `init` takes any `Double`. This is how a caller finds out which.
    public var nonFiniteWeights: [String] {
        let named: [(name: String, value: Double)] = [
            ("clusterMatch", clusterMatch),
            ("anomalyPattern", anomalyPattern),
            ("unaddressedPolicy", unaddressedPolicy),
            ("recurrenceBonus", recurrenceBonus),
            ("suppressionPattern", suppressionPattern),
        ]
        return named.filter { !$0.value.isFinite }.map(\.name)
    }
}
