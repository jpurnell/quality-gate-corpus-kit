import Foundation
#if canImport(os)
import os
#endif

/// A corpus artifact that carries its schema version (Phase 0.5).
///
/// Every artifact serialized into the corpus stamps
/// ``currentSchemaVersion`` when written. Artifacts written before
/// versioning existed decode as version 1. The reader policy is asymmetric
/// by design:
///
/// - `version <= current`: decode with declared tolerance (absent newer
///   fields take their documented defaults).
/// - `version > current`: **skip the artifact entirely** — never half-decode
///   a future shape (a skipped artifact is visible; a silently mis-read one
///   is corruption).
///
/// Bump rules (documented here as the canonical reference): adding an
/// optional/defaulted field is **not** a bump; a semantic change or a new
/// required field **is** a bump plus explicit handling in the reader.
public protocol VersionedCorpusArtifact: Codable, Sendable {
    /// The schema version this build writes.
    static var currentSchemaVersion: Int { get }
    /// The schema version this artifact was written with.
    var schemaVersion: Int { get }
}

/// The uniform reader policy for versioned corpus artifacts.
public enum CorpusSchema {
    private static let logger = Logger(subsystem: "com.quality-gate", category: "CorpusSchema")

    /// The outcome of a policy-checked decode.
    public enum DecodeOutcome<T: VersionedCorpusArtifact>: Sendable where T: Sendable {
        /// Decoded within the supported range.
        case decoded(T)
        /// Written by a newer build — skipped, never half-decoded.
        case skippedNewer(artifactVersion: Int, supported: Int)
    }

    /// Decodes an artifact under the version policy.
    ///
    /// - Returns: `.decoded` when the artifact's version is within range,
    ///   `.skippedNewer` (with a logged note naming the file) when it was
    ///   written by a newer build.
    /// - Throws: decoding errors for genuinely malformed data — a *newer*
    ///   artifact is not an error, but garbage still is.
    public static func decode<T: VersionedCorpusArtifact>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder,
        origin: String = "<unknown>"
    ) throws -> DecodeOutcome<T> {
        // Peek the version without committing to the full shape.
        let peeked = try decoder.decode(SchemaVersionPeek.self, from: data)
        let version = peeked.schemaVersion ?? 1
        guard version <= T.currentSchemaVersion else {
            logger.notice("corpus.schema-newer: \(origin, privacy: .public) is schema v\(version, privacy: .public) but this build supports up to v\(T.currentSchemaVersion, privacy: .public) — skipped, not half-decoded")
            return .skippedNewer(artifactVersion: version, supported: T.currentSchemaVersion)
        }
        return .decoded(try decoder.decode(T.self, from: data))
    }

    /// Minimal envelope for reading the version field alone.
    private struct SchemaVersionPeek: Decodable {
        let schemaVersion: Int?
    }
}
