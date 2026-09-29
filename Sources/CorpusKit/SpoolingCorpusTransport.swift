import Foundation
import QualityGateLogging

/// One spooled write, serialized to disk while the upstream is unreachable
/// (Phase 3a §8).
///
/// The filename embeds the artifact timestamp and a payload discriminator so
/// drains replay in chronological order and re-drains are no-ops — replayed
/// artifacts land on their timestamp-keyed corpus paths, overwriting
/// themselves harmlessly.
struct SpoolEntry: Codable, Sendable {
    /// Which write operation this entry replays.
    enum Payload: Codable, Sendable {
        /// A run's metadata with its calibrations.
        case metadata(CheckResultMetadata, calibrations: [JudgmentCalibration])
        /// A work event.
        case workEvent(WorkEvent)
        /// A skip record.
        case skip(SkipRecord)
    }

    /// The operation to replay.
    let payload: Payload
    /// The corpus root the write targeted.
    let basePath: String
    /// The project directory the write targeted.
    let projectID: String
    /// The artifact's own timestamp — the ordering and idempotency key.
    let timestamp: Date
}

/// The fail-open decorator (Phase 3a §8): wraps any ``CorpusTransport`` and
/// guarantees the enforcement path never blocks on corpus availability.
///
/// Writes try the upstream first; on failure they spool to a local directory
/// and return normally — the gate's verdict was computed locally and a down
/// corpus must never change it. ``drainSpool()`` replays spooled entries in
/// timestamp order and deletes them on success; replay is idempotent because
/// corpus artifact paths are timestamp-keyed. Reads delegate to the upstream
/// untouched (solo `.direct` reads are local; service reads fall back to the
/// last-synced git state by deployment, not by this type).
public struct SpoolingCorpusTransport: CorpusTransport {
    private static let logger = Logger(subsystem: "com.quality-gate", category: "SpoolingCorpusTransport")

    private let upstream: any CorpusTransport
    private let spoolDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a spooling transport.
    /// - Parameters:
    ///   - upstream: The transport writes are attempted against.
    ///   - spoolDirectory: Where failed writes are held until a drain.
    public init(upstream: any CorpusTransport, spoolDirectory: URL) {
        self.upstream = upstream
        self.spoolDirectory = spoolDirectory
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Spooled writes

    /// Writes metadata and calibrations, spooling on upstream failure.
    public func write(
        metadata: CheckResultMetadata,
        calibrations: [JudgmentCalibration],
        to corpus: CorpusPath
    ) async throws {
        do {
            try await upstream.write(metadata: metadata, calibrations: calibrations, to: corpus)
        } catch {
            Self.logger.warning("Upstream metadata write failed (\(error.localizedDescription, privacy: .public)) — spooling")
            try spool(SpoolEntry(
                payload: .metadata(metadata, calibrations: calibrations),
                basePath: corpus.basePath, projectID: corpus.projectID,
                timestamp: metadata.timestamp))
        }
    }

    /// Writes a work event, spooling on upstream failure.
    public func writeWorkEvent(_ event: WorkEvent, to corpus: CorpusPath) async throws {
        do {
            try await upstream.writeWorkEvent(event, to: corpus)
        } catch {
            Self.logger.warning("Upstream work-event write failed (\(error.localizedDescription, privacy: .public)) — spooling")
            try spool(SpoolEntry(
                payload: .workEvent(event),
                basePath: corpus.basePath, projectID: corpus.projectID,
                timestamp: event.date))
        }
    }

    /// Writes a skip record, spooling on upstream failure.
    public func writeSkip(_ record: SkipRecord, to corpus: CorpusPath) async throws {
        do {
            try await upstream.writeSkip(record, to: corpus)
        } catch {
            Self.logger.warning("Upstream skip write failed (\(error.localizedDescription, privacy: .public)) — spooling")
            try spool(SpoolEntry(
                payload: .skip(record),
                basePath: corpus.basePath, projectID: corpus.projectID,
                timestamp: record.timestamp))
        }
    }

    // MARK: - Pass-through writes (pipeline artifacts, not enforcement-path)

    /// Writes a pulse — pipeline artifact, not spooled (regenerable).
    public func writePulse(_ pulse: InstitutionalPulse, to corpus: CorpusPath) async throws {
        try await upstream.writePulse(pulse, to: corpus)
    }

    /// Writes a snapshot — pipeline artifact, not spooled (regenerable).
    public func writeSnapshot(_ snapshot: DailySnapshot, to corpus: CorpusPath) async throws {
        try await upstream.writeSnapshot(snapshot, to: corpus)
    }

    /// Writes a complexity report — sidecar, not spooled (regenerable).
    public func writeComplexityReport(_ report: ComplexityReport, to corpus: CorpusPath) async throws {
        try await upstream.writeComplexityReport(report, to: corpus)
    }

    /// Writes an orientation report — sidecar, not spooled (regenerable).
    public func writeOrientationReport(_ report: OrientationReport, to corpus: CorpusPath) async throws {
        try await upstream.writeOrientationReport(report, to: corpus)
    }

    /// Writes the manifest — administrative, not spooled.
    public func writeManifest(_ manifest: CorpusManifest, to basePath: String) async throws {
        try await upstream.writeManifest(manifest, to: basePath)
    }

    // MARK: - Reads (delegate untouched)

    /// Reads metadata from the upstream.
    public func readMetadata(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [CheckResultMetadata] {
        try await upstream.readMetadata(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// Reads the latest metadata from the upstream.
    public func readLatestMetadata(from corpus: CorpusPath) async throws -> CheckResultMetadata? {
        try await upstream.readLatestMetadata(from: corpus)
    }

    /// Reads calibrations from the upstream.
    public func readCalibrations(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [JudgmentCalibration] {
        try await upstream.readCalibrations(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// Reads the latest pulse from the upstream.
    public func readLatestPulse(from corpus: CorpusPath, beforeWeek: String?) async throws -> InstitutionalPulse? {
        try await upstream.readLatestPulse(from: corpus, beforeWeek: beforeWeek)
    }

    /// Reads snapshots from the upstream.
    public func readSnapshots(
        from corpus: CorpusPath, scope: String, startDate: Date, endDate: Date
    ) async throws -> [DailySnapshot] {
        try await upstream.readSnapshots(from: corpus, scope: scope, startDate: startDate, endDate: endDate)
    }

    /// Reads complexity reports from the upstream.
    public func readComplexityReports(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [ComplexityReport] {
        try await upstream.readComplexityReports(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// Reads skip records from the upstream.
    public func readSkipRecords(
        from corpus: CorpusPath, startDate: Date, endDate: Date
    ) async throws -> [SkipRecord] {
        try await upstream.readSkipRecords(from: corpus, startDate: startDate, endDate: endDate)
    }

    /// Reads the work log from the upstream.
    public func readWorkLog(from corpus: CorpusPath) async throws -> [WorkEvent] {
        try await upstream.readWorkLog(from: corpus)
    }

    /// Discovers projects via the upstream.
    public func discoverProjects(in basePath: String) async throws -> [CorpusPath] {
        try await upstream.discoverProjects(in: basePath)
    }

    /// Loads the manifest via the upstream.
    public func loadManifest(from basePath: String) async throws -> CorpusManifest {
        try await upstream.loadManifest(from: basePath)
    }

    // MARK: - Drain

    /// Replays every spooled entry against the upstream in timestamp order,
    /// deleting each on success.
    ///
    /// Stops at the first replay failure (the upstream is presumably still
    /// down) leaving the remainder spooled; the next drain resumes from
    /// there. Returns the number of entries drained.
    @discardableResult
    public func drainSpool() async throws -> Int {
        // SAFETY: spoolDirectory is a trusted, deployment-configured path set at init, never attacker-derived — no path-traversal exposure [CWE-22].
        guard FileManager.default.fileExists(atPath: spoolDirectory.path) else { return 0 }
        // SAFETY: Enumerates only the trusted spoolDirectory; results are filtered to .json files this transport itself wrote [CWE-22].
        let files = try FileManager.default.contentsOfDirectory(atPath: spoolDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()

        var drained = 0
        for file in files {
            let url = spoolDirectory.appendingPathComponent(file)
            let entry: SpoolEntry
            do {
                entry = try decoder.decode(SpoolEntry.self, from: Data(contentsOf: url))
            } catch {
                Self.logger.error("Corrupt spool entry \(file, privacy: .public): \(error.localizedDescription, privacy: .public) — leaving in place")
                continue
            }
            let corpus = CorpusPath(basePath: entry.basePath, projectID: entry.projectID)
            do {
                switch entry.payload {
                case .metadata(let metadata, let calibrations):
                    try await upstream.write(metadata: metadata, calibrations: calibrations, to: corpus)
                case .workEvent(let event):
                    try await upstream.writeWorkEvent(event, to: corpus)
                case .skip(let record):
                    try await upstream.writeSkip(record, to: corpus)
                }
            } catch {
                Self.logger.warning("Spool drain stopped at \(file, privacy: .public): \(error.localizedDescription, privacy: .public)")
                break
            }
            try FileManager.default.removeItem(at: url)
            drained += 1
        }
        return drained
    }

    // MARK: - Spool write

    /// Serializes a failed write to the spool directory. The filename leads
    /// with the artifact timestamp so a directory sort IS chronological
    /// order; a UUID suffix keeps same-second writes distinct.
    ///
    /// The caller (the per-operation catch block) is responsible for logging
    /// the upstream error before delegating here.
    private func spool(_ entry: SpoolEntry) throws {
        try FileManager.default.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime]
        let stamp = formatter.string(from: entry.timestamp)
            .replacingOccurrences(of: ":", with: "-")
        let url = spoolDirectory.appendingPathComponent("\(stamp)-\(UUID().uuidString).json")
        try encoder.encode(entry).write(to: url, options: .atomic)
    }
}
