import Foundation

/// The build identity of the gate binary that produced an artifact (Phase 0.6).
///
/// A stale installed binary silently runs old rules; stamping the build into
/// telemetry makes staleness visible from the corpus side. Optional on
/// ``CheckResultMetadata`` — its addition is not a schema bump.
public struct GateBuild: Sendable, Codable, Equatable {
    /// Git commit the binary was built from.
    public let commit: String
    /// ISO8601 build timestamp.
    public let buildDate: String

    /// Creates a build identity.
    /// - Parameters:
    ///   - commit: Git commit the binary was built from.
    ///   - buildDate: ISO8601 build timestamp.
    public init(commit: String, buildDate: String) {
        self.commit = commit
        self.buildDate = buildDate
    }
}
