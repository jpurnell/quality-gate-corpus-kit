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

@Suite("Corpus schema versioning — remaining artifacts (0.5)")
struct RemainingArtifactVersioningTests {

    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private let stamp = Date(timeIntervalSince1970: 1_777_000_000)

    /// Encodes the artifact and returns whether it stamped the current schema version.
    private func stampsCurrentVersion<T: VersionedCorpusArtifact>(_ artifact: T) throws -> Bool {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let json = String(decoding: try enc.encode(artifact), as: UTF8.self)
        return json.contains("\"schemaVersion\":\(T.currentSchemaVersion)")
    }

    /// Returns whether the uniform skip-newer policy applies to the artifact type
    /// (a schema-99 artifact is skipped, reporting version 99 and the supported version).
    private func skipsNewerArtifact<T: VersionedCorpusArtifact>(_ type: T.Type) throws -> Bool {
        let future = Data("{\"schemaVersion\":99}".utf8)
        let outcome = try CorpusSchema.decode(type, from: future, decoder: decoder, origin: "future.json")
        guard case .skippedNewer(let v, let supported) = outcome else { return false }
        return v == 99 && supported == T.currentSchemaVersion
    }

    @Test("all six remaining artifact types stamp the current schema version when written")
    func stampsCurrent() throws {
        #expect(try stampsCurrentVersion(CheckResultMetadata(
            projectID: "p", timestamp: stamp, environment: .local, decisionOwner: "o",
            results: [], overrides: [], riskTier: .informational, ethicalFlags: [],
            consistencyScore: nil)))
        #expect(try stampsCurrentVersion(ComplexityReport(
            projectID: "p", timestamp: stamp, modules: [],
            summary: ComplexitySummary(totalFunctions: 0, medianCognitive: 0, p90Cognitive: 0,
                                       maxCognitive: 0, complexityDistribution: [:], totalPatterns: 0,
                                       patternBreakdown: [:], functionsAboveThreshold: 0))))
        #expect(try stampsCurrentVersion(DailySnapshot(
            date: stamp, scope: "corpus", gateRuns: 1, passedRuns: 1, failedRuns: 0,
            overrides: 0, calibrations: 0, failuresByChecker: [:], overridesByRiskTier: [:])))
        #expect(try stampsCurrentVersion(InstitutionalPulse(
            windowStart: stamp, windowEnd: stamp, weekLabel: "2026-W28", projects: [],
            statistics: PulseStatistics(totalGateRuns: 0, passedRuns: 0, failedRuns: 0,
                                        totalOverrides: 0, totalCalibrations: 0,
                                        overridesByRiskTier: [:], failuresByChecker: [:],
                                        rootCauseDistribution: [:], failedStepDistribution: [:],
                                        meanConsistencyScore: nil, corpusTrends: [],
                                        projectTrends: [:], anomalies: [], corpusSnapshots: [],
                                        projectSnapshots: [:]),
            violationClusters: [], proposedPolicyUpdates: [], calibrationSummaries: [],
            narrative: nil, generatedAt: stamp)))
        #expect(try stampsCurrentVersion(JudgmentCalibration(
            date: stamp, decisionOwner: "o", practitioner: "dev", riskTier: .operational,
            rootCauseAnalysis: RootCauseAnalysis(proximateCause: "c", chainOfInquiry: [],
                                                 rootCause: "expedient", failedStep: .design,
                                                 isRecurringPattern: false),
            redTeamDissent: "d", proposedPolicyUpdate: nil, pulseContribution: "s")))
        #expect(try stampsCurrentVersion(SkipRecord(
            projectID: "p", timestamp: stamp, issueReference: "QG-1", author: "a",
            environment: .ci)))
    }

    @Test("all six remaining artifact types skip newer-versioned artifacts")
    func skipsNewer() throws {
        #expect(try skipsNewerArtifact(CheckResultMetadata.self))
        #expect(try skipsNewerArtifact(ComplexityReport.self))
        #expect(try skipsNewerArtifact(DailySnapshot.self))
        #expect(try skipsNewerArtifact(InstitutionalPulse.self))
        #expect(try skipsNewerArtifact(JudgmentCalibration.self))
        #expect(try skipsNewerArtifact(SkipRecord.self))
    }

    @Test("legacy check-result metadata (pre-complianceCount, pre-commitSHA) decodes as v1")
    func legacyCheckResultMetadata() throws {
        let legacy = Data("""
        {"projectID":"p","timestamp":"2026-05-01T00:00:00Z","environment":"local",
         "decisionOwner":"o","results":[],"overrides":[],"riskTier":1,"ethicalFlags":[]}
        """.utf8)
        let outcome = try CorpusSchema.decode(CheckResultMetadata.self, from: legacy, decoder: decoder, origin: "legacy-metadata.json")
        guard case .decoded(let m) = outcome else { Issue.record("legacy metadata skipped"); return }
        #expect(m.schemaVersion == 1)
        #expect(m.complianceCount == 0)
        #expect(m.commitSHA == nil)
    }

    @Test("legacy complexity report decodes as v1")
    func legacyComplexityReport() throws {
        let legacy = Data("""
        {"projectID":"p","timestamp":"2026-05-01T00:00:00Z","modules":[],
         "summary":{"totalFunctions":10,"medianCognitive":2,"p90Cognitive":5,"maxCognitive":9,
                    "complexityDistribution":{},"totalPatterns":0,"patternBreakdown":{},
                    "functionsAboveThreshold":0}}
        """.utf8)
        let outcome = try CorpusSchema.decode(ComplexityReport.self, from: legacy, decoder: decoder, origin: "legacy-complexity.json")
        guard case .decoded(let r) = outcome else { Issue.record("legacy complexity report skipped"); return }
        #expect(r.schemaVersion == 1)
        #expect(r.summary.totalFunctions == 10)
    }

    @Test("legacy daily snapshot decodes as v1")
    func legacyDailySnapshot() throws {
        let legacy = Data("""
        {"date":"2026-05-01T00:00:00Z","scope":"corpus","gateRuns":4,"passedRuns":3,
         "failedRuns":1,"overrides":0,"calibrations":0,"failuresByChecker":{"safety":1},
         "overridesByRiskTier":[]}
        """.utf8)
        let outcome = try CorpusSchema.decode(DailySnapshot.self, from: legacy, decoder: decoder, origin: "legacy-snapshot.json")
        guard case .decoded(let s) = outcome else { Issue.record("legacy snapshot skipped"); return }
        #expect(s.schemaVersion == 1)
        #expect(s.gateRuns == 4)
        #expect(abs(s.passRate - 0.75) < 1e-6)
    }

    @Test("legacy institutional pulse (pre-tiers, pre-trajectories) decodes as v1")
    func legacyInstitutionalPulse() throws {
        let legacy = Data("""
        {"windowStart":"2026-05-01T00:00:00Z","windowEnd":"2026-05-08T00:00:00Z",
         "weekLabel":"2026-W19","projects":["p"],
         "statistics":{"totalGateRuns":1,"passedRuns":1,"failedRuns":0,"totalOverrides":0,
                       "totalCalibrations":0,"overridesByRiskTier":[],"failuresByChecker":{},
                       "rootCauseDistribution":{},"failedStepDistribution":[],
                       "corpusTrends":[],"projectTrends":{},"anomalies":[],
                       "corpusSnapshots":[],"projectSnapshots":{}},
         "violationClusters":[],"proposedPolicyUpdates":[],"calibrationSummaries":[],
         "generatedAt":"2026-05-08T00:00:00Z"}
        """.utf8)
        let outcome = try CorpusSchema.decode(InstitutionalPulse.self, from: legacy, decoder: decoder, origin: "legacy-pulse.json")
        guard case .decoded(let p) = outcome else { Issue.record("legacy pulse skipped"); return }
        #expect(p.schemaVersion == 1)
        #expect(p.projectTiers == nil)
        #expect(p.narrative == nil)
    }

    @Test("legacy judgment calibration decodes as v1")
    func legacyJudgmentCalibration() throws {
        let legacy = Data("""
        {"date":"2026-05-01T00:00:00Z","decisionOwner":"o","practitioner":"dev","riskTier":2,
         "rootCauseAnalysis":{"proximateCause":"c","chainOfInquiry":["why"],
                              "rootCause":"expedient","failedStep":"design",
                              "isRecurringPattern":false},
         "redTeamDissent":"d","pulseContribution":"s"}
        """.utf8)
        let outcome = try CorpusSchema.decode(JudgmentCalibration.self, from: legacy, decoder: decoder, origin: "legacy-calibration.json")
        guard case .decoded(let c) = outcome else { Issue.record("legacy calibration skipped"); return }
        #expect(c.schemaVersion == 1)
        #expect(c.proposedPolicyUpdate == nil)
        #expect(c.riskTier == .operational)
    }

    @Test("legacy skip record decodes as v1")
    func legacySkipRecord() throws {
        let legacy = Data("""
        {"projectID":"p","timestamp":"2026-05-01T00:00:00Z","issueReference":"QG-9",
         "author":"a","environment":"ci"}
        """.utf8)
        let outcome = try CorpusSchema.decode(SkipRecord.self, from: legacy, decoder: decoder, origin: "legacy-skip.json")
        guard case .decoded(let s) = outcome else { Issue.record("legacy skip record skipped"); return }
        #expect(s.schemaVersion == 1)
        #expect(s.issueReference == "QG-9")
    }

    @Test("stamped round-trip is lossless for a representative artifact")
    func roundTripMetadata() throws {
        let metadata = CheckResultMetadata(
            projectID: "p", timestamp: stamp, environment: .ci, decisionOwner: "o",
            results: [], overrides: [], riskTier: .safety, ethicalFlags: [],
            consistencyScore: 0.9, complianceCount: 3, commitSHA: "abc123")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let outcome = try CorpusSchema.decode(CheckResultMetadata.self, from: try enc.encode(metadata), decoder: decoder)
        guard case .decoded(let back) = outcome else { Issue.record("round-trip skipped"); return }
        #expect(back == metadata)
    }
}
