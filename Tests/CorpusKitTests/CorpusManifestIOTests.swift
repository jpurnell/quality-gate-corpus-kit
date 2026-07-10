import Testing
import Foundation
@testable import CorpusKit

@Suite("CorpusManifest I/O")
struct CorpusManifestIOTests {

    // MARK: - CorpusPath.manifestPath

    @Test("manifestPath returns basePath/manifest.yml")
    func manifestPath() {
        let corpus = CorpusPath(basePath: "/tmp/corpus", projectID: "test")
        #expect(corpus.manifestPath == "/tmp/corpus/manifest.yml")
    }

    @Test("manifestPath with trailing slash in basePath")
    func manifestPathTrailingSlash() {
        let corpus = CorpusPath(basePath: "/tmp/corpus/", projectID: "test")
        #expect(corpus.manifestPath.hasSuffix("manifest.yml"))
    }

    // MARK: - TelemetryWriter manifest round-trip

    @Test("Write then load manifest round-trips")
    func writeAndLoadManifest() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ijs-manifest-test-\(UUID().uuidString)")
        // SAFETY: Path is within system temp; cleaned up after test
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let now = Date(timeIntervalSince1970: 1_747_500_000)
        let manifest = CorpusManifest(projects: [
            "project-a": ProjectEntry(lifecycle: .active, reason: nil, changedAt: now),
            "project-b": ProjectEntry(lifecycle: .sunset, reason: "Done", changedAt: now),
        ])

        let writer = TelemetryWriter()
        try await writer.writeManifest(manifest, to: tmpDir.path)
        let loaded = try await writer.loadManifest(from: tmpDir.path)

        #expect(loaded.lifecycle(for: "project-a") == .active)
        #expect(loaded.lifecycle(for: "project-b") == .sunset)
        #expect(loaded.projects["project-b"]?.reason == "Done")
    }

    @Test("loadManifest returns empty manifest when file does not exist")
    func loadManifestMissing() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ijs-manifest-missing-\(UUID().uuidString)")
        // SAFETY: Path is within system temp; cleaned up after test
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let writer = TelemetryWriter()
        let loaded = try await writer.loadManifest(from: tmpDir.path)

        #expect(loaded.projects.isEmpty)
        #expect(loaded.lifecycle(for: "anything") == .active)
    }

    @Test("Manifest file is written as YAML")
    func manifestIsYAML() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ijs-manifest-yaml-\(UUID().uuidString)")
        // SAFETY: Path is within system temp; cleaned up after test
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let now = Date(timeIntervalSince1970: 1_747_500_000)
        let manifest = CorpusManifest(projects: [
            "my-project": ProjectEntry(lifecycle: .sunset, reason: "Test", changedAt: now),
        ])

        let writer = TelemetryWriter()
        try await writer.writeManifest(manifest, to: tmpDir.path)

        let fileURL = URL(fileURLWithPath: tmpDir.path).appendingPathComponent("manifest.yml")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.contains("my-project"))
        #expect(contents.contains("sunset"))
    }

    @Test("Manifest write respects path sanitization")
    func manifestPathSanitization() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ijs-manifest-safe-\(UUID().uuidString)")
        // SAFETY: Path is within system temp; cleaned up after test
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let writer = TelemetryWriter()
        let manifest = CorpusManifest(projects: [:])

        // Writing to a valid path should succeed
        try await writer.writeManifest(manifest, to: tmpDir.path)

        let corpus = CorpusPath(basePath: tmpDir.path, projectID: "test")
        #expect(corpus.manifestPath.hasPrefix(tmpDir.path))
    }
}
