import Testing
import Foundation
@testable import CorpusKit

@Suite("CorpusPath Stack Map Paths")
struct CorpusPathStackMapTests {

    private let corpusPath = CorpusPath(basePath: "/corpus", projectID: "my-app")

    @Test("stackMapDirectory is the stack-map folder at the corpus root")
    func directory() {
        #expect(corpusPath.stackMapDirectory == "/corpus/stack-map")
    }

    @Test("stackMapPath is the current map, which the dashboard reads")
    func current() {
        #expect(corpusPath.stackMapPath == "/corpus/stack-map/stack-map.json")
    }

    @Test("stackMapHistoryPath is one file per UTC day, for trend history")
    func history() {
        // 2026-10-22T12:00:00Z
        let noon = Date(timeIntervalSince1970: 1_792_670_400)
        #expect(corpusPath.stackMapHistoryPath(date: noon) == "/corpus/stack-map/history/2026-10-22.json")
    }

    @Test("The day is taken in UTC: 2026-10-22T23:30Z is still the 22nd")
    func historyUsesUTC() {
        let lateUTC = Date(timeIntervalSince1970: 1_792_670_400 + 11 * 3600 + 1800)
        #expect(corpusPath.stackMapHistoryPath(date: lateUTC) == "/corpus/stack-map/history/2026-10-22.json")
    }

    @Test("The map's location does not depend on the project ID")
    func independentOfProject() {
        #expect(CorpusPath(basePath: "/corpus", projectID: "other").stackMapPath == corpusPath.stackMapPath)
    }

    @Test("The stack-map folder does not collide with another corpus root")
    func noCollision() {
        let roots = [corpusPath.stackMapDirectory, corpusPath.pulseRoot, "/corpus/telemetry", "/corpus/snapshots"]
        #expect(Set(roots).count == roots.count)
    }
}
