import Foundation
import CorpusKit
import QualityGateTypes

/// One checker's most recent standard-mode result, with the facts of the run it came from.
///
/// What ``CorpusReader/latestStandardResult(of:for:)`` returns: the diagnostics behind a checker's latest pass or fail, and enough of
/// the run (when, which commit, which gate build) for them to be read, or handed to someone else, without the app that showed them.
public struct LatestCheckerResult: Sendable {
    /// The checker's result, diagnostics included.
    public let result: CheckResult
    /// The project the run belongs to.
    public let projectID: String
    /// When the run was made.
    public let timestamp: Date
    /// The commit the run was made at, when it recorded one.
    public let commitSHA: String?
    /// The gate build that made the run, when it recorded one.
    public let gateBuild: GateBuild?
    /// The mode of the run; always ``GateMode/standard`` here.
    public let gateMode: GateMode

    /// Creates a result.
    public init(
        result: CheckResult, projectID: String, timestamp: Date, commitSHA: String?, gateBuild: GateBuild?, gateMode: GateMode
    ) {
        self.result = result
        self.projectID = projectID
        self.timestamp = timestamp
        self.commitSHA = commitSHA
        self.gateBuild = gateBuild
        self.gateMode = gateMode
    }
}

/// Why a checker's latest result could not be read.
///
/// Fixed cases with no file names, paths or system text, so a caller can show or log one without carrying what the file system said.
public enum LatestResultError: Error, Equatable, Sendable {
    /// The run file that holds the result is gone, is not valid, or does not hold the checker the index says it does.
    case runFileUnreadable
}
