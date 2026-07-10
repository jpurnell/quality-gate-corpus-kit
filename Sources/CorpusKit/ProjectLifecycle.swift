import Foundation
#if canImport(os)
import os
#endif
import Yams

/// The lifecycle state of a project within the corpus.
///
/// Projects start as ``active`` and may be moved to ``sunset``
/// when they are no longer under active development. The lifecycle
/// state is stored in the corpus manifest (`manifest.yml`).
public enum ProjectLifecycle: String, Sendable, Codable, Equatable, CaseIterable {
    /// The project is actively maintained and included in portfolio metrics.
    case active
    /// The project has been retired and excluded from active portfolio counts.
    case sunset
}

/// A single entry in the corpus manifest describing a project's lifecycle state.
///
/// This is a read-only model. Full mutation of the manifest is handled
/// by the org-judgement-system CLI.
public struct CorpusManifestEntry: Sendable, Codable, Equatable {
    /// The lifecycle state of the project.
    public let lifecycle: ProjectLifecycle
    /// Optional reason for the lifecycle state (e.g., why a project was sunset).
    public let reason: String?
    /// When the lifecycle state was last changed.
    public let changedAt: Date
    /// Optional tier override. When set, the pulse refiner uses this instead of auto-classification.
    public let tierOverride: ProjectTier?

    /// Creates a new manifest entry.
    /// - Parameters:
    ///   - lifecycle: The lifecycle state of the project.
    ///   - reason: Optional reason for the lifecycle state.
    ///   - changedAt: When the lifecycle state was last changed.
    ///   - tierOverride: Optional tier override for manual classification.
    public init(lifecycle: ProjectLifecycle, reason: String? = nil, changedAt: Date, tierOverride: ProjectTier? = nil) {
        self.lifecycle = lifecycle
        self.reason = reason
        self.changedAt = changedAt
        self.tierOverride = tierOverride
    }
}

/// Legacy name for ``CorpusManifestEntry`` (org-judgement-system heritage).
public typealias ProjectEntry = CorpusManifestEntry

/// A corpus manifest mapping project IDs to their lifecycle metadata.
///
/// Stored as `manifest.yml` in the corpus root. Projects not present
/// in the manifest are assumed to be ``ProjectLifecycle/active``.
public struct CorpusManifest: Sendable, Codable, Equatable {
    private static let logger = Logger(subsystem: "com.quality-gate", category: "CorpusManifest")
    /// Per-project lifecycle entries keyed by project ID.
    public var projects: [String: CorpusManifestEntry]

    /// Project group definitions keyed by group name.
    /// Each value is an array of project IDs belonging to that group.
    public var groups: [String: [String]]

    /// Identity aliases: legacy corpus directory name → stable identity.
    ///
    /// History stays in the legacy directory (no mass migration); readers
    /// take the union of a project's identity directory and its aliases.
    public var aliases: [String: String]

    /// Creates a new manifest.
    /// - Parameters:
    ///   - projects: Per-project lifecycle entries keyed by project ID.
    ///   - groups: Project group definitions keyed by group name.
    ///   - aliases: Legacy directory → identity map for corpus reads.
    public init(
        projects: [String: CorpusManifestEntry] = [:],
        groups: [String: [String]] = [:],
        aliases: [String: String] = [:]
    ) {
        self.projects = projects
        self.groups = groups
        self.aliases = aliases
    }

    /// Returns the corpus directory names holding a project's history:
    /// the identity directory first, then its aliased legacy directories.
    /// - Parameter identity: The stable project identity.
    /// - Returns: Directory names in deterministic order.
    public func directories(for identity: String) -> [String] {
        [identity] + aliases.filter { $0.value == identity }.keys.sorted()
    }

    /// Returns the lifecycle state for a project, defaulting to ``ProjectLifecycle/active``.
    /// - Parameter projectID: The project identifier to look up.
    /// - Returns: The project's lifecycle state, or `.active` if not in the manifest.
    public func lifecycle(for projectID: String) -> ProjectLifecycle {
        projects[projectID]?.lifecycle ?? .active
    }

    /// Updates a project's lifecycle state, preserving any tier override.
    /// - Parameters:
    ///   - lifecycle: The new lifecycle state.
    ///   - projectID: The project identifier.
    ///   - reason: Optional human-readable reason for the change.
    ///   - date: Timestamp of the change (defaults to now).
    public mutating func setLifecycle(
        _ lifecycle: ProjectLifecycle,
        for projectID: String,
        reason: String?,
        at date: Date = Date()
    ) {
        projects[projectID] = CorpusManifestEntry(
            lifecycle: lifecycle,
            reason: reason,
            changedAt: date,
            tierOverride: projects[projectID]?.tierOverride
        )
    }

    /// All project IDs with a given lifecycle.
    /// - Parameter lifecycle: The lifecycle state to filter by.
    /// - Returns: Project IDs matching the given state, in no guaranteed order.
    public func projectIDs(matching lifecycle: ProjectLifecycle) -> [String] {
        projects.compactMap { key, entry in
            entry.lifecycle == lifecycle ? key : nil
        }
    }

    /// Returns the group name for a project ID, or nil if ungrouped.
    /// - Parameter projectID: The project identifier to look up.
    /// - Returns: The group name containing this project, or `nil` if ungrouped.
    public func group(for projectID: String) -> String? {
        for (groupName, members) in groups {
            if members.contains(projectID) {
                return groupName
            }
        }
        return nil
    }

    /// Loads a manifest from a YAML file at the given URL.
    ///
    /// Returns an empty manifest (all projects treated as active) if the
    /// file does not exist.
    ///
    /// - Parameter url: The file URL of the `manifest.yml` file.
    /// - Returns: The decoded manifest.
    /// - Throws: ``IJSError/configurationError(reason:)`` if the file exists but cannot be parsed.
    public static func load(from url: URL) throws -> CorpusManifest {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { // SAFETY: read-only check on configured path
            return CorpusManifest()
        }

        let yamlString: String
        do {
            yamlString = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw IJSError.configurationError(reason: "Cannot read manifest: \(error.localizedDescription)")
        }

        let root: [String: Any]
        do {
            guard let parsed = try Yams.load(yaml: yamlString) as? [String: Any] else {
                throw IJSError.configurationError(reason: "Invalid YAML structure in manifest")
            }
            root = parsed
        } catch let ijsError as IJSError {
            throw ijsError
        } catch {
            logger.warning("Failed to parse manifest YAML: \(error.localizedDescription, privacy: .public)")
            throw IJSError.configurationError(reason: "Invalid YAML structure in manifest: \(error.localizedDescription)")
        }

        // Parse groups section (may exist even without projects)
        let parsedGroups: [String: [String]]
        if let groupsSection = root["groups"] as? [String: [Any]] {
            var groupMap: [String: [String]] = [:]
            for (groupName, memberList) in groupsSection {
                groupMap[groupName] = memberList.compactMap { $0 as? String }
            }
            parsedGroups = groupMap
        } else {
            parsedGroups = [:]
        }

        // Parse aliases section (legacy directory name → identity).
        let parsedAliases: [String: String]
        if let aliasesSection = root["aliases"] as? [String: Any] {
            parsedAliases = aliasesSection.compactMapValues { $0 as? String }
        } else {
            parsedAliases = [:]
        }

        guard let projectsSection = root["projects"] as? [String: Any] else {
            // Empty or missing projects section is valid — all projects are active
            return CorpusManifest(groups: parsedGroups, aliases: parsedAliases)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [String: CorpusManifestEntry] = [:]
        for (projectID, value) in projectsSection {
            guard let entryDict = value as? [String: Any] else { continue }
            guard let lifecycleRaw = entryDict["lifecycle"] as? String,
                  let lifecycle = ProjectLifecycle(rawValue: lifecycleRaw) else { continue }
            let changedAt: Date
            if let changedAtDate = entryDict["changedAt"] as? Date {
                changedAt = changedAtDate
            } else if let changedAtString = entryDict["changedAt"] as? String {
                let iso8601Formatter = ISO8601DateFormatter()
                iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = iso8601Formatter.date(from: changedAtString) {
                    changedAt = parsed
                } else {
                    let fallbackFormatter = ISO8601DateFormatter()
                    fallbackFormatter.formatOptions = [.withInternetDateTime]
                    guard let fallbackParsed = fallbackFormatter.date(from: changedAtString) else {
                        continue
                    }
                    changedAt = fallbackParsed
                }
            } else {
                continue
            }

            let reason = entryDict["reason"] as? String
            let tierOverride: ProjectTier?
            if let tierRaw = entryDict["tierOverride"] as? String {
                tierOverride = ProjectTier(rawValue: tierRaw)
            } else {
                tierOverride = nil
            }
            entries[projectID] = CorpusManifestEntry(
                lifecycle: lifecycle,
                reason: reason,
                changedAt: changedAt,
                tierOverride: tierOverride
            )
        }

        return CorpusManifest(projects: entries, groups: parsedGroups, aliases: parsedAliases)
    }

    /// Saves the manifest to a YAML file, preserving the expected format.
    ///
    /// - Parameter url: The file URL to write the manifest to.
    /// - Throws: An error if the file cannot be written.
    public func save(to url: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines: [String] = []
        lines.append("# Generated by quality-gate")
        lines.append("# Re-run generate-manifest to pick up new projects. Groups are preserved.")
        lines.append("")
        lines.append("projects:")

        for projectID in projects.keys.sorted() {
            guard let entry = projects[projectID] else { continue }
            lines.append("  \(projectID):")
            lines.append("    lifecycle: \(entry.lifecycle.rawValue)")
            lines.append("    changedAt: \"\(formatter.string(from: entry.changedAt))\"")
            if let reason = entry.reason {
                lines.append("    reason: \"\(reason)\"")
            }
            if let tierOverride = entry.tierOverride {
                lines.append("    tierOverride: \(tierOverride.rawValue)")
            }
        }

        lines.append("")
        lines.append("groups:")

        if groups.isEmpty {
            lines.append("  # No groups defined")
        } else {
            for groupName in groups.keys.sorted() {
                let members = groups[groupName] ?? []
                lines.append("  \(groupName):")
                for member in members.sorted() {
                    lines.append("    - \(member)")
                }
            }
        }

        if !aliases.isEmpty {
            lines.append("")
            lines.append("aliases:")
            for legacyDir in aliases.keys.sorted() {
                guard let identity = aliases[legacyDir] else { continue }
                lines.append("  \"\(legacyDir)\": \"\(identity)\"")
            }
        }

        lines.append("")
        let yaml = lines.joined(separator: "\n")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
