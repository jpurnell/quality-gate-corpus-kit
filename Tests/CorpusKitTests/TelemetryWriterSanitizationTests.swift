import Testing
import Foundation
@testable import CorpusKit
import QualityGateTypes

/// Regression coverage for `TelemetryWriter`'s corpus-base containment guard.
///
/// The write path must accept targets inside a base reached through a symlink
/// (e.g. `/tmp` → `/private/tmp` on Darwin) and must reject prefix-sibling
/// escapes (`/a/corpus-evil` is not inside `/a/corpus`) as well as `..`
/// traversal.
@Suite("TelemetryWriter path sanitization")
struct TelemetryWriterSanitizationTests {

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func makeMetadata(projectID: String) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: projectID,
            timestamp: referenceDate,
            environment: .local,
            decisionOwner: "owner",
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil
        )
    }

    @Test("writes succeed when the corpus base is under a symlinked path")
    func writesUnderSymlinkedBase() async throws {
        // /tmp is a symlink to /private/tmp on Darwin — the live-CLI condition
        // where the existing base and the not-yet-created target subtree get
        // canonicalized asymmetrically.
        let root = "/tmp/corpuskit-symlink-\(UUID().uuidString)"
        let basePath = root + "/corpus"
        // SAFETY: Creates a directory under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input, so the path cannot escape the temp root [CWE-22].
        try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
        // SAFETY: Removes only the temp tree this test created under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input [CWE-22].
        defer { try? FileManager.default.removeItem(atPath: root) }

        let corpus = CorpusPath(basePath: basePath, projectID: "Pare")
        let writer = TelemetryWriter()

        try await writer.write(metadata: Self.makeMetadata(projectID: "Pare"), calibrations: [], to: corpus)

        let expected = corpus.metadataPath(for: Self.referenceDate)
        // SAFETY: Read-only existence probe; the path was built by this test under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input, so there is no traversal to sanitize [CWE-22].
        #expect(FileManager.default.fileExists(atPath: expected))
    }

    @Test("rejects a prefix-sibling directory escape")
    func rejectsPrefixSiblingEscape() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpuskit-sanitize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // Resolves to a sibling "<base>-evil" that shares the base's string
        // prefix but is not contained within it — the case a naive hasPrefix
        // check wrongly admits.
        let baseLast = base.lastPathComponent
        let corpus = CorpusPath(basePath: base.path, projectID: "../../\(baseLast)-evil/x")
        let writer = TelemetryWriter()

        await #expect(throws: IJSError.self) {
            try await writer.write(metadata: Self.makeMetadata(projectID: "x"), calibrations: [], to: corpus)
        }
    }

    @Test("rejects `..` traversal out of the corpus base")
    func rejectsDotDotTraversal() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpuskit-sanitize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let corpus = CorpusPath(basePath: base.path, projectID: "../../../etc")
        let writer = TelemetryWriter()

        await #expect(throws: IJSError.self) {
            try await writer.write(metadata: Self.makeMetadata(projectID: "etc"), calibrations: [], to: corpus)
        }
    }
}
