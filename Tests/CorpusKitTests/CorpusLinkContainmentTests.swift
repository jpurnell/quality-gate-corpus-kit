import Foundation
import Testing
@testable import CorpusKit

/// A link in the corpus that leads to a sibling directory is outside the corpus.
///
/// `TelemetryWriter`'s directory filters resolve each entry's links and keep it if
/// `resolved.path.hasPrefix(base.path)`. A link to `…/corpus-other` begins with `…/corpus`, so
/// a project directory outside the corpus was discovered and read as one of its own.
@Suite("Corpus link containment")
struct CorpusLinkContainmentTests {

    @Test("A project linked from a sibling directory is not discovered")
    func siblingLinkIsNotAProject() async throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("corpus-link-\(UUID().uuidString)")
        let corpus = parent.appendingPathComponent("corpus")
        let telemetry = corpus.appendingPathComponent("telemetry")
        let sibling = parent.appendingPathComponent("corpus-other").appendingPathComponent("smuggled")
        try fm.createDirectory(at: telemetry.appendingPathComponent("real"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) } // silent: test cleanup; a leftover temp directory changes no result
        try fm.createSymbolicLink(at: telemetry.appendingPathComponent("smuggled"), withDestinationURL: sibling)

        let projects = try await TelemetryWriter().discoverProjects(in: corpus.path)
        #expect(projects.map(\.projectID) == ["real"])
    }
}
