import Foundation

/// A gate run's identity as attested by a CI provider (Phase 2, CI parity).
///
/// The first identity in the ecosystem verified by an external system rather
/// than asserted: the provider binds the actor, workflow run, commit, and
/// repository. Local runs never carry one — their identity stays asserted
/// (`decisionOwner` + `host`), and the second-writer tripwire treats the two
/// classes accordingly.
public struct CIIdentity: Sendable, Codable, Equatable {
    /// The CI system that attested this run (e.g. `"github-actions"`).
    public let provider: String
    /// The user the provider says triggered the run.
    public let actor: String
    /// The provider's unique identifier for this workflow run.
    public let workflowRunID: String
    /// The commit the run executed against.
    public let commit: String
    /// The repository the run executed in (e.g. `"jpurnell/quality-gate-swift"`).
    public let repository: String

    /// Creates a CI identity record.
    /// - Parameters:
    ///   - provider: The CI system that attested this run.
    ///   - actor: The user the provider says triggered the run.
    ///   - workflowRunID: The provider's unique run identifier.
    ///   - commit: The commit the run executed against.
    ///   - repository: The repository the run executed in.
    public init(
        provider: String,
        actor: String,
        workflowRunID: String,
        commit: String,
        repository: String
    ) {
        self.provider = provider
        self.actor = actor
        self.workflowRunID = workflowRunID
        self.commit = commit
        self.repository = repository
    }
}
