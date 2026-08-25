import Testing
import Foundation
@testable import CorpusKit

@Suite("ProjectHealthSummary")
struct ProjectHealthSummaryTests {

    @Test("Golden path: mixed pass rates yield correct mean")
    func goldenPath() {
        let summary = ProjectHealthSummary(
            projectPassRates: [
                "proj-a": 90.0,
                "proj-b": 70.0,
                "proj-c": 100.0,
                "proj-d": 50.0,
                "proj-e": 40.0,
            ]
        )
        #expect(summary.totalProjects == 5)
        #expect(abs(summary.meanHealthRate - 70.0) < 0.001)
    }

    @Test("Zero projects yields 0% mean")
    func zeroProjects() {
        let summary = ProjectHealthSummary(projectPassRates: [:])
        #expect(abs(summary.meanHealthRate - 0.0) < 1e-6)
        #expect(summary.totalProjects == 0)
    }

    @Test("All projects at 100% yields 100% mean")
    func allPerfect() {
        let summary = ProjectHealthSummary(
            projectPassRates: [
                "a": 100.0, "b": 100.0, "c": 100.0, "d": 100.0,
            ]
        )
        #expect(abs(summary.meanHealthRate - 100.0) < 0.001)
    }

    @Test("Single project pass rate is the mean")
    func singleProject() {
        let summary = ProjectHealthSummary(projectPassRates: ["solo": 85.0])
        #expect(abs(summary.meanHealthRate - 85.0) < 0.001)
        #expect(summary.totalProjects == 1)
    }

    @Test("Trajectories included in summary")
    func withTrajectories() {
        let traj = RunRateTrajectory(
            firstRunRate: 60.0, latestRunRate: 100.0, runCount: 4,
            delta: 40.0, runRates: [60.0, 70.0, 90.0, 100.0]
        )
        let summary = ProjectHealthSummary(
            projectPassRates: ["proj-a": 100.0],
            trajectories: ["proj-a": traj]
        )
        #expect(abs((summary.trajectories["proj-a"]?.delta ?? Double.nan) - 40.0) < 1e-6)
        #expect(summary.trajectories["proj-a"]?.runCount == 4)
    }

    @Test("Codable round-trip preserves all fields including trajectories")
    func codableRoundTrip() throws {
        let traj = RunRateTrajectory(
            firstRunRate: 50.0, latestRunRate: 90.0, runCount: 3,
            delta: 40.0, runRates: [50.0, 70.0, 90.0]
        )
        let summary = ProjectHealthSummary(
            projectPassRates: ["alpha": 90.0, "beta": 60.0, "gamma": 100.0],
            trajectories: ["alpha": traj]
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(summary)
        let decoded = try decoder.decode(ProjectHealthSummary.self, from: data)
        #expect(decoded == summary)
    }

    @Test("Backward-compat decode: old projectStatuses format converts to rates")
    func backwardCompatDecode() throws {
        let json = Data("""
        {"projectStatuses": {"a": true, "b": false, "c": true}}
        """.utf8)
        let decoded = try JSONDecoder().decode(ProjectHealthSummary.self, from: json)
        let rateForA = try #require(decoded.projectPassRates["a"])
        let rateForB = try #require(decoded.projectPassRates["b"])
        #expect(abs(rateForA - 100.0) < 0.001)
        #expect(abs(rateForB - 0.0) < 0.001)
        #expect(decoded.trajectories.isEmpty)
    }

    @Test("RunRateTrajectory round-trips through Codable")
    func trajectoryRoundTrip() throws {
        let traj = RunRateTrajectory(
            firstRunRate: 40.0, latestRunRate: 85.0, runCount: 5,
            delta: 45.0, runRates: [40.0, 55.0, 65.0, 75.0, 85.0]
        )
        let data = try JSONEncoder().encode(traj)
        let decoded = try JSONDecoder().decode(RunRateTrajectory.self, from: data)
        #expect(decoded == traj)
    }
}
