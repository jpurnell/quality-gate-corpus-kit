import Testing
import Foundation
@testable import CorpusKit

/// Phase 2 §4b — the second-writer tripwire.
///
/// The personal→professional transition is detected by the system, not
/// remembered by a human: when a second distinct *person* writes to a
/// project's corpus within the rolling window, every gate run and the
/// dashboard surface a standing warning that Phase 3 controls are now
/// required. Machines are counted and surfaced but never trip alone — the
/// owner running two Macs is write-coordination texture, not a transition.
@Suite("WriterCensus")
struct WriterCensusTests {

    private func makeMeta(
        owner: String,
        host: String?,
        ciActor: String? = nil,
        daysAgo: Double,
        now: Date
    ) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "fixture",
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            environment: ciActor == nil ? .local : .ci,
            decisionOwner: owner,
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil,
            ciIdentity: ciActor.map {
                CIIdentity(provider: "github-actions", actor: $0,
                           workflowRunID: "1", commit: "c", repository: "r")
            },
            host: host)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a single writer never trips")
    func singleWriterQuiet() {
        let census = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 5, now: now),
        ], now: now)
        #expect(census.tripped == false)
        #expect(census.persons == ["jpurnell"])
    }

    @Test("the same person on two machines does not trip, but both machines are counted")
    func twoMachinesOnePersonQuiet() {
        let census = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
            makeMeta(owner: "jpurnell", host: "builder-01.local", daysAgo: 2, now: now),
        ], now: now)
        #expect(census.tripped == false)
        #expect(census.persons == ["jpurnell"])
        #expect(census.machines.count == 2)
    }

    @Test("a second asserted person trips")
    func secondAssertedPersonTrips() {
        let census = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
            makeMeta(owner: "contributor", host: "their-mac.local", daysAgo: 3, now: now),
        ], now: now)
        #expect(census.tripped == true)
        #expect(census.persons == ["contributor", "jpurnell"])
    }

    @Test("a verified CI actor distinct from the local owner trips")
    func verifiedSecondActorTrips() {
        let census = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
            makeMeta(owner: "runner", host: nil, ciActor: "external-contributor", daysAgo: 2, now: now),
        ], now: now)
        #expect(census.tripped == true)
        #expect(census.persons.contains("external-contributor"))
    }

    @Test("a CI actor matching the local owner is the same person — no trip")
    func ciActorSamePersonQuiet() {
        let census = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
            makeMeta(owner: "runner", host: nil, ciActor: "jpurnell", daysAgo: 2, now: now),
        ], now: now)
        #expect(census.tripped == false)
        #expect(census.persons == ["jpurnell"])
    }

    @Test("writers outside the rolling window do not trip")
    func oldWritersExpire() {
        let census = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
            makeMeta(owner: "long-gone", host: "old.local", daysAgo: 45, now: now),
        ], now: now)
        #expect(census.tripped == false)
        #expect(census.persons == ["jpurnell"])
    }

    @Test("the standing warning names Phase 3 and only exists when tripped")
    func warningText() {
        let quiet = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
        ], now: now)
        #expect(quiet.standingWarning == nil)

        let tripped = WriterCensus.census(of: [
            makeMeta(owner: "jpurnell", host: "studio.local", daysAgo: 1, now: now),
            makeMeta(owner: "contributor", host: "b.local", daysAgo: 2, now: now),
        ], now: now)
        let warning = tripped.standingWarning ?? ""
        #expect(warning.contains("multi-writer activity detected"))
        #expect(warning.contains("Phase 3"))
        #expect(warning.contains("jpurnell"))
        #expect(warning.contains("contributor"))
    }

    @Test("an empty corpus is quiet")
    func emptyCorpusQuiet() {
        let census = WriterCensus.census(of: [], now: now)
        #expect(census.tripped == false)
        #expect(census.persons.isEmpty)
        #expect(census.machines.isEmpty)
    }
}
