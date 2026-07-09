import Foundation

/// Records a quality-gate skip event with an issue reference for accountability.
public struct SkipRecord: VersionedCorpusArtifact, Equatable {
    /// The corpus schema version this build writes.
    public static let currentSchemaVersion = 1

    /// The corpus schema version this artifact was written with.
    public let schemaVersion: Int
    /// Project identifier.
    public let projectID: String
    /// When the skip occurred.
    public let timestamp: Date
    /// Issue URL or reference justifying the skip.
    public let issueReference: String
    /// Who triggered the skip.
    public let author: String
    /// Execution environment (local or CI).
    public let environment: Environment

    /// Creates a new skip record.
    public init(
        projectID: String,
        timestamp: Date,
        issueReference: String,
        author: String,
        environment: Environment
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.projectID = projectID
        self.timestamp = timestamp
        self.issueReference = issueReference
        self.author = author
        self.environment = environment
    }

    /// Decodes a record, treating pre-versioning artifacts as schema v1.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        projectID = try container.decode(String.self, forKey: .projectID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        issueReference = try container.decode(String.self, forKey: .issueReference)
        author = try container.decode(String.self, forKey: .author)
        environment = try container.decode(Environment.self, forKey: .environment)
    }
}
