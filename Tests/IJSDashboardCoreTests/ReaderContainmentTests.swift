import Foundation
import Testing
import CorpusKit
@testable import IJSDashboardCore

/// A reader must not be talked out of its corpus.
///
/// `CorpusReader` built `"\(corpusPath)/telemetry/\(project)"` and resolved it. Its comment said
/// *"project from discoverProjects"*, which was true while the only caller listed the directory
/// itself — and false once `ijs-mcp-server` passed `project_id` from an MCP tool call. A crafted
/// value read a **different corpus** and returned a valid-looking consistency score.
///
/// The containment helpers existed the whole time. Their doc said they were for *writers*, which
/// was accurate when only writers took computed input.
@Suite("CorpusReader containment")
struct ReaderContainmentTests {

    private func corpus() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reader-containment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("telemetry/RealProject"), withIntermediateDirectories: true)
        return dir
    }

    @Test("A traversing project id is refused, not resolved")
    func traversalRefused() throws {
        let dir = try corpus()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = CorpusReader(corpusPath: dir.path)

        #expect(throws: (any Error).self) {
            _ = try reader.loadRuns(for: "../../elsewhere")
        }
    }

    @Test("So is a bare parent reference, and an absolute path")
    func otherEscapes() throws {
        let dir = try corpus()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = CorpusReader(corpusPath: dir.path)

        for bad in ["..", "/etc", "a/b", "."] {
            #expect(throws: (any Error).self) {
                _ = try reader.loadRuns(for: bad)
            }
        }
    }

    @Test("A real project id still reads")
    func legitimateStillWorks() throws {
        let dir = try corpus()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = CorpusReader(corpusPath: dir.path)
        // No runs in it, but it resolves and returns empty rather than throwing.
        #expect(try reader.loadRuns(for: "RealProject").isEmpty)
    }

    @Test("An orientation lookup is guarded the same way")
    func orientationGuarded() throws {
        let dir = try corpus()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = CorpusReader(corpusPath: dir.path)

        #expect(throws: (any Error).self) {
            _ = try reader.loadLatestOrientationReport(for: "../../elsewhere")
        }
    }

    @Test("A pulse label that is not a single component finds nothing")
    func pulseLabelGuarded() throws {
        let dir = try corpus()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = CorpusReader(corpusPath: dir.path)
        #expect(reader.loadPulse(label: "../../elsewhere") == nil)
        #expect(reader.loadPulse(label: "..") == nil)
    }
}

/// The identifier check itself, at the level it is defined.
@Suite("CorpusPath.isSingleComponent")
struct SingleComponentTests {

    @Test("Accepts a plain identifier")
    func accepts() {
        for good in ["BusinessMath", "quality-gate-swift", "2026-W34", "a_b.c"] {
            #expect(CorpusPath.isSingleComponent(good), "\(good) should be accepted")
        }
    }

    @Test("Refuses separators, relative components and empties")
    func refuses() {
        for bad in ["", ".", "..", "a/b", "/abs", "../x", "a\\b"] {
            #expect(!CorpusPath.isSingleComponent(bad), "\(bad) should be refused")
        }
    }

    @Test("The throwing form names what it rejected")
    func throwingFormNamesIt() {
        #expect(throws: (any Error).self) {
            try CorpusPath.requireSingleComponent("../x", label: "project id")
        }
        #expect(throws: Never.self) {
            try CorpusPath.requireSingleComponent("BusinessMath", label: "project id")
        }
    }
}
