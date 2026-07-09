import Foundation
#if canImport(os)
import os
#endif

private let logger = Logger(subsystem: "com.ijs.core", category: "corpus-manager")

/// Outcome of a corpus sync operation.
public enum SyncResult: Sendable, Equatable {
    /// Nothing to commit — working tree was clean.
    case nothingToCommit
    /// Committed and pushed successfully.
    case pushed(commitHash: String)
    /// Committed locally but push failed (network error, auth, etc.).
    case commitOnly(commitHash: String, pushError: String)
}

/// Manages git synchronization for the IJS telemetry corpus.
///
/// Wraps git operations (pull, add, commit, push) around the local
/// corpus directory. The local filesystem remains the source of truth
/// for reads; git provides versioning, remote backup, and CI access.
///
/// All git operations shell out to the `git` CLI via `Process`.
/// Network failures are non-fatal — the local corpus is always usable
/// even when the remote is unreachable.
public actor CorpusManager {

    /// The local corpus directory path.
    public let localPath: String
    /// The remote git URL.
    public let remoteURL: String

    /// Creates a new corpus manager.
    /// - Parameters:
    ///   - localPath: Absolute path to the local corpus directory.
    ///   - remoteURL: Git remote URL for the corpus repository.
    public init(localPath: String, remoteURL: String) {
        self.localPath = localPath
        self.remoteURL = remoteURL
    }

    /// Ensures the local corpus is a git repository linked to the remote.
    ///
    /// If the directory exists with a `.git/` subdirectory, runs
    /// `git pull --rebase`. If the directory exists without `.git/`,
    /// initializes and adds the remote. If the directory does not exist,
    /// clones from the remote.
    ///
    /// - Throws: ``IJSError/corpusSyncFailed(reason:)`` if git operations fail.
    public func prepare() async throws {
        let fm = FileManager.default
        let gitDir = (localPath as NSString).appendingPathComponent(".git")

        // SAFETY: gitDir and localPath derived from actor-owned localPath property, not user input
        if fm.fileExists(atPath: gitDir) {
            _ = tryGit("pull", "--rebase", "--quiet")
        } else if fm.fileExists(atPath: localPath) { // SAFETY: localPath is actor-owned, not user input
            try runGit("init")
            try runGit("remote", "add", "origin", remoteURL)
        } else {
            try runGitIn(
                directory: (localPath as NSString).deletingLastPathComponent,
                args: "clone", remoteURL, (localPath as NSString).lastPathComponent
            )
        }
    }

    /// Commits and pushes all changes in the corpus to the remote.
    ///
    /// Runs: `git add -A`, `git commit`, `git pull --rebase`, `git push`.
    /// If there are no changes to commit, returns ``SyncResult/nothingToCommit``.
    /// If push fails (network), returns ``SyncResult/commitOnly(commitHash:pushError:)``
    /// — the local commit is preserved for the next sync.
    ///
    /// - Parameters:
    ///   - projectID: Project identifier for the default commit message.
    ///   - message: Commit message. Defaults to `"telemetry: <projectID> <YYYY-MM-DD>"`.
    /// - Returns: A ``SyncResult`` indicating what happened.
    public func sync(
        projectID: String,
        message: String? = nil
    ) async throws -> SyncResult {
        try runGit("add", "-A")

        let status = try runGitOutput("status", "--porcelain")
        guard !status.isEmpty else {
            return .nothingToCommit
        }

        let commitMessage = message ?? "telemetry: \(projectID) \(Self.todayString())"
        try runGit("commit", "-m", commitMessage)

        let hash = try runGitOutput("log", "-1", "--format=%h")

        // Pull may fail (e.g., no upstream yet) — still try to push
        _ = tryGit("pull", "--rebase", "--quiet")

        if let pushError = tryGit("push") {
            return .commitOnly(commitHash: hash, pushError: pushError)
        }
        return .pushed(commitHash: hash)
    }

    // MARK: - Private Helpers

    private func runGit(_ args: String...) throws {
        try runGitInArray(directory: localPath, args: args)
    }

    private func runGitIn(directory: String, args: String...) throws {
        try runGitInArray(directory: directory, args: args)
    }

    private func runGitInArray(directory: String, args: [String]) throws {
        // SAFETY: Hardcoded executable path /usr/bin/git; arguments are string literals or actor-owned properties
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw IJSError.corpusSyncFailed(
                reason: "git \(args.joined(separator: " ")) failed with exit code \(process.terminationStatus)"
            )
        }
    }

    private func runGitOutput(_ args: String...) throws -> String {
        // SAFETY: Hardcoded executable path /usr/bin/git; arguments are string literals
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: localPath)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw IJSError.corpusSyncFailed(
                reason: "git \(args.joined(separator: " ")) failed with exit code \(process.terminationStatus)"
            )
        }
        return (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tryGit(_ args: String...) -> String? {
        // SAFETY: Hardcoded executable path /usr/bin/git; arguments are string literals
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: localPath)
        process.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            logger.error("git process launch failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errStr = (String(data: errData, encoding: .utf8) ?? "unknown error")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return errStr
        }
        return nil
    }

    private static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }
}
