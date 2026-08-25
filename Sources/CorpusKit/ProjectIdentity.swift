import Foundation
#if canImport(os)
import os
#endif

/// A stable project identity for corpus telemetry (Phase 0.4, retires L4).
///
/// Directory basenames fork history on rename and merge unrelated projects
/// on collision. The resolution chain instead prefers, in order:
///
/// 1. An explicit `consistency.projectID` from configuration.
/// 2. The normalized `origin` remote, slugged as `org__repo` — forks differ
///    by org, so they get distinct identities by construction.
/// 3. The directory basename, recorded as a *weak* identity
///    (``Source/basename``) so the corpus can tell strong from weak.
public struct ProjectIdentity: Sendable, Equatable {
    /// How the identity was derived, recorded in telemetry metadata.
    public enum Source: String, Sendable, Codable {
        /// Explicit `consistency.projectID` configuration.
        case explicitConfig = "config"
        /// Derived from the normalized git `origin` remote.
        case remote
        /// Weak fallback: the working directory basename.
        case basename
    }

    private static let logger = Logger(subsystem: "com.quality-gate", category: "ProjectIdentity")

    /// The identity slug used as the corpus directory name.
    public let id: String
    /// How this identity was derived.
    public let source: Source
    /// The full normalized remote (`host/org/repo`), when derived from one.
    public let remote: String?

    /// Creates an identity directly. Prefer ``resolve(explicitID:remoteURL:directoryName:)``.
    public init(id: String, source: Source, remote: String? = nil) {
        self.id = id
        self.source = source
        self.remote = remote
    }

    /// Normalizes a git remote URL to a `host/org/repo` form plus an
    /// `org__repo` identity slug.
    ///
    /// Handles scp-style SSH (`git@host:org/repo.git`), `ssh://`, `http(s)://`,
    /// trailing slashes, and `.git` suffixes. Deeper paths (e.g. GitLab
    /// subgroups) keep every component in the slug. The host is lowercased;
    /// path casing is preserved.
    ///
    /// - Returns: `nil` when no host and at least one path component can be
    ///   extracted — callers degrade to the basename fallback.
    public static func normalizeRemote(_ url: String) -> (slug: String, normalized: String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var host = ""
        var path = ""
        if let schemeRange = trimmed.range(of: "://") {
            // ssh://git@host/org/repo.git or http(s)://host/org/repo.git
            let rest = String(trimmed[schemeRange.upperBound...])
            let hostAndPath = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard hostAndPath.count == 2 else { return nil }
            host = String(hostAndPath[0])
            path = String(hostAndPath[1])
        } else if let colonIndex = trimmed.firstIndex(of: ":"), trimmed.contains("@") {
            // scp-style: git@host:org/repo.git
            host = String(trimmed[..<colonIndex])
            path = String(trimmed[trimmed.index(after: colonIndex)...])
        } else {
            return nil
        }

        // Drop the user@ prefix from the host portion.
        if let atIndex = host.lastIndex(of: "@") {
            host = String(host[host.index(after: atIndex)...])
        }
        host = host.lowercased()
        guard !host.isEmpty, host.contains(".") else { return nil }

        if path.hasSuffix("/") { path = String(path.dropLast()) }
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy({ !$0.contains(" ") }) else { return nil }

        return (slug: components.joined(separator: "__"),
                normalized: "\(host)/\(components.joined(separator: "/"))")
    }

    /// Resolves a project identity through the precedence chain:
    /// explicit config → normalized remote → directory basename.
    ///
    /// The basename fallback logs a one-line notice so weak identities are
    /// visible without blocking anything.
    public static func resolve(
        explicitID: String?,
        remoteURL: String?,
        directoryName: String
    ) -> ProjectIdentity {
        if let explicitID, !explicitID.isEmpty {
            return ProjectIdentity(id: explicitID, source: .explicitConfig)
        }
        if let remoteURL, let normalized = normalizeRemote(remoteURL) {
            return ProjectIdentity(id: normalized.slug, source: .remote, remote: normalized.normalized)
        }
        logger.notice("identity.basename-fallback: no usable git remote — using directory basename '\(directoryName, privacy: .public)' as a weak project identity")
        return ProjectIdentity(id: directoryName, source: .basename)
    }

    /// Resolves the identity for a checkout on disk, reading the `origin`
    /// remote from git when available.
    public static func resolve(cwd: URL, explicitID: String?) -> ProjectIdentity {
        resolve(explicitID: explicitID,
                remoteURL: originRemoteURL(cwd: cwd),
                directoryName: cwd.lastPathComponent)
    }

    /// Bound for the local `git remote get-url` probe. Purely local, so a run
    /// that takes longer than this is wedged rather than slow.
    private static let gitTimeoutSeconds: TimeInterval = 30

    /// Reads the `origin` remote URL for the repository containing `cwd`,
    /// or `nil` when git is unavailable or the directory is not a repo.
    public static func originRemoteURL(cwd: URL) -> String? {
        let result: ProcessResult
        do {
            // SAFETY: Fixed executable (/usr/bin/env) and fixed argv; the only dynamic value is cwd.path, passed as git's -C argument (not shell-interpreted), so no command injection [CWE-78].
            result = try ProcessRunner.run(
                "/usr/bin/env",
                arguments: ["git", "-C", cwd.path, "remote", "get-url", "origin"],
                timeout: gitTimeoutSeconds
            )
        } catch {
            logger.notice("identity.git-unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard result.succeeded else { return nil }
        let url = result.standardOutputText
        return url.isEmpty ? nil : url
    }
}
