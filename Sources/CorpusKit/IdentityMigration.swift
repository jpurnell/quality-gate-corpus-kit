import Foundation

/// Computes manifest alias proposals for the identity migration (Phase 0.4).
///
/// The migration never moves history: it proposes `legacy-dir → identity`
/// aliases so readers union old and new directories. Applying a proposal
/// only writes `manifest.yml`.
public enum IdentityMigration {
    /// Proposes new aliases mapping legacy corpus directories to a project's
    /// stable identity.
    ///
    /// A candidate is proposed only when it has history in the corpus, is not
    /// the identity directory itself, and is not already aliased. A directory
    /// aliased to a *different* identity is a conflict for a human to resolve —
    /// it is never silently re-pointed.
    ///
    /// - Parameters:
    ///   - identityID: The stable identity slug new telemetry writes to.
    ///   - legacyCandidates: Directory names this project may have written
    ///     under before (configured ID, old basenames).
    ///   - corpusDirectories: Directory names currently present under
    ///     `telemetry/` in the corpus.
    ///   - existingAliases: The manifest's current alias map.
    /// - Returns: New aliases to merge into the manifest.
    public static func proposedAliases(
        identityID: String,
        legacyCandidates: [String],
        corpusDirectories: [String],
        existingAliases: [String: String]
    ) -> [String: String] {
        var proposal: [String: String] = [:]
        let present = Set(corpusDirectories)
        for candidate in legacyCandidates {
            guard candidate != identityID,
                  present.contains(candidate),
                  existingAliases[candidate] == nil else { continue }
            proposal[candidate] = identityID
        }
        return proposal
    }
}
