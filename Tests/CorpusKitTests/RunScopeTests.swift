import Foundation
import Testing
@testable import CorpusKit

@Suite("Run scope on check-result metadata (0.1, schema v2)")
struct RunScopeTests {

    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private let stamp = Date(timeIntervalSince1970: 1_777_000_000)

    private func makeMetadata(runScope: RunScope) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "p", timestamp: stamp, environment: .local, decisionOwner: "o",
            results: [], overrides: [], riskTier: .informational, ethicalFlags: [],
            consistencyScore: nil, runScope: runScope)
    }

    @Test("metadata now writes schema v2 and defaults to a full-run scope")
    func writesV2FullByDefault() throws {
        let metadata = CheckResultMetadata(
            projectID: "p", timestamp: stamp, environment: .local, decisionOwner: "o",
            results: [], overrides: [], riskTier: .informational, ethicalFlags: [],
            consistencyScore: nil)
        #expect(CheckResultMetadata.currentSchemaVersion == 2)
        #expect(metadata.schemaVersion == 2)
        #expect(metadata.runScope == .full)
    }

    @Test("subset scope round-trips with its checker list")
    func subsetRoundTrip() throws {
        let metadata = makeMetadata(runScope: .subset(checkers: ["legibility", "safety"]))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let outcome = try CorpusSchema.decode(CheckResultMetadata.self, from: try enc.encode(metadata), decoder: decoder)
        guard case .decoded(let back) = outcome else { Issue.record("round-trip skipped"); return }
        #expect(back.runScope == .subset(checkers: ["legibility", "safety"]))
        #expect(back == metadata)
    }

    @Test("v1 metadata (no runScope) decodes as a full run — history was written by full gates")
    func legacyDecodesAsFull() throws {
        let legacy = Data("""
        {"projectID":"p","timestamp":"2026-05-01T00:00:00Z","environment":"local",
         "decisionOwner":"o","results":[],"overrides":[],"riskTier":1,"ethicalFlags":[]}
        """.utf8)
        let outcome = try CorpusSchema.decode(CheckResultMetadata.self, from: legacy, decoder: decoder, origin: "legacy-metadata.json")
        guard case .decoded(let m) = outcome else { Issue.record("legacy metadata skipped"); return }
        #expect(m.schemaVersion == 1)
        #expect(m.runScope == .full)
    }

    @Test("a v3 artifact is skipped, not half-decoded")
    func skipsNewerThanV2() throws {
        let future = Data("{\"schemaVersion\":3}".utf8)
        let outcome = try CorpusSchema.decode(CheckResultMetadata.self, from: future, decoder: decoder, origin: "future.json")
        guard case .skippedNewer(let v, let supported) = outcome else {
            Issue.record("future artifact was decoded"); return
        }
        #expect(v == 3)
        #expect(supported == 2)
    }
}
