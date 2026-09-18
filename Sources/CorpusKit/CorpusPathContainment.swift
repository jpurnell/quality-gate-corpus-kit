import Foundation

/// The single hardened corpus-base containment check, shared by every writer.
///
/// Every writer that turns a computed corpus path into a filesystem URL must
/// guarantee the target stays inside the corpus base — otherwise a crafted
/// `projectID`, slug, or label could escape it. This logic used to be
/// copy-pasted (and independently buggy) across writers; it now lives here once.
///
/// Containment is checked **lexically and component-wise**: both paths are
/// standardized to collapse `.`/`..` without touching the filesystem, and the
/// base's path components must be an exact prefix of the target's. This avoids
/// two failure modes of a naive `hasPrefix` on symlink-resolved strings:
///
/// - **Symlinked-base false rejection.** `resolvingSymlinksInPath()`
///   canonicalizes an existing base and a not-yet-created target subtree
///   asymmetrically (e.g. `/tmp` ↔ `/private/tmp`), so string prefixing
///   spuriously fails.
/// - **Prefix-sibling escape.** String `hasPrefix` treats `/a/corpus-evil` as
///   inside `/a/corpus`; component comparison rejects it.
///
/// The validated relative suffix is then re-anchored onto the base resolved once
/// via `resolvingSymlinksInPath()`, so the returned URL points at the real
/// location even when the base is reached through a symlink.
extension CorpusPath {

    /// Whether `path` resolves to a location contained within `basePath`.
    ///
    /// Pure and lexical — no filesystem access, no symlink resolution — so it is
    /// symmetric between existing and not-yet-created paths.
    ///
    /// - Parameters:
    ///   - path: The candidate absolute path.
    ///   - basePath: The corpus base the path must stay within.
    /// - Returns: `true` when `path` is `basePath` or a descendant of it.
    /// Whether an identifier is a single, safe path component.
    ///
    /// A corpus identifier — a `projectID`, a pulse label, a slug — names **one** directory.
    /// ``CorpusPath`` already models it that way. Anything carrying a separator or a relative
    /// component is not an identifier that happened to be malformed; it is a path, and
    /// resolving it is how `../../elsewhere` becomes a read outside the corpus.
    ///
    /// ## Why this is checked where the value is consumed
    ///
    /// Containment (``CorpusPath/contains(_:within:)``) catches an escape after the path is built, and is
    /// the backstop. This catches the *input* before it becomes a path, which produces a better
    /// failure: "that is not a project id" rather than "nothing found there". A caller that sees
    /// the second learns nothing and often retries.
    ///
    /// Added 2026-09-17 after a crafted `project_id` from an MCP tool call read a different
    /// corpus through `loadRuns(for:)` and returned a valid-looking consistency score. The
    /// readers had no containment because their doc said containment was for *writers* — true
    /// when only writers took computed input, and false once a network-facing server passed
    /// client strings to a reader.
    public static func isSingleComponent(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        guard !identifier.contains("/"), !identifier.contains("\\") else { return false }
        guard !identifier.contains("\0") else { return false }
        guard identifier != ".", identifier != ".." else { return false }
        return true
    }

    /// Throws unless `identifier` is a single, safe path component.
    ///
    /// - Parameters:
    ///   - identifier: The candidate identifier.
    ///   - label: What the identifier is, for the error message — "project id", "pulse label".
    /// - Throws: ``IJSError/telemetryWriteFailed(reason:)`` naming the rejected value.
    public static func requireSingleComponent(_ identifier: String, label: String) throws {
        guard isSingleComponent(identifier) else {
            throw IJSError.telemetryWriteFailed(
                reason: "\(label) '\(identifier)' is not a single path component")
        }
    }

    public static func contains(_ path: String, within basePath: String) -> Bool {
        let baseComponents = URL(fileURLWithPath: basePath).standardized.pathComponents
        let targetComponents = URL(fileURLWithPath: path).standardized.pathComponents
        return targetComponents.count >= baseComponents.count
            && Array(targetComponents.prefix(baseComponents.count)) == baseComponents
    }

    /// Validates that `path` is contained within `basePath` and returns a
    /// filesystem URL anchored on the base resolved once via `resolvingSymlinksInPath()`.
    ///
    /// - Parameters:
    ///   - path: The candidate absolute path.
    ///   - basePath: The corpus base the path must stay within.
    /// - Returns: A URL for `path` whose leading components are the symlink-resolved base.
    /// - Throws: ``IJSError/telemetryWriteFailed(reason:)`` if `path` escapes `basePath`.
    public static func resolvedURL(for path: String, within basePath: String) throws -> URL {
        let baseComponents = URL(fileURLWithPath: basePath).standardized.pathComponents
        let targetComponents = URL(fileURLWithPath: path).standardized.pathComponents

        guard targetComponents.count >= baseComponents.count,
              Array(targetComponents.prefix(baseComponents.count)) == baseComponents else {
            throw IJSError.telemetryWriteFailed(reason: "Path \(path) escapes corpus base \(basePath)")
        }

        var resolved = URL(fileURLWithPath: basePath).resolvingSymlinksInPath()
        for component in targetComponents.dropFirst(baseComponents.count) {
            resolved.appendPathComponent(component)
        }
        return resolved
    }

    /// Whether `path` resolves to a location contained within this corpus's ``basePath``.
    ///
    /// - Parameter path: The candidate absolute path.
    /// - Returns: `true` when `path` is inside this corpus's base.
    public func contains(_ path: String) -> Bool {
        Self.contains(path, within: basePath)
    }

    /// Validates that `path` is contained within this corpus's ``basePath`` and
    /// returns the symlink-anchored URL.
    ///
    /// - Parameter path: The candidate absolute path.
    /// - Returns: A URL for `path` whose leading components are the symlink-resolved base.
    /// - Throws: ``IJSError/telemetryWriteFailed(reason:)`` if `path` escapes this corpus's base.
    public func resolvedURL(forContainedPath path: String) throws -> URL {
        try Self.resolvedURL(for: path, within: basePath)
    }
}
