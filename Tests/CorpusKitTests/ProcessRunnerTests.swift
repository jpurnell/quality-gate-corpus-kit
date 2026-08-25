import Testing
import Foundation
@testable import CorpusKit

/// Tests for ``ProcessRunner``, the audited subprocess kernel.
///
/// The two cases that matter here are the ones the ad-hoc `Process` call
/// sites could not survive: output larger than a pipe buffer (which
/// deadlocks a child that writes while nobody drains) and a child that
/// never exits (which pins the caller forever on `waitUntilExit()`).
@Suite("ProcessRunner")
struct ProcessRunnerTests {

    // MARK: - Basic Execution

    @Test("Captures stdout and a zero exit status")
    func capturesStandardOutput() throws {
        let result = try ProcessRunner.run(
            "/bin/echo", arguments: ["hello"], timeout: 10
        )
        #expect(result.terminationStatus == 0)
        #expect(result.timedOut == false)
        #expect(result.standardOutputText == "hello")
    }

    @Test("Captures stderr separately from stdout")
    func capturesStandardError() throws {
        let result = try ProcessRunner.run(
            "/bin/sh", arguments: ["-c", "echo out; echo err >&2"], timeout: 10
        )
        #expect(result.terminationStatus == 0)
        #expect(result.standardOutputText == "out")
        #expect(result.standardErrorText == "err")
    }

    @Test("Reports a non-zero exit status without throwing")
    func reportsFailureStatus() throws {
        let result = try ProcessRunner.run(
            "/bin/sh", arguments: ["-c", "exit 3"], timeout: 10
        )
        #expect(result.terminationStatus == 3)
        #expect(result.timedOut == false)
    }

    @Test("Runs in the requested working directory")
    func honoursWorkingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try ProcessRunner.run(
            "/bin/pwd", arguments: [], workingDirectory: dir.path, timeout: 10
        )
        #expect(result.terminationStatus == 0)
        // /var and /private/var alias on macOS; compare resolved paths.
        let reported = URL(fileURLWithPath: result.standardOutputText).resolvingSymlinksInPath().path
        #expect(reported == dir.resolvingSymlinksInPath().path)
    }

    // MARK: - Deadlock Resistance

    /// The regression that motivated the kernel: a child writing more than a
    /// pipe buffer (~64 KB) blocks until someone drains it. A reader that
    /// waits for exit before reading never gets there.
    @Test("Drains output larger than one pipe buffer without deadlocking")
    func survivesLargeOutput() throws {
        let result = try ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 20000); do echo 0123456789; done"],
            timeout: 60
        )
        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput.count > 200_000)
    }

    /// Same hazard on the other stream — the undrained-stderr case that
    /// `ProjectIdentity.originRemoteURL` shipped with.
    @Test("Drains large stderr without deadlocking")
    func survivesLargeStandardError() throws {
        let result = try ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 20000); do echo 0123456789 >&2; done"],
            timeout: 60
        )
        #expect(result.terminationStatus == 0)
        #expect(result.standardError.count > 200_000)
    }

    @Test("Drains both streams concurrently when both are large")
    func survivesLargeOutputOnBothStreams() throws {
        let result = try ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 10000); do echo aaaaaaaaaa; echo bbbbbbbbbb >&2; done"],
            timeout: 60
        )
        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput.count > 100_000)
        #expect(result.standardError.count > 100_000)
    }

    // MARK: - Timeout

    @Test("Terminates a child that outlives its timeout")
    func timesOutHangingChild() throws {
        let started = Date()
        let result = try ProcessRunner.run(
            "/bin/sh", arguments: ["-c", "sleep 60"], timeout: 1
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.timedOut == true)
        // A child killed by a signal reports that signal, not an exit code.
        #expect(result.terminationStatus == SIGTERM)
        // TIMING: The bound under test is itself wall-clock; 20x the 1s timeout absorbs load.
        #expect(elapsed < 20, "expected the timeout to bound the run, took \(elapsed)s")
    }

    /// A child that ignores SIGTERM must still be reaped, via SIGKILL.
    ///
    /// This case also pins down the subtler hazard it exposed: `sh` traps the
    /// signal and forks `sleep`, so killing `sh` leaves a grandchild holding
    /// the inherited pipe write ends open. Reading to EOF would then outlive
    /// the process being bounded, so the drain is bounded too and the result
    /// reports the capture as truncated instead of blocking for the full sleep.
    @Test("Escalates to SIGKILL and does not wait on a grandchild's pipe")
    func escalatesToKill() throws {
        let started = Date()
        let result = try ProcessRunner.run(
            "/bin/sh", arguments: ["-c", "trap '' TERM; sleep 60"], timeout: 1
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.timedOut == true)
        #expect(result.outputTruncated == true)
        // Before the drain was bounded this took the grandchild's full 60s sleep;
        // 30s sits well under that and well over the ~11s real path.
        // TIMING: Wall-clock is the property under test, not an incidental measurement.
        #expect(elapsed < 30, "expected SIGKILL escalation to bound the run, took \(elapsed)s")
    }

    @Test("A normally exiting child reports untruncated output")
    func normalExitIsNotTruncated() throws {
        let result = try ProcessRunner.run(
            "/bin/echo", arguments: ["complete"], timeout: 10
        )
        #expect(result.outputTruncated == false)
        #expect(result.succeeded)
    }

    @Test("A fast child is not delayed by the timeout budget")
    func fastChildReturnsPromptly() throws {
        let started = Date()
        _ = try ProcessRunner.run("/bin/echo", arguments: ["quick"], timeout: 30)
        // TIMING: Catches the kernel waiting out its whole budget on an exited child.
        #expect(Date().timeIntervalSince(started) < 10)
    }

    // MARK: - Invalid Input

    @Test("Throws when the executable does not exist")
    func throwsForMissingExecutable() {
        #expect(throws: (any Error).self) {
            try ProcessRunner.run(
                "/nonexistent/definitely-not-here", arguments: [], timeout: 10
            )
        }
    }

    @Test("Rejects a non-positive timeout")
    func rejectsNonPositiveTimeout() {
        #expect(throws: (any Error).self) {
            try ProcessRunner.run("/bin/echo", arguments: ["x"], timeout: 0)
        }
    }
}
