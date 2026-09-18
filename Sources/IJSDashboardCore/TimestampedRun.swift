import Foundation
import CorpusKit
import QualityGateTypes

/// A quality gate run anchored to its execution timestamp.
public struct TimestampedRun: Sendable {
    /// The full metadata captured during this gate execution.
    public let metadata: CheckResultMetadata

    /// Creates a timestamped run from gate metadata.
    public init(metadata: CheckResultMetadata) {
        self.metadata = metadata
    }
}

extension TimestampedRun {

    /// Each checker's most recent result across a project's **standard-mode** runs.
    ///
    /// A project's state is not the newest run. A partial invocation — one checker, run while
    /// iterating — is newer than the last full sweep, and reading it as the whole picture blanks
    /// every other checker's findings. So this composes: it walks the standard-mode runs oldest
    /// to newest and keeps the latest result *per checker*, which is the union a reader means by
    /// "where does this project stand".
    ///
    /// Filtering to `.standard` is the other half. Subset and advisory modes are deliberate
    /// narrowings, and folding them in would let a narrow run overwrite a broad one's verdict
    /// for the checkers they share.
    ///
    /// - Parameter runs: A project's runs, in any order.
    /// - Returns: One result per checker that appeared in any standard-mode run.
    public static func latestStandardResults(of runs: [TimestampedRun]) -> [CheckResult] {
        let standard = runs
            .filter { $0.metadata.gateMode == .standard }
            .sorted { $0.metadata.timestamp < $1.metadata.timestamp }
        var latestForChecker: [String: CheckResult] = [:]
        for run in standard {              // ascending — later runs overwrite earlier
            for result in run.metadata.results {
                latestForChecker[result.checkerId] = result
            }
        }
        return Array(latestForChecker.values)
    }
}
