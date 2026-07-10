import Foundation

/// Per-project health summary derived from the checker pass rate on each project's latest gate run.
///
/// Each project's health is its checker pass rate (0.0–100.0) on the most recent run.
/// The ``meanHealthRate`` gives the portfolio-wide average of those rates.
/// Trajectories track per-run pass rates to show improvement or regression over time.
///
/// Ported from org-judgement-system (drift #4). Its nested trajectory type is
/// ``RunRateTrajectory`` here — the name `ProjectTrajectory` was already taken
/// by the regression-based trajectory used in ``InstitutionalPulse``.
public struct ProjectHealthSummary: Sendable, Codable, Equatable {
    /// Per-project checker pass rate (0.0–100.0) on the latest gate run, keyed by project ID.
    public let projectPassRates: [String: Double]
    /// Per-project run-by-run trajectories within the window, keyed by project ID.
    public let trajectories: [String: RunRateTrajectory]

    /// Portfolio-wide mean of per-project pass rates (0.0–100.0).
    ///
    /// Returns `0.0` when there are no projects.
    public var meanHealthRate: Double {
        guard !projectPassRates.isEmpty else { return 0.0 }
        let sum = projectPassRates.values.reduce(0.0, +)
        return sum / Double(projectPassRates.count)
    }

    /// Number of projects evaluated.
    public var totalProjects: Int { projectPassRates.count }

    /// Creates a new project health summary.
    /// - Parameters:
    ///   - projectPassRates: Per-project checker pass rate keyed by project ID.
    ///   - trajectories: Per-project run-by-run trajectory data.
    public init(projectPassRates: [String: Double], trajectories: [String: RunRateTrajectory] = [:]) {
        self.projectPassRates = projectPassRates
        self.trajectories = trajectories
    }

    private enum CodingKeys: String, CodingKey {
        case projectPassRates, trajectories
        case projectStatuses
    }

    /// Creates a ``ProjectHealthSummary`` from a decoder, tolerating the legacy
    /// boolean `projectStatuses` shape (pass → 100.0, fail → 0.0).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rates = try container.decodeIfPresent([String: Double].self, forKey: .projectPassRates) {
            self.projectPassRates = rates
        } else if let statuses = try container.decodeIfPresent([String: Bool].self, forKey: .projectStatuses) {
            self.projectPassRates = statuses.mapValues { $0 ? 100.0 : 0.0 }
        } else {
            self.projectPassRates = [:]
        }
        self.trajectories = try container.decodeIfPresent(
            [String: RunRateTrajectory].self, forKey: .trajectories
        ) ?? [:]
    }

    /// Encodes this instance to the given encoder, omitting empty trajectories.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectPassRates, forKey: .projectPassRates)
        if !trajectories.isEmpty {
            try container.encode(trajectories, forKey: .trajectories)
        }
    }
}

/// Run-by-run pass rate trajectory for a single project within the pulse window.
///
/// Named `ProjectTrajectory` in org-judgement-system before consolidation;
/// renamed here to avoid colliding with the regression-based ``ProjectTrajectory``.
/// The serialized shape is unchanged.
public struct RunRateTrajectory: Sendable, Codable, Equatable {
    /// Pass rate on the first run in the window (0.0–100.0).
    public let firstRunRate: Double
    /// Pass rate on the latest run in the window (0.0–100.0).
    public let latestRunRate: Double
    /// Total number of runs in the window.
    public let runCount: Int
    /// Signed change: `latestRunRate - firstRunRate`.
    public let delta: Double
    /// Chronological per-run pass rates within the window (0.0–100.0).
    public let runRates: [Double]

    /// Creates a new run-rate trajectory.
    /// - Parameters:
    ///   - firstRunRate: Pass rate on the first run in the window.
    ///   - latestRunRate: Pass rate on the latest run in the window.
    ///   - runCount: Total number of runs in the window.
    ///   - delta: Signed change from first to latest.
    ///   - runRates: Chronological per-run pass rates.
    public init(firstRunRate: Double, latestRunRate: Double, runCount: Int, delta: Double, runRates: [Double]) {
        self.firstRunRate = firstRunRate
        self.latestRunRate = latestRunRate
        self.runCount = runCount
        self.delta = delta
        self.runRates = runRates
    }
}
