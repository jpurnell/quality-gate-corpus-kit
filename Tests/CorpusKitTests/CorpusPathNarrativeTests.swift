import Testing
import Foundation
@testable import CorpusKit

@Suite("CorpusPath Narrative Paths")
struct CorpusPathNarrativeTests {

    private let corpusPath = CorpusPath(basePath: "/corpus", projectID: "my-app")

    @Test("narrativePath produces correct path")
    func narrativePathCorrect() {
        let path = corpusPath.narrativePath(weekLabel: "2026-W20")
        #expect(path == "/corpus/pulse/2026-W20/NARRATIVE_2026-W20.md")
    }

    @Test("narrativePath is independent of projectID")
    func narrativePathIndependentOfProject() {
        let other = CorpusPath(basePath: "/corpus", projectID: "other-app")
        #expect(
            corpusPath.narrativePath(weekLabel: "2026-W20")
                == other.narrativePath(weekLabel: "2026-W20")
        )
    }

    @Test("narrativePath with different week labels")
    func narrativePathDifferentWeeks() {
        let w01 = corpusPath.narrativePath(weekLabel: "2025-W01")
        let w52 = corpusPath.narrativePath(weekLabel: "2025-W52")
        #expect(w01 == "/corpus/pulse/2025-W01/NARRATIVE_2025-W01.md")
        #expect(w52 == "/corpus/pulse/2025-W52/NARRATIVE_2025-W52.md")
        #expect(w01 != w52)
    }
}
