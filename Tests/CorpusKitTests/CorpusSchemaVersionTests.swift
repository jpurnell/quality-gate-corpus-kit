import Foundation
import Testing
@testable import CorpusKit

@Suite("Corpus schema versioning (0.5)")
struct CorpusSchemaVersionTests {

    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    @Test("a freshly written report stamps the current schema version")
    func stampsCurrent() throws {
        let report = OrientationReport(projectID: "p", timestamp: Date(timeIntervalSince1970: 1_777_000_000), cards: [])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let json = String(decoding: try enc.encode(report), as: UTF8.self)
        #expect(json.contains("\"schemaVersion\":\(OrientationReport.currentSchemaVersion)"))
    }

    @Test("a pre-versioning, pre-E1 artifact decodes as v1 with defaults (the live corpus bug)")
    func decodesLegacyArtifact() throws {
        // Shape of a real 2026-07-08 pre-E1 file: no schemaVersion, no
        // packageDependsOn/packageSummary, cards without dependsOn.
        let legacy = Data("""
        {"projectID":"quality-gate-swift","timestamp":"2026-07-08T17:53:12Z",
         "cards":[{"moduleID":"AccessibilityAuditor","reliedOnBy":["QualityGateCLI"],
                   "role":"intermediate","source":"template","generatedAt":"2026-07-08T17:53:12Z"}]}
        """.utf8)
        let outcome = try CorpusSchema.decode(OrientationReport.self, from: legacy, decoder: decoder, origin: "legacy.json")
        guard case .decoded(let report) = outcome else { Issue.record("legacy artifact skipped"); return }
        #expect(report.schemaVersion == 1)
        #expect(report.packageDependsOn.isEmpty)
        #expect(report.cards.first?.dependsOn == [])
        #expect(report.cards.first?.reliedOnBy == ["QualityGateCLI"])
    }

    @Test("a newer-versioned artifact is skipped with its versions reported — never half-decoded")
    func skipsNewer() throws {
        let future = Data("""
        {"schemaVersion":99,"projectID":"p","timestamp":"2026-07-09T00:00:00Z","cards":[],
         "someFieldFromTheFuture":{"nested":true}}
        """.utf8)
        let outcome = try CorpusSchema.decode(OrientationReport.self, from: future, decoder: decoder, origin: "future.json")
        guard case .skippedNewer(let v, let supported) = outcome else { Issue.record("future artifact was decoded"); return }
        #expect(v == 99)
        #expect(supported == OrientationReport.currentSchemaVersion)
    }

    @Test("garbage is still an error — newer is not the same as malformed")
    func garbageStillThrows() {
        let garbage = Data("{\"projectID\": 42}".utf8)
        #expect(throws: (any Error).self) {
            _ = try CorpusSchema.decode(OrientationReport.self, from: garbage, decoder: decoder)
        }
    }

    @Test("versioned round-trip is lossless")
    func roundTrip() throws {
        let report = OrientationReport(
            projectID: "p", timestamp: Date(timeIntervalSince1970: 1_777_000_000),
            cards: [ModuleOrientationCard(moduleID: "M", whatItDoes: "x", why: nil, dependsOn: ["A"],
                                          reliedOnBy: ["B"], role: "foundation", source: .template,
                                          generatedAt: Date(timeIntervalSince1970: 1_777_000_000))],
            packageDependsOn: ["Dep"], packageSummary: "s")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let outcome = try CorpusSchema.decode(OrientationReport.self, from: try enc.encode(report), decoder: decoder)
        guard case .decoded(let back) = outcome else { Issue.record("round-trip skipped"); return }
        #expect(back == report)
    }
}
