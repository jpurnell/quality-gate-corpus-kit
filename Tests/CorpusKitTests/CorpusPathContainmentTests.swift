import Testing
import Foundation
@testable import CorpusKit

/// The one hardened corpus-base containment check, shared by every writer.
///
/// Containment is lexical and component-wise (no `hasPrefix` on symlink-resolved
/// strings), and the returned URL re-anchors the validated suffix onto the base
/// resolved once via `resolvingSymlinksInPath` — so it is correct under a
/// symlinked base and rejects prefix-sibling and `..` escapes.
@Suite("CorpusPath containment")
struct CorpusPathContainmentTests {

    // MARK: - contains (pure predicate)

    @Test("contains accepts a path inside the base")
    func containsInside() {
        let corpus = CorpusPath(basePath: "/corpus", projectID: "p")
        #expect(corpus.contains("/corpus/telemetry/p/2026-07-29/120000_metadata.json"))
        #expect(CorpusPath.contains("/a/b/c/d", within: "/a/b"))
    }

    @Test("contains rejects a prefix-sibling that only shares a string prefix")
    func containsRejectsPrefixSibling() {
        // /a/corpus-evil is NOT inside /a/corpus, even though hasPrefix would say so.
        #expect(!CorpusPath.contains("/a/corpus-evil/x", within: "/a/corpus"))
    }

    @Test("contains rejects `..` traversal out of the base")
    func containsRejectsDotDot() {
        #expect(!CorpusPath.contains("/a/corpus/../secrets", within: "/a/corpus"))
        #expect(!CorpusPath.contains("/a/corpus/x/../../etc", within: "/a/corpus"))
    }

    @Test("the base itself is contained")
    func containsBaseItself() {
        #expect(CorpusPath.contains("/a/corpus", within: "/a/corpus"))
    }

    // MARK: - resolvedURL (validate + re-anchor)

    @Test("resolvedURL returns an anchored URL for a contained path")
    func resolvedURLForContained() throws {
        // Base "/corpus" does not exist, so resolvingSymlinksInPath leaves it as-is
        // and the validated suffix is appended verbatim.
        let corpus = CorpusPath(basePath: "/corpus", projectID: "p")
        let url = try corpus.resolvedURL(forContainedPath: "/corpus/decisions/p/2026-07-29/x.json")
        #expect(url.path == "/corpus/decisions/p/2026-07-29/x.json")
    }

    @Test("resolvedURL throws when the path escapes the base")
    func resolvedURLThrowsOnEscape() {
        #expect(throws: IJSError.self) {
            _ = try CorpusPath.resolvedURL(for: "/a/corpus-evil/x", within: "/a/corpus")
        }
        #expect(throws: IJSError.self) {
            _ = try CorpusPath.resolvedURL(for: "/a/corpus/../etc", within: "/a/corpus")
        }
    }

    @Test("resolvedURL re-anchors onto the base resolved through a symlink")
    func resolvedURLUnderSymlinkedBase() throws {
        // /tmp is a symlink to /private/tmp on Darwin: the existing base and the
        // not-yet-created target must not be canonicalized asymmetrically.
        let root = "/tmp/corpuskit-contain-\(UUID().uuidString)"
        let basePath = root + "/corpus"
        // SAFETY: Creates a directory under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input, so the path cannot escape the temp root [CWE-22].
        try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
        // SAFETY: Removes only the temp tree this test created under the test's own temp directory (FileManager.temporaryDirectory + a UUID), never external input [CWE-22].
        defer { try? FileManager.default.removeItem(atPath: root) }

        let target = basePath + "/telemetry/p/2026-07-29/120000_metadata.json"
        let url = try CorpusPath.resolvedURL(for: target, within: basePath)

        // The returned URL resolves to a real location inside the real base.
        let baseReal = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().path
        #expect(url.path.hasPrefix(baseReal))
        #expect(url.lastPathComponent == "120000_metadata.json")
    }
}
