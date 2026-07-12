import Foundation

/// How corpus artifacts travel (Phase 3a §1).
///
/// The transport is the seam Phase 3b's service slots into: today every
/// caller uses ``DirectCorpusTransport`` (local filesystem, exactly the
/// behavior `TelemetryWriter` has always had); when a corpus grows a second
/// verified writer, a `.service` implementation takes the same calls over
/// HTTP without touching any call site. Reads are not a trust boundary in
/// solo mode, but they ride the same protocol so read-side governance (3b
/// §6) is a swap, not a refactor.
public protocol CorpusTransport: Sendable {

    // MARK: Writes

    /// Writes a run's metadata and any judgment calibrations.
    func write(
        metadata: CheckResultMetadata,
        calibrations: [JudgmentCalibration],
        to corpus: CorpusPath
    ) async throws

    /// Upserts a work event into the project's work log.
    func writeWorkEvent(_ event: WorkEvent, to corpus: CorpusPath) async throws

    /// Records a gate skip with its accountability reference.
    func writeSkip(_ record: SkipRecord, to corpus: CorpusPath) async throws

    /// Writes an institutional pulse.
    func writePulse(_ pulse: InstitutionalPulse, to corpus: CorpusPath) async throws

    /// Writes a daily snapshot.
    func writeSnapshot(_ snapshot: DailySnapshot, to corpus: CorpusPath) async throws

    /// Writes a complexity report.
    func writeComplexityReport(_ report: ComplexityReport, to corpus: CorpusPath) async throws

    /// Writes an orientation report.
    func writeOrientationReport(_ report: OrientationReport, to corpus: CorpusPath) async throws

    /// Writes the corpus manifest.
    func writeManifest(_ manifest: CorpusManifest, to basePath: String) async throws

    // MARK: Reads

    /// Reads metadata artifacts within a date range (inclusive), sorted by timestamp.
    func readMetadata(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [CheckResultMetadata]

    /// The most recent metadata artifact, or nil for an empty project.
    func readLatestMetadata(from corpus: CorpusPath) async throws -> CheckResultMetadata?

    /// Reads judgment calibrations within a date range.
    func readCalibrations(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [JudgmentCalibration]

    /// The most recent pulse, optionally before a given week label.
    func readLatestPulse(from corpus: CorpusPath, beforeWeek: String?) async throws -> InstitutionalPulse?

    /// Reads daily snapshots for a scope within a date range.
    func readSnapshots(
        from corpus: CorpusPath, scope: String, startDate: Date, endDate: Date
    ) async throws -> [DailySnapshot]

    /// Reads complexity reports within a date range.
    func readComplexityReports(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [ComplexityReport]

    /// Reads skip records within a date range.
    func readSkipRecords(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [SkipRecord]

    /// Reads the project's full work log.
    func readWorkLog(from corpus: CorpusPath) async throws -> [WorkEvent]

    /// Discovers project directories under a corpus root.
    func discoverProjects(in basePath: String) async throws -> [CorpusPath]

    /// Loads the corpus manifest (empty manifest when none exists).
    func loadManifest(from basePath: String) async throws -> CorpusManifest
}

public extension CorpusTransport {
    /// Reads the union of a project's identity directory and its aliased
    /// legacy directories, merged and sorted by timestamp — the manifest
    /// alias semantics (0.4), available on every transport.
    func readMetadataUnion(
        identity: String,
        basePath: String,
        manifest: CorpusManifest,
        startDate: Date,
        endDate: Date
    ) async throws -> [CheckResultMetadata] {
        var union: [CheckResultMetadata] = []
        for directory in manifest.directories(for: identity) {
            let path = CorpusPath(basePath: basePath, projectID: directory)
            union += try await readMetadata(from: path, startDate: startDate, endDate: endDate)
        }
        return union.sorted { $0.timestamp < $1.timestamp }
    }
}

/// The local-filesystem transport — solo mode's `.direct` (Phase 3a §1).
///
/// Delegates verbatim to ``TelemetryWriter``, so artifacts written through
/// the transport and through the writer are indistinguishable: existing
/// corpora need no migration, and switching a caller to the protocol is
/// mechanical.
public struct DirectCorpusTransport: CorpusTransport {
    private let writer: TelemetryWriter

    /// Creates a direct transport over the local filesystem.
    public init() {
        self.writer = TelemetryWriter()
    }

    /// Writes a run's metadata and any judgment calibrations.
    public func write(
        metadata: CheckResultMetadata,
        calibrations: [JudgmentCalibration],
        to corpus: CorpusPath
    ) async throws {
        try await writer.write(metadata: metadata, calibrations: calibrations, to: corpus)
    }

    /// Upserts a work event into the project's work log.
    public func writeWorkEvent(_ event: WorkEvent, to corpus: CorpusPath) async throws {
        try await writer.writeWorkEvent(event, to: corpus)
    }

    /// Records a gate skip with its accountability reference.
    public func writeSkip(_ record: SkipRecord, to corpus: CorpusPath) async throws {
        try await writer.writeSkip(record, to: corpus)
    }

    /// Writes an institutional pulse.
    public func writePulse(_ pulse: InstitutionalPulse, to corpus: CorpusPath) async throws {
        try await writer.writePulse(pulse, to: corpus)
    }

    /// Writes a daily snapshot.
    public func writeSnapshot(_ snapshot: DailySnapshot, to corpus: CorpusPath) async throws {
        try await writer.writeSnapshot(snapshot, to: corpus)
    }

    /// Writes a complexity report.
    public func writeComplexityReport(_ report: ComplexityReport, to corpus: CorpusPath) async throws {
        try await writer.writeComplexityReport(report, to: corpus)
    }

    /// Writes an orientation report.
    public func writeOrientationReport(_ report: OrientationReport, to corpus: CorpusPath) async throws {
        try await writer.writeOrientationReport(report, to: corpus)
    }

    /// Writes the corpus manifest.
    public func writeManifest(_ manifest: CorpusManifest, to basePath: String) async throws {
        try await writer.writeManifest(manifest, to: basePath)
    }

    /// Reads metadata artifacts within a date range, sorted by timestamp.
    public func readMetadata(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [CheckResultMetadata] {
        try await writer.readMetadata(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// The most recent metadata artifact, or nil for an empty project.
    public func readLatestMetadata(from corpus: CorpusPath) async throws -> CheckResultMetadata? {
        try await writer.readLatestMetadata(from: corpus)
    }

    /// Reads judgment calibrations within a date range.
    public func readCalibrations(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [JudgmentCalibration] {
        try await writer.readCalibrations(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// The most recent pulse, optionally before a given week label.
    public func readLatestPulse(
        from corpus: CorpusPath, beforeWeek: String?
    ) async throws -> InstitutionalPulse? {
        try await writer.readLatestPulse(from: corpus, beforeWeek: beforeWeek)
    }

    /// Reads daily snapshots for a scope within a date range.
    public func readSnapshots(
        from corpus: CorpusPath, scope: String, startDate: Date, endDate: Date
    ) async throws -> [DailySnapshot] {
        try await writer.readSnapshots(from: corpus, scope: scope, startDate: startDate, endDate: endDate)
    }

    /// Reads complexity reports within a date range.
    public func readComplexityReports(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [ComplexityReport] {
        try await writer.readComplexityReports(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// Reads skip records within a date range.
    public func readSkipRecords(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [SkipRecord] {
        try await writer.readSkipRecords(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// Reads the project's full work log.
    public func readWorkLog(from corpus: CorpusPath) async throws -> [WorkEvent] {
        try await writer.readWorkLog(from: corpus)
    }

    /// Discovers project directories under a corpus root.
    public func discoverProjects(in basePath: String) async throws -> [CorpusPath] {
        try await writer.discoverProjects(in: basePath)
    }

    /// Loads the corpus manifest (empty manifest when none exists).
    public func loadManifest(from basePath: String) async throws -> CorpusManifest {
        try await writer.loadManifest(from: basePath)
    }
}
