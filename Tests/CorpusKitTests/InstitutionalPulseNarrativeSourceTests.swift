import Testing
import Foundation
@testable import CorpusKit

@Suite("InstitutionalPulse narrativeSource provenance")
struct InstitutionalPulseNarrativeSourceTests {

    private let stamp = Date(timeIntervalSince1970: 1_777_000_000)

    private func makeStats() -> PulseStatistics {
        PulseStatistics(
            totalGateRuns: 0, passedRuns: 0, failedRuns: 0,
            totalOverrides: 0, totalCalibrations: 0,
            overridesByRiskTier: [:], failuresByChecker: [:],
            rootCauseDistribution: [:], failedStepDistribution: [:],
            meanConsistencyScore: nil, corpusTrends: [], projectTrends: [:],
            anomalies: [], corpusSnapshots: [], projectSnapshots: [:]
        )
    }

    private func makePulse(narrativeSource: ProseSource? = nil) -> InstitutionalPulse {
        InstitutionalPulse(
            windowStart: stamp, windowEnd: stamp, weekLabel: "2026-W28", projects: [],
            statistics: makeStats(), violationClusters: [], proposedPolicyUpdates: [],
            calibrationSummaries: [], narrative: "n", generatedAt: stamp,
            narrativeSource: narrativeSource
        )
    }

    @Test("narrativeSource round-trips through JSON")
    func roundTrips() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let pulse = makePulse(narrativeSource: .onDeviceLLM)
        let back = try dec.decode(InstitutionalPulse.self, from: try enc.encode(pulse))
        #expect(back.narrativeSource == .onDeviceLLM)
        #expect(back == pulse)
    }

    @Test("a pulse without narrativeSource omits the key and decodes as nil (optional, no schema bump)")
    func legacyDecodesAsNil() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        // A no-source pulse encodes without the key — byte-identical to a
        // pre-provenance pulse — and must decode back to nil.
        let data = try enc.encode(makePulse(narrativeSource: nil))
        #expect(!String(decoding: data, as: UTF8.self).contains("narrativeSource"))
        let pulse = try dec.decode(InstitutionalPulse.self, from: data)
        #expect(pulse.narrativeSource == nil)
        #expect(pulse.schemaVersion == 1)
    }

    @Test("withNarrative records the producing engine")
    func withNarrativeSetsSource() {
        let base = makePulse(narrativeSource: nil)
        let updated = base.withNarrative("Generated on-device.", source: .onDeviceLLM)
        #expect(updated.narrative == "Generated on-device.")
        #expect(updated.narrativeSource == .onDeviceLLM)
    }

    @Test("withNarrative without a source keeps provenance nil (source-compatible)")
    func withNarrativeNoSource() {
        let updated = makePulse().withNarrative("Just text.")
        #expect(updated.narrative == "Just text.")
        #expect(updated.narrativeSource == nil)
    }
}
