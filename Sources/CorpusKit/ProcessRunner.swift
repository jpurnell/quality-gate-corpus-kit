import Foundation
import QualityGateLogging

private let logger = Logger(subsystem: "com.ijs.core", category: "process-runner")

/// The outcome of a bounded subprocess run.
public struct ProcessResult: Sendable, Equatable {

    /// The child's exit status, or its signal-derived status when it was killed.
    public let terminationStatus: Int32

    /// Everything the child wrote to stdout.
    public let standardOutput: Data

    /// Everything the child wrote to stderr.
    public let standardError: Data

    /// Whether the run exceeded its timeout and the child was terminated.
    public let timedOut: Bool

    /// Whether capture was cut short because a stream never reached EOF.
    ///
    /// A grandchild that inherits the child's stdout or stderr keeps that
    /// write end open after the child itself is gone, so a read to EOF would
    /// outlive the process this call was bounding. When that happens the
    /// captured bytes are whatever arrived before the drain deadline, and
    /// this flag says so rather than passing a partial capture off as whole.
    public let outputTruncated: Bool

    /// Creates a result.
    /// - Parameters:
    ///   - terminationStatus: The child's exit status.
    ///   - standardOutput: Bytes captured from stdout.
    ///   - standardError: Bytes captured from stderr.
    ///   - timedOut: Whether the timeout fired.
    ///   - outputTruncated: Whether a stream failed to reach EOF in time.
    public init(
        terminationStatus: Int32,
        standardOutput: Data,
        standardError: Data,
        timedOut: Bool,
        outputTruncated: Bool = false
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
        self.outputTruncated = outputTruncated
    }

    /// `true` when the child exited zero and did not time out.
    public var succeeded: Bool { terminationStatus == 0 && !timedOut }

    /// Stdout decoded as UTF-8 with surrounding whitespace trimmed.
    public var standardOutputText: String {
        String(decoding: standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stderr decoded as UTF-8 with surrounding whitespace trimmed.
    public var standardErrorText: String {
        String(decoding: standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A mutable byte buffer safe to fill from a background drain queue.
// Justification: `storage` is only ever touched while `lock` is held.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(data)
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// The one place in this package that spawns a subprocess.
///
/// Every unbounded blocking primitive — `Process.run()`, `waitUntilExit()`,
/// `readDataToEndOfFile()` — is contained here so that exactly one file has
/// to be correct about two hazards that ad-hoc call sites kept getting wrong:
///
/// - **Pipe-buffer deadlock.** A child that writes more than the pipe buffer
///   (~64 KB) blocks until a reader drains it. A caller that waits for exit
///   before reading therefore waits forever, and a caller that attaches a
///   `Pipe` it never reads deadlocks the child the moment it gets chatty.
///   Both streams are drained concurrently here, started before the wait.
/// - **Unbounded wait.** `waitUntilExit()` returns when the child exits or
///   never. Every run made through this type carries a deadline, after which
///   the child gets `SIGTERM` and then, if it ignores that, `SIGKILL`.
///
/// Containment does not make this code right; it makes it the only code that
/// has to be. New subprocess work belongs in this file, not at the call site.
public enum ProcessRunner {

    /// How long to wait for a child to honour `SIGTERM` before sending `SIGKILL`.
    private static let sigkillGraceSeconds: TimeInterval = 5

    /// How long to keep draining after the child is gone, for output still in flight.
    private static let drainGraceSeconds: TimeInterval = 5

    /// Reported when a child could not be reaped even after `SIGKILL`, where
    /// no real exit status exists to report. Mirrors the shell's 128 + SIGKILL.
    static let unreapedStatus: Int32 = 137

    /// Runs an executable to completion, bounded by `timeout`.
    ///
    /// Both output streams are captured in full and drained concurrently, so
    /// a child may write arbitrarily much without stalling.
    ///
    /// A non-zero exit is reported in the result rather than thrown — a failed
    /// child is an outcome, not an error. Throwing is reserved for a run that
    /// could not be started at all, or arguments that make no sense.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable to spawn.
    ///   - arguments: Arguments passed directly to the child. These are never
    ///     shell-interpreted, so they need no shell quoting.
    ///   - workingDirectory: Directory to run in, or `nil` to inherit.
    ///   - timeout: Seconds to allow before terminating the child. Must be positive.
    /// - Returns: The captured result, with `timedOut` set when the deadline fired.
    /// - Throws: ``IJSError/configurationError(reason:)`` for a non-positive
    ///   timeout, or the underlying error when the process cannot be launched.
    public static func run(
        _ executablePath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) throws -> ProcessResult {
        guard timeout > 0 else {
            throw IJSError.configurationError(
                reason: "ProcessRunner timeout must be positive, got \(timeout)"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Signalled from the termination handler, which must be installed
        // before launch — a child can exit before `run()` even returns.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        // SAFETY: Caller-supplied executable path and argv are passed to posix_spawn directly, never through a shell, so argument content cannot be interpreted as commands [CWE-78].
        try process.run()

        // Drain both streams before waiting. Reading to EOF is bounded in
        // practice because EOF arrives when the child dies, and the child is
        // guaranteed to die below.
        let outBox = DataBox()
        let errBox = DataBox()
        let drained = DispatchGroup()
        drain(outPipe, into: outBox, group: drained)
        drain(errPipe, into: errBox, group: drained)

        var timedOut = false
        var reaped = true
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            logger.notice("process.timeout: terminating child after \(timeout, privacy: .public)s")
            process.terminate()

            if exited.wait(timeout: .now() + sigkillGraceSeconds) == .timedOut {
                logger.error("process.sigkill: child ignored SIGTERM, sending SIGKILL")
                kill(process.processIdentifier, SIGKILL)
                // Even this wait is bounded: a child wedged in uninterruptible
                // I/O does not die on SIGKILL either, and the whole point of
                // this type is that no caller waits forever on a child.
                reaped = exited.wait(timeout: .now() + sigkillGraceSeconds) == .success
                if !reaped {
                    logger.fault("process.unreaped: child survived SIGKILL; abandoning it")
                }
            }
        }

        // The child is dead, but that does not guarantee EOF: any grandchild
        // that inherited these write ends still holds them open. Bound the
        // join too, or a bounded run could still hang here on a process this
        // call never spawned and cannot reap.
        let fullyDrained = drained.wait(timeout: .now() + drainGraceSeconds) == .success
        if !fullyDrained {
            logger.error("process.drain-timeout: a stream never reached EOF; output is truncated")
        }

        // Reading `terminationStatus` before the child is reaped traps, so an
        // abandoned child reports the sentinel rather than crashing the caller.
        let status = reaped && !process.isRunning ? process.terminationStatus : Self.unreapedStatus

        return ProcessResult(
            terminationStatus: status,
            standardOutput: outBox.value,
            standardError: errBox.value,
            timedOut: timedOut,
            outputTruncated: !fullyDrained
        )
    }

    /// Reads `pipe` to EOF on a background queue, accumulating into `box`.
    private static func drain(_ pipe: Pipe, into box: DataBox, group: DispatchGroup) {
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            let handle = pipe.fileHandleForReading
            // `availableData` returns an empty buffer at EOF, which arrives
            // once every write end of this pipe is closed.
            var chunk = handle.availableData
            while !chunk.isEmpty {
                box.append(chunk)
                chunk = handle.availableData
            }
        }
    }
}
