import Testing
import Foundation
@testable import CorpusKit

/// Integration tests for ``CorpusManager``'s git synchronization.
///
/// Moved from org-judgement-system and hardened (drift #9): the original
/// suite ran parallel with the whole test fleet, discarded git exit codes,
/// depended on the developer's global git identity, and synced against an
/// empty (unborn-branch) remote — the gate's flip detector caught three of
/// its tests flipping fail→pass on identical code. This version is
/// serialized, asserts every setup command, configures a repo-local
/// identity, and seeds the remote with an initial commit for sync tests.
@Suite("CorpusManager", .serialized)
struct CorpusManagerTests {

    // MARK: - Test Helpers

    /// Creates a bare git repo to act as a "remote" and returns its path.
    private func makeBareRemote() throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-test-\(UUID().uuidString)")
        let remotePath = base.appendingPathComponent("remote.git").path
        try FileManager.default.createDirectory(
            atPath: remotePath,
            withIntermediateDirectories: true
        )
        try runShellChecked("git", "init", "--bare", "--initial-branch=main", in: remotePath)
        return remotePath
    }

    /// Creates a bare remote seeded with one commit, so clones have a real
    /// branch head instead of an unborn branch.
    private func makeSeededRemote() throws -> String {
        let remotePath = try makeBareRemote()
        let seedClone = try cloneRemote(remotePath)
        try writeTestFile(in: seedClone, name: "seed.txt")
        try commitAll(in: seedClone, message: "seed")
        try runShellChecked("git", "push", "origin", "HEAD", in: seedClone)
        return remotePath
    }

    /// Creates an empty directory for use as a local corpus path.
    private func makeLocalDir() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-test-\(UUID().uuidString)")
            .appendingPathComponent("local")
            .path
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        return path
    }

    /// Clones a bare remote into a new directory, configures a hermetic git
    /// identity, and returns the clone path.
    private func cloneRemote(_ remotePath: String) throws -> String {
        let clonePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-test-\(UUID().uuidString)")
            .appendingPathComponent("clone")
            .path
        try runShellChecked("git", "clone", remotePath, clonePath, in: FileManager.default.temporaryDirectory.path)
        try configureIdentity(in: clonePath)
        return clonePath
    }

    /// Sets a repo-local git identity so commits never depend on global config.
    private func configureIdentity(in dir: String) throws {
        try runShellChecked("git", "config", "user.name", "CorpusKit Tests", in: dir)
        try runShellChecked("git", "config", "user.email", "tests@corpuskit.invalid", in: dir)
    }

    /// Writes a test file into a directory.
    private func writeTestFile(in dir: String, name: String = "test.json") throws {
        let filePath = (dir as NSString).appendingPathComponent(name)
        try "test content".write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    /// Commits all changes in a git repo with a given message.
    private func commitAll(in dir: String, message: String = "test commit") throws {
        try runShellChecked("git", "add", "-A", in: dir)
        try runShellChecked("git", "commit", "-m", message, in: dir)
    }

    /// Returns the latest commit message from a git repo.
    private func latestCommitMessage(in dir: String) throws -> String {
        try runShellOutput("git", "log", "-1", "--format=%s", in: dir)
    }

    /// Runs a shell command and throws if it exits non-zero — setup failures
    /// surface as test failures instead of racy downstream asserts.
    private func runShellChecked(_ args: String..., in dir: String) throws {
        let status = try runShell(args, in: dir)
        guard status == 0 else {
            throw IJSError.corpusSyncFailed(
                reason: "test setup: \(args.joined(separator: " ")) exited \(status) in \(dir)"
            )
        }
    }

    /// Runs a shell command and returns its exit status.
    private func runShell(_ args: [String], in dir: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Runs a shell command and returns trimmed stdout.
    private func runShellOutput(_ args: String..., in dir: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prepare Tests

    @Test("Prepare clones from remote when local dir is empty")
    func prepareClonesFresh() async throws {
        let remotePath = try makeBareRemote()
        let localPath = try makeLocalDir()
        // Remove the empty dir so clone can create it
        try FileManager.default.removeItem(atPath: localPath)

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        try await manager.prepare()

        let gitDir = (localPath as NSString).appendingPathComponent(".git")
        #expect(FileManager.default.fileExists(atPath: gitDir))
    }

    @Test("Prepare pulls when local repo already exists")
    func preparePullsExisting() async throws {
        let remotePath = try makeSeededRemote()
        let localPath = try cloneRemote(remotePath)

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        try await manager.prepare()

        let gitDir = (localPath as NSString).appendingPathComponent(".git")
        #expect(FileManager.default.fileExists(atPath: gitDir))
    }

    @Test("Prepare initializes git when directory exists without .git")
    func prepareInitsExistingDir() async throws {
        let remotePath = try makeBareRemote()
        let localPath = try makeLocalDir()
        try writeTestFile(in: localPath, name: "existing.txt")

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        try await manager.prepare()

        let gitDir = (localPath as NSString).appendingPathComponent(".git")
        #expect(FileManager.default.fileExists(atPath: gitDir))
    }

    // MARK: - Sync Tests

    @Test("Sync returns nothingToCommit when working tree is clean")
    func syncNothingToCommit() async throws {
        let remotePath = try makeSeededRemote()
        let localPath = try cloneRemote(remotePath)

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        let result = try await manager.sync(projectID: "test")

        #expect(result == .nothingToCommit)
    }

    @Test("Sync commits and pushes new files")
    func syncCommitsAndPushes() async throws {
        let remotePath = try makeSeededRemote()
        let localPath = try cloneRemote(remotePath)
        try writeTestFile(in: localPath, name: "telemetry.json")

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        let result = try await manager.sync(projectID: "my-project")

        guard case .pushed(let hash) = result else {
            Issue.record("Expected .pushed, got \(result)")
            return
        }
        #expect(hash.isEmpty == false)

        let verifyClone = try cloneRemote(remotePath)
        let pushed = FileManager.default.fileExists(
            atPath: (verifyClone as NSString).appendingPathComponent("telemetry.json")
        )
        #expect(pushed)
    }

    @Test("Sync uses default commit message format")
    func syncDefaultMessage() async throws {
        let remotePath = try makeSeededRemote()
        let localPath = try cloneRemote(remotePath)
        try writeTestFile(in: localPath)

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        _ = try await manager.sync(projectID: "org-judgement-system")

        let message = try latestCommitMessage(in: localPath)
        #expect(message.hasPrefix("telemetry: org-judgement-system"))
    }

    @Test("Sync uses custom commit message when provided")
    func syncCustomMessage() async throws {
        let remotePath = try makeSeededRemote()
        let localPath = try cloneRemote(remotePath)
        try writeTestFile(in: localPath)

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        _ = try await manager.sync(
            projectID: "test",
            message: "custom: weekly pulse W21"
        )

        let message = try latestCommitMessage(in: localPath)
        #expect(message == "custom: weekly pulse W21")
    }

    @Test("Sync returns commitOnly when push fails")
    func syncPushFailureNonFatal() async throws {
        let remotePath = try makeSeededRemote()
        let localPath = try cloneRemote(remotePath)
        try writeTestFile(in: localPath)

        // Point remote at an invalid URL so push fails
        try runShellChecked("git", "remote", "set-url", "origin", "/nonexistent/repo.git", in: localPath)

        let manager = CorpusManager(localPath: localPath, remoteURL: "/nonexistent/repo.git")
        let result = try await manager.sync(projectID: "test")

        guard case .commitOnly(let hash, let pushError) = result else {
            Issue.record("Expected .commitOnly, got \(result)")
            return
        }
        #expect(hash.isEmpty == false)
        #expect(pushError.isEmpty == false)
    }

    @Test("Sync rebases cleanly when remote has diverged")
    func syncRebasesOnDivergence() async throws {
        let remotePath = try makeSeededRemote()

        // Clone for "local" machine
        let localPath = try cloneRemote(remotePath)

        // Simulate another machine pushing a different file
        let otherClone = try cloneRemote(remotePath)
        try writeTestFile(in: otherClone, name: "from_other.json")
        try commitAll(in: otherClone, message: "other machine")
        try runShellChecked("git", "push", in: otherClone)

        // Local writes a different file (no content conflict)
        try writeTestFile(in: localPath, name: "from_local.json")

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)
        let result = try await manager.sync(projectID: "test")

        guard case .pushed = result else {
            Issue.record("Expected .pushed after rebase, got \(result)")
            return
        }

        // Both files should be in the final repo
        let both = FileManager.default.fileExists(
            atPath: (localPath as NSString).appendingPathComponent("from_other.json")
        )
        #expect(both)
    }

    @Test("Concurrent sync calls are serialized by actor")
    func concurrentSyncSerialized() async throws {
        let remotePath = try makeSeededRemote()
        let localPath = try cloneRemote(remotePath)

        let manager = CorpusManager(localPath: localPath, remoteURL: remotePath)

        // Write one file and fire two syncs concurrently
        try writeTestFile(in: localPath, name: "file_a.json")

        let results = try await withThrowingTaskGroup(of: SyncResult.self) { group in
            group.addTask {
                try await manager.sync(projectID: "test")
            }
            group.addTask {
                try await manager.sync(projectID: "test")
            }
            var collected: [SyncResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        // One should commit, the other should find nothing to commit
        let pushedCount = results.filter {
            if case .pushed = $0 { return true }
            return false
        }.count
        let nothingCount = results.filter { $0 == .nothingToCommit }.count
        #expect(pushedCount == 1)
        #expect(nothingCount == 1)
    }
}
