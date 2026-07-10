import Testing
import Foundation
@testable import CorpusKit

@Suite("InstitutionalPulse sunset field")
struct InstitutionalPulseSunsetTests {

    private static let emptyStats = PulseStatistics(
        totalGateRuns: 0,
        passedRuns: 0,
        failedRuns: 0,
        totalOverrides: 0,
        totalCalibrations: 0,
        overridesByRiskTier: [:],
        failuresByChecker: [:],
        rootCauseDistribution: [:],
        failedStepDistribution: [:],
        meanConsistencyScore: nil,
        corpusTrends: [],
        projectTrends: [:],
        anomalies: [],
        corpusSnapshots: [],
        projectSnapshots: [:]
    )

    @Test("Pulse with sunsetProjects encodes and decodes")
    func sunsetProjectsRoundTrip() throws {
        let pulse = InstitutionalPulse(
            windowStart: Date(timeIntervalSince1970: 1_747_000_000),
            windowEnd: Date(timeIntervalSince1970: 1_747_600_000),
            weekLabel: "2026-W20",
            projects: ["active-a", "active-b"],
            statistics: Self.emptyStats,
            violationClusters: [],
            proposedPolicyUpdates: [],
            calibrationSummaries: [],
            narrative: nil,
            generatedAt: Date(timeIntervalSince1970: 1_747_600_000),
            sunsetProjects: ["sunset-x", "sunset-y"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(pulse)
        let decoded = try decoder.decode(InstitutionalPulse.self, from: data)

        #expect(decoded.sunsetProjects == ["sunset-x", "sunset-y"])
        #expect(decoded.projects == ["active-a", "active-b"])
        #expect(decoded == pulse)
    }

    @Test("Decoding existing pulse JSON without sunsetProjects key succeeds with empty array")
    func backwardCompatibility() throws {
        let json = """
        {
            "windowStart": "2026-05-11T00:00:00Z",
            "windowEnd": "2026-05-17T23:59:59Z",
            "weekLabel": "2026-W20",
            "projects": ["project-a"],
            "statistics": {
                "totalGateRuns": 10,
                "passedRuns": 8,
                "failedRuns": 2,
                "totalOverrides": 0,
                "totalCalibrations": 0,
                "overridesByRiskTier": [],
                "failuresByChecker": {},
                "rootCauseDistribution": {},
                "failedStepDistribution": [],
                "corpusTrends": [],
                "projectTrends": {},
                "anomalies": [],
                "corpusSnapshots": [],
                "projectSnapshots": {}
            },
            "violationClusters": [],
            "proposedPolicyUpdates": [],
            "calibrationSummaries": [],
            "generatedAt": "2026-05-18T00:00:00Z"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pulse = try decoder.decode(InstitutionalPulse.self, from: data)

        #expect(pulse.sunsetProjects.isEmpty)
        #expect(pulse.projects == ["project-a"])
    }

    @Test("Empty sunsetProjects serializes as empty array")
    func emptySunsetProjectsSerialization() throws {
        let pulse = InstitutionalPulse(
            windowStart: Date(timeIntervalSince1970: 1_747_000_000),
            windowEnd: Date(timeIntervalSince1970: 1_747_600_000),
            weekLabel: "2026-W20",
            projects: ["a"],
            statistics: Self.emptyStats,
            violationClusters: [],
            proposedPolicyUpdates: [],
            calibrationSummaries: [],
            narrative: nil,
            generatedAt: Date(timeIntervalSince1970: 1_747_600_000),
            sunsetProjects: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pulse)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        #expect(jsonString.contains("sunsetProjects"))
    }
}
