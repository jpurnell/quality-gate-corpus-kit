import Foundation
import Testing
@testable import CorpusKit

@Suite("Project identity resolution (0.4)")
struct ProjectIdentityTests {

    // MARK: Remote URL normalization

    @Test("normalizes SSH scp-style remotes", arguments: [
        ("git@github.com:jpurnell/quality-gate-swift.git", "jpurnell__quality-gate-swift", "github.com/jpurnell/quality-gate-swift"),
        ("git@github.com:jpurnell/WineTaster.git", "jpurnell__WineTaster", "github.com/jpurnell/WineTaster"),
        ("git@git.corp.example.com:team/proj.git", "team__proj", "git.corp.example.com/team/proj"),
    ])
    func normalizesSCPStyle(url: String, slug: String, normalized: String) throws {
        let result = try #require(ProjectIdentity.normalizeRemote(url))
        #expect(result.slug == slug)
        #expect(result.normalized == normalized)
    }

    @Test("normalizes HTTPS remotes with and without .git and trailing slash", arguments: [
        ("https://github.com/jpurnell/quality-gate-swift.git", "jpurnell__quality-gate-swift"),
        ("https://github.com/jpurnell/quality-gate-swift", "jpurnell__quality-gate-swift"),
        ("https://github.com/jpurnell/quality-gate-swift/", "jpurnell__quality-gate-swift"),
        // SAFETY: Fixture string, never fetched — this case exists to pin down that a plaintext-HTTP remote still normalizes correctly [CWE-319].
        ("http://git.internal.example.com/org/repo.git", "org__repo"),
    ])
    func normalizesHTTPS(url: String, slug: String) throws {
        let result = try #require(ProjectIdentity.normalizeRemote(url))
        #expect(result.slug == slug)
    }

    @Test("normalizes ssh:// scheme remotes")
    func normalizesSSHScheme() throws {
        let result = try #require(ProjectIdentity.normalizeRemote("ssh://git@github.com/jpurnell/quality-gate-swift.git"))
        #expect(result.slug == "jpurnell__quality-gate-swift")
        #expect(result.normalized == "github.com/jpurnell/quality-gate-swift")
    }

    @Test("keeps deeper paths (GitLab subgroups) distinct in the slug")
    func normalizesSubgroups() throws {
        let result = try #require(ProjectIdentity.normalizeRemote("git@gitlab.com:team/sub/repo.git"))
        #expect(result.slug == "team__sub__repo")
        #expect(result.normalized == "gitlab.com/team/sub/repo")
    }

    @Test("host casing is normalized but path casing is preserved")
    func hostLowercased() throws {
        let result = try #require(ProjectIdentity.normalizeRemote("git@GitHub.com:JPurnell/Repo.git"))
        #expect(result.normalized == "github.com/JPurnell/Repo")
        #expect(result.slug == "JPurnell__Repo")
    }

    @Test("rejects remotes without a usable path", arguments: ["", "git@github.com:", "https://github.com/", "not a url"])
    func rejectsUnusable(url: String) {
        #expect(ProjectIdentity.normalizeRemote(url) == nil)
    }

    // MARK: Resolution chain

    @Test("explicit config projectID always wins")
    func explicitWins() {
        let identity = ProjectIdentity.resolve(
            explicitID: "my-project",
            remoteURL: "git@github.com:jpurnell/other.git",
            directoryName: "other")
        #expect(identity.id == "my-project")
        #expect(identity.source == .explicitConfig)
        #expect(identity.remote == nil)
    }

    @Test("remote-derived identity is used when no explicit ID is configured")
    func remoteWins() {
        let identity = ProjectIdentity.resolve(
            explicitID: nil,
            remoteURL: "git@github.com:jpurnell/quality-gate-swift.git",
            directoryName: "quality-gate-swift copy 2")
        #expect(identity.id == "jpurnell__quality-gate-swift")
        #expect(identity.source == .remote)
        #expect(identity.remote == "github.com/jpurnell/quality-gate-swift")
    }

    @Test("falls back to directory basename when there is no remote")
    func basenameFallback() {
        let identity = ProjectIdentity.resolve(explicitID: nil, remoteURL: nil, directoryName: "WineTaster 4")
        #expect(identity.id == "WineTaster 4")
        #expect(identity.source == .basename)
        #expect(identity.remote == nil)
    }

    @Test("an unparseable remote degrades to the basename fallback")
    func unparseableRemoteFallsBack() {
        let identity = ProjectIdentity.resolve(explicitID: nil, remoteURL: "not a url", directoryName: "local-project")
        #expect(identity.id == "local-project")
        #expect(identity.source == .basename)
    }

    @Test("acceptance: two checkouts of one repo resolve to one identity; two projects sharing a basename resolve to two")
    func acceptanceIdentityStability() {
        let checkoutA = ProjectIdentity.resolve(
            explicitID: nil, remoteURL: "git@github.com:jpurnell/WineTaster.git", directoryName: "WineTaster")
        let checkoutB = ProjectIdentity.resolve(
            explicitID: nil, remoteURL: "git@github.com:jpurnell/WineTaster.git", directoryName: "WineTaster 4")
        #expect(checkoutA.id == checkoutB.id)

        let forkC = ProjectIdentity.resolve(
            explicitID: nil, remoteURL: "git@github.com:otheruser/WineTaster.git", directoryName: "WineTaster")
        #expect(forkC.id != checkoutA.id)
    }
}

@Suite("Manifest aliases and reader union (0.4)")
struct ManifestAliasTests {

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alias-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("manifest round-trips an aliases section")
    func aliasRoundTrip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) } // silent: best-effort temp cleanup
        let url = dir.appendingPathComponent("manifest.yml")

        var manifest = CorpusManifest()
        manifest.aliases = ["WineTaster 4": "jpurnell__WineTaster", "old-dir": "jpurnell__repo"]
        try manifest.save(to: url)

        let loaded = try CorpusManifest.load(from: url)
        #expect(loaded.aliases == manifest.aliases)
    }

    @Test("a manifest without an aliases section loads with no aliases")
    func missingAliasesSection() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) } // silent: best-effort temp cleanup
        let url = dir.appendingPathComponent("manifest.yml")
        try "projects:\n".write(to: url, atomically: true, encoding: .utf8)

        let loaded = try CorpusManifest.load(from: url)
        #expect(loaded.aliases.isEmpty)
    }

    @Test("directories(for:) is the union of the identity dir and its aliases, identity first")
    func directoryUnion() {
        var manifest = CorpusManifest()
        manifest.aliases = [
            "WineTaster 4": "jpurnell__WineTaster",
            "WineTaster-old": "jpurnell__WineTaster",
            "unrelated": "someone__else",
        ]
        let dirs = manifest.directories(for: "jpurnell__WineTaster")
        #expect(dirs == ["jpurnell__WineTaster", "WineTaster 4", "WineTaster-old"])
        #expect(manifest.directories(for: "no-aliases") == ["no-aliases"])
    }

    @Test("union read merges metadata across the identity dir and aliased dirs, sorted by timestamp")
    func unionRead() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) } // silent: best-effort temp cleanup

        let writer = TelemetryWriter()
        let early = Date(timeIntervalSince1970: 1_777_000_000)
        let late = early.addingTimeInterval(3600)

        // History under the legacy basename dir; new run under the identity dir.
        let legacyPath = CorpusPath(basePath: dir.path, projectID: "WineTaster 4")
        let identityPath = CorpusPath(basePath: dir.path, projectID: "jpurnell__WineTaster")
        try await writer.write(metadata: makeMetadata(projectID: "WineTaster 4", timestamp: early), calibrations: [], to: legacyPath)
        try await writer.write(metadata: makeMetadata(projectID: "jpurnell__WineTaster", timestamp: late), calibrations: [], to: identityPath)

        var manifest = CorpusManifest()
        manifest.aliases = ["WineTaster 4": "jpurnell__WineTaster"]

        let union = try await writer.readMetadataUnion(
            identity: "jpurnell__WineTaster", basePath: dir.path, manifest: manifest,
            startDate: early.addingTimeInterval(-60), endDate: late.addingTimeInterval(60))
        #expect(union.count == 2)
        #expect(union.first?.timestamp == early)
        #expect(union.last?.timestamp == late)
    }

    private func makeMetadata(projectID: String, timestamp: Date) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: projectID, timestamp: timestamp, environment: .local,
            decisionOwner: "o", results: [], overrides: [], riskTier: .informational,
            ethicalFlags: [], consistencyScore: nil)
    }
}
