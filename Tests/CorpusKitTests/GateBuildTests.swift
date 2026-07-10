import Foundation
import Testing
@testable import CorpusKit

@Suite("Gate build identity on metadata (0.6)")
struct GateBuildTests {

    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private let stamp = Date(timeIntervalSince1970: 1_777_000_000)

    @Test("metadata round-trips the gate build identity")
    func gateBuildRoundTrip() throws {
        let metadata = CheckResultMetadata(
            projectID: "p", timestamp: stamp, environment: .local, decisionOwner: "o",
            results: [], overrides: [], riskTier: .informational, ethicalFlags: [],
            consistencyScore: nil,
            gateBuild: GateBuild(commit: "abc1234", buildDate: "2026-07-09T18:00:08Z"))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let outcome = try CorpusSchema.decode(CheckResultMetadata.self, from: try enc.encode(metadata), decoder: decoder)
        guard case .decoded(let back) = outcome else { Issue.record("round-trip skipped"); return }
        #expect(back.gateBuild == GateBuild(commit: "abc1234", buildDate: "2026-07-09T18:00:08Z"))
    }

    @Test("adding gateBuild is not a schema bump — v2 artifacts without it decode with nil")
    func absentGateBuildIsNil() throws {
        let v2WithoutBuild = Data("""
        {"schemaVersion":2,"projectID":"p","timestamp":"2026-07-09T00:00:00Z","environment":"local",
         "decisionOwner":"o","results":[],"overrides":[],"riskTier":1,"ethicalFlags":[],
         "runScope":{"type":"full"}}
        """.utf8)
        let outcome = try CorpusSchema.decode(CheckResultMetadata.self, from: v2WithoutBuild, decoder: decoder, origin: "v2-no-build.json")
        guard case .decoded(let m) = outcome else { Issue.record("v2 artifact skipped"); return }
        #expect(CheckResultMetadata.currentSchemaVersion == 2)
        #expect(m.gateBuild == nil)
    }
}
