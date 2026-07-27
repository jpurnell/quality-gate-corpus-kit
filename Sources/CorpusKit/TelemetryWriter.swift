import Foundation
#if canImport(os)
import os
#endif

/// Writes and reads IJS telemetry artifacts as JSON files in the corpus.
///
/// All operations are async to avoid blocking the caller during file I/O.
/// Write operations use a single-writer model — concurrent writes to the
/// same daily directory are safe because filenames include HHmmss timestamps.
public actor TelemetryWriter {

    private static let logger = Logger(subsystem: "com.quality-gate", category: "TelemetryWriter")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a new telemetry writer with ISO 8601 date encoding and sorted, pretty-printed JSON.
    public init() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Writes a CheckResultMetadata and any JudgmentCalibrations to the corpus.
    ///
    /// Creates the daily directory if it doesn't exist.
    ///
    /// - Throws: `IJSError.telemetryWriteFailed` if directory creation or file write fails.
    public func write(
        metadata: CheckResultMetadata,
        calibrations: [JudgmentCalibration],
        to corpusPath: CorpusPath
    ) async throws {
        let dailyDir = try sanitizedURL(corpusPath.dailyDirectory(for: metadata.timestamp), within: corpusPath.basePath)
        try createDirectoryIfNeeded(at: dailyDir)

        let metadataURL = try sanitizedURL(corpusPath.metadataPath(for: metadata.timestamp), within: corpusPath.basePath)
        try writeJSON(metadata, to: metadataURL)

        if calibrations.count > 1 {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, calibration) in calibrations.enumerated() {
                    let url = try sanitizedURL(corpusPath.calibrationPath(for: metadata.timestamp, index: index), within: corpusPath.basePath)
                    let data = try self.encoder.encode(calibration)
                    group.addTask {
                        try data.write(to: url, options: .atomic)
                    }
                }
                try await group.waitForAll()
            }
        } else if let calibration = calibrations.first {
            let url = try sanitizedURL(corpusPath.calibrationPath(for: metadata.timestamp, index: 0), within: corpusPath.basePath)
            try writeJSON(calibration, to: url)
        }
    }

    /// Reads all metadata artifacts for a project within a date range (inclusive).
    ///
    /// Scans daily directories concurrently. Results are sorted by timestamp.
    ///
    /// - Throws: `IJSError.telemetryReadFailed` if deserialization fails.
    public func readMetadata(
        from corpusPath: CorpusPath,
        startDate: Date,
        endDate: Date
    ) async throws -> [CheckResultMetadata] {
        let directories = try dailyDirectoryURLs(in: corpusPath, startDate: startDate, endDate: endDate)
        guard !directories.isEmpty else { return [] }

        let allMetadata = try await withThrowingTaskGroup(
            of: [CheckResultMetadata].self
        ) { group in
            for dir in directories {
                let dec = self.decoder
                group.addTask {
                    try Self.readMetadataFiles(in: dir, decoder: dec)
                }
            }
            var results: [CheckResultMetadata] = []
            for try await batch in group {
                results.append(contentsOf: batch)
            }
            return results
        }

        return allMetadata.sorted { $0.timestamp < $1.timestamp }
    }

    /// Reads a project's metadata as the union of its identity directory and
    /// any aliased legacy directories from the manifest (Phase 0.4).
    ///
    /// History stays where it was written — aliases let renamed or
    /// re-identified projects keep one continuous time series.
    ///
    /// - Throws: `IJSError.telemetryReadFailed` if deserialization fails.
    public func readMetadataUnion(
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

    /// Returns the most recent metadata artifact for a project, or `nil` when
    /// the project has no telemetry.
    ///
    /// Scans daily directories newest-first and stops at the first hit.
    public func readLatestMetadata(
        from corpusPath: CorpusPath
    ) async throws -> CheckResultMetadata? {
        let projectURL = URL(fileURLWithPath: corpusPath.projectDirectory)
            .standardized.resolvingSymlinksInPath()
        // SAFETY: Path resolved via standardized + resolvingSymlinksInPath above
        guard FileManager.default.fileExists(atPath: projectURL.path) else { return nil }

        let baseURL = URL(fileURLWithPath: corpusPath.basePath)
            .standardized.resolvingSymlinksInPath()

        guard let contents = try? FileManager.default.contentsOfDirectory( // silent: returns nil when directory is unreadable
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        let dailyDirs = contents
            .filter { url in
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(baseURL.path) else { return false }
                var isDir: ObjCBool = false
                // SAFETY: Path validated against base via hasPrefix above
                return FileManager.default.fileExists(
                    atPath: resolved.path, isDirectory: &isDir
                ) && isDir.boolValue
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for dir in dailyDirs {
            let metadata = try Self.readMetadataFiles(in: dir, decoder: decoder)
            if let latest = metadata.sorted(by: { $0.timestamp < $1.timestamp }).last {
                return latest
            }
        }

        return nil
    }

    /// Discovers all project directories under `<basePath>/telemetry`.
    /// - Returns: One ``CorpusPath`` per project, sorted by project ID.
    public func discoverProjects(in basePath: String) throws -> [CorpusPath] {
        let telemetryURL = URL(fileURLWithPath: basePath)
            .appendingPathComponent("telemetry")
            .standardized.resolvingSymlinksInPath()
        // SAFETY: Path is resolved via standardized + resolvingSymlinksInPath above
        guard FileManager.default.fileExists(atPath: telemetryURL.path) else { return [] }

        let baseURL = URL(fileURLWithPath: basePath)
            .standardized.resolvingSymlinksInPath()

        guard let contents = try? FileManager.default.contentsOfDirectory( // silent: returns empty when directory is unreadable
            at: telemetryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents
            .filter { url in
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(baseURL.path) else { return false }
                var isDir: ObjCBool = false
                // SAFETY: Path validated against base via hasPrefix above
                return FileManager.default.fileExists(
                    atPath: resolved.path, isDirectory: &isDir
                ) && isDir.boolValue
            }
            .map { CorpusPath(basePath: basePath, projectID: $0.lastPathComponent) }
            .sorted { $0.projectID < $1.projectID }
    }

    /// Loads the corpus manifest from `<basePath>/manifest.yml`, returning an
    /// empty manifest when the file does not exist.
    ///
    /// Delegates to ``CorpusManifest/load(from:)`` — the hand-rolled format the
    /// real corpus uses (org-judgement-system's Yams-Codable reader could not
    /// parse quoted ISO dates; drift #3 reconciliation).
    public func loadManifest(from basePath: String) async throws -> CorpusManifest {
        let corpus = CorpusPath(basePath: basePath, projectID: "")
        let fileURL = URL(fileURLWithPath: corpus.manifestPath)
            .standardized.resolvingSymlinksInPath()
        let baseURL = URL(fileURLWithPath: basePath)
            .standardized.resolvingSymlinksInPath()

        guard fileURL.path.hasPrefix(baseURL.path) else {
            throw IJSError.telemetryReadFailed(
                reason: "Manifest path escapes corpus base"
            )
        }
        return try CorpusManifest.load(from: fileURL)
    }

    /// Writes the corpus manifest to `<basePath>/manifest.yml` in the
    /// canonical hand-rolled format (see ``CorpusManifest/save(to:)``).
    public func writeManifest(
        _ manifest: CorpusManifest,
        to basePath: String
    ) async throws {
        let corpus = CorpusPath(basePath: basePath, projectID: "")
        let fileURL = try sanitizedURL(corpus.manifestPath, within: basePath)
        do {
            try manifest.save(to: fileURL)
        } catch let error as IJSError {
            throw error
        } catch {
            throw IJSError.telemetryWriteFailed(
                reason: "Cannot write manifest to \(fileURL.path): \(error.localizedDescription)"
            )
        }
    }

    /// Reads all calibration artifacts for a project within a date range (inclusive).
    ///
    /// Daily directories are scanned concurrently. Results are sorted by date.
    ///
    /// - Throws: `IJSError.telemetryReadFailed` if deserialization fails.
    public func readCalibrations(
        from corpusPath: CorpusPath,
        startDate: Date,
        endDate: Date
    ) async throws -> [JudgmentCalibration] {
        let directories = try dailyDirectoryURLs(in: corpusPath, startDate: startDate, endDate: endDate)
        guard !directories.isEmpty else { return [] }

        let allCalibrations = try await withThrowingTaskGroup(
            of: [JudgmentCalibration].self
        ) { group in
            for dir in directories {
                let dec = self.decoder
                group.addTask {
                    try Self.readCalibrationFiles(in: dir, decoder: dec)
                }
            }
            var results: [JudgmentCalibration] = []
            for try await batch in group {
                results.append(contentsOf: batch)
            }
            return results
        }

        return allCalibrations.sorted { $0.date < $1.date }
    }

    // MARK: - Pulse I/O

    /// Writes an InstitutionalPulse to the corpus pulse directory.
    ///
    /// Uses `pulse.label` when present, falling back to `pulse.weekLabel` for directory naming.
    /// Creates the label directory if needed. Overwrites existing pulse for the same label.
    ///
    /// - Throws: `IJSError.telemetryWriteFailed` if directory creation or write fails.
    public func writePulse(
        _ pulse: InstitutionalPulse,
        to corpusPath: CorpusPath
    ) async throws {
        let effectiveLabel = pulse.label ?? pulse.weekLabel
        let labelDir = try sanitizedURL(
            corpusPath.pulseDirectory(weekLabel: effectiveLabel),
            within: corpusPath.basePath
        )
        try createDirectoryIfNeeded(at: labelDir)

        let fileURL = try sanitizedURL(
            corpusPath.pulsePath(weekLabel: effectiveLabel),
            within: corpusPath.basePath
        )
        try writeJSON(pulse, to: fileURL)
    }

    /// Reads the most recent InstitutionalPulse from the corpus.
    ///
    /// Scans the pulse root directory for labeled subdirectories (both
    /// `YYYY-WNN` week labels and `YYYY-MM-DD` date labels) and returns
    /// the pulse from the chronologically latest one.
    ///
    /// - Returns: The latest pulse, or `nil` if no pulses exist.
    /// - Throws: `IJSError.telemetryReadFailed` if deserialization fails.
    public func readLatestPulse(
        from corpusPath: CorpusPath,
        beforeWeek: String? = nil
    ) async throws -> InstitutionalPulse? {
        let pulseRootURL = URL(fileURLWithPath: corpusPath.pulseRoot)
            .standardized.resolvingSymlinksInPath()
        // SAFETY: Path is resolved via standardized + resolvingSymlinksInPath before use
        guard FileManager.default.fileExists(atPath: pulseRootURL.path) else { return nil }

        let baseURL = URL(fileURLWithPath: corpusPath.basePath)
            .standardized.resolvingSymlinksInPath()

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: pulseRootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )
        } catch {
            Self.logger.warning("Failed to list pulse directory \(pulseRootURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let labelDirs = contents
            .filter { url in
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(baseURL.path) else { return false }
                var isDir: ObjCBool = false
                // SAFETY: Path validated against base via hasPrefix above
                return FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) && isDir.boolValue
            }
            .sorted { lhs, rhs in
                let lhsDate = Self.parseLabelDate(lhs.lastPathComponent)
                let rhsDate = Self.parseLabelDate(rhs.lastPathComponent)
                switch (lhsDate, rhsDate) {
                case let (.some(l), .some(r)):
                    return l > r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.lastPathComponent > rhs.lastPathComponent
                }
            }

        for labelDir in labelDirs {
            let dirLabel = labelDir.lastPathComponent
            // beforeWeek excludes the current label (and anything newer) so a
            // refine run can find its predecessor (drift #11, org heritage).
            if let limit = beforeWeek, dirLabel >= limit { continue }
            let filePath = corpusPath.pulsePath(weekLabel: dirLabel)
            let fileURL = URL(fileURLWithPath: filePath).standardized.resolvingSymlinksInPath()
            guard fileURL.path.hasPrefix(baseURL.path) else { continue }
            // SAFETY: Path validated against base via hasPrefix above
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            do {
                let data = try Data(contentsOf: fileURL)
                return try decoder.decode(InstitutionalPulse.self, from: data)
            } catch {
                throw IJSError.telemetryReadFailed(
                    reason: "Cannot read \(fileURL.path): \(error.localizedDescription)"
                )
            }
        }

        return nil
    }

    // MARK: - Label Date Parsing

    /// Parses a pulse label into a `Date` for chronological sorting.
    ///
    /// Supports two formats:
    /// - `YYYY-MM-DD` (daily date labels) — parsed directly
    /// - `YYYY-WNN` (ISO week labels) — resolved to Monday of that week
    ///
    /// - Returns: The parsed date, or `nil` if the label is not in a recognized format.
    static func parseLabelDate(_ label: String) -> Date? {
        // Try YYYY-MM-DD first
        if label.count == 10, label.dropFirst(4).first == "-", label.dropFirst(7).first == "-" {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.locale = Locale(identifier: "en_US_POSIX")
            if let date = fmt.date(from: label) {
                return date
            }
        }

        // Try YYYY-WNN
        if label.count == 8, label.dropFirst(4).hasPrefix("-W") {
            guard let year = Int(label.prefix(4)),
                  let week = Int(label.suffix(2)),
                  week >= 1, week <= 53 else {
                return nil
            }
            var components = DateComponents()
            components.yearForWeekOfYear = year
            components.weekOfYear = week
            components.weekday = 2 // Monday (1=Sunday in Gregorian)
            components.timeZone = TimeZone(identifier: "UTC")
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            return calendar.date(from: components)
        }

        return nil
    }

    // MARK: - Snapshot I/O

    /// Writes a DailySnapshot to the corpus snapshots directory.
    ///
    /// Creates the scope directory if needed. Overwrites existing snapshot for the same date.
    ///
    /// - Throws: `IJSError.telemetryWriteFailed` if directory creation or write fails.
    public func writeSnapshot(
        _ snapshot: DailySnapshot,
        to corpusPath: CorpusPath
    ) async throws {
        let scopeDir = try sanitizedURL(
            corpusPath.snapshotDirectory(scope: snapshot.scope),
            within: corpusPath.basePath
        )
        try createDirectoryIfNeeded(at: scopeDir)

        let fileURL = try sanitizedURL(
            corpusPath.snapshotPath(scope: snapshot.scope, date: snapshot.date),
            within: corpusPath.basePath
        )
        try writeJSON(snapshot, to: fileURL)
    }

    /// Reads all DailySnapshots for a scope within a date range (inclusive).
    ///
    /// - Throws: `IJSError.telemetryReadFailed` if deserialization fails.
    public func readSnapshots(
        from corpusPath: CorpusPath,
        scope: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailySnapshot] {
        let scopeDir = URL(fileURLWithPath: corpusPath.snapshotDirectory(scope: scope))
            .standardized.resolvingSymlinksInPath()
        // SAFETY: Path is resolved via standardized + resolvingSymlinksInPath before use
        guard FileManager.default.fileExists(atPath: scopeDir.path) else { return [] }

        let baseURL = URL(fileURLWithPath: corpusPath.basePath)
            .standardized.resolvingSymlinksInPath()

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let startDay = dayFormatter.string(from: startDate)
        let endDay = dayFormatter.string(from: endDate)

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: scopeDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            Self.logger.warning("Failed to list snapshot directory \(scopeDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        return try files
            .filter { url in
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(baseURL.path) else { return false }
                let name = url.deletingPathExtension().lastPathComponent
                return name >= startDay && name <= endDay
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { fileURL in
                let standardized = fileURL.standardized
                do {
                    let data = try Data(contentsOf: standardized)
                    return try decoder.decode(DailySnapshot.self, from: data)
                } catch {
                    throw IJSError.telemetryReadFailed(
                        reason: "Cannot read \(standardized.path): \(error.localizedDescription)"
                    )
                }
            }
    }

    // MARK: - Complexity Report I/O

    /// Writes a ComplexityReport to the corpus daily directory.
    ///
    /// Creates the daily directory if it doesn't exist.
    ///
    /// - Throws: `IJSError.telemetryWriteFailed` if directory creation or file write fails.
    public func writeComplexityReport(
        _ report: ComplexityReport,
        to corpusPath: CorpusPath
    ) async throws {
        let dailyDir = try sanitizedURL(
            corpusPath.dailyDirectory(for: report.timestamp),
            within: corpusPath.basePath
        )
        try createDirectoryIfNeeded(at: dailyDir)

        let fileURL = try sanitizedURL(
            corpusPath.complexityPath(for: report.timestamp),
            within: corpusPath.basePath
        )
        try writeJSON(report, to: fileURL)
    }

    /// Writes a per-run orientation report to
    /// `telemetry/<projectID>/YYYY-MM-DD/HHmmss_orientation.json`.
    public func writeOrientationReport(
        _ report: OrientationReport,
        to corpusPath: CorpusPath
    ) async throws {
        let dailyDir = try sanitizedURL(
            corpusPath.dailyDirectory(for: report.timestamp),
            within: corpusPath.basePath
        )
        try createDirectoryIfNeeded(at: dailyDir)

        let fileURL = try sanitizedURL(
            corpusPath.orientationPath(for: report.timestamp),
            within: corpusPath.basePath
        )
        try writeJSON(report, to: fileURL)
    }

    /// Reads all ComplexityReport artifacts for a project within a date range (inclusive).
    ///
    /// Scans daily directories concurrently. Results are sorted by timestamp.
    ///
    /// - Throws: `IJSError.telemetryReadFailed` if deserialization fails.
    public func readComplexityReports(
        from corpusPath: CorpusPath,
        startDate: Date,
        endDate: Date
    ) async throws -> [ComplexityReport] {
        let directories = try dailyDirectoryURLs(in: corpusPath, startDate: startDate, endDate: endDate)
        guard !directories.isEmpty else { return [] }

        let allReports = try await withThrowingTaskGroup(
            of: [ComplexityReport].self
        ) { group in
            for dir in directories {
                let dec = self.decoder
                group.addTask {
                    try Self.readComplexityFiles(in: dir, decoder: dec)
                }
            }
            var results: [ComplexityReport] = []
            for try await batch in group {
                results.append(contentsOf: batch)
            }
            return results
        }

        return allReports.sorted { $0.timestamp < $1.timestamp }
    }

    /// Writes a quality-gate skip record to the corpus.
    public func writeSkip(
        _ record: SkipRecord,
        to corpusPath: CorpusPath
    ) async throws {
        let dailyDir = try sanitizedURL(
            corpusPath.dailyDirectory(for: record.timestamp),
            within: corpusPath.basePath
        )
        try createDirectoryIfNeeded(at: dailyDir)

        let fileURL = try sanitizedURL(
            corpusPath.skipPath(for: record.timestamp),
            within: corpusPath.basePath
        )
        try writeJSON(record, to: fileURL)
    }

    /// Reads skip records from the corpus within the given date range.
    public func readSkipRecords(
        from corpusPath: CorpusPath,
        startDate: Date,
        endDate: Date
    ) async throws -> [SkipRecord] {
        let directories = try dailyDirectoryURLs(
            in: corpusPath, startDate: startDate, endDate: endDate
        )
        guard !directories.isEmpty else { return [] }

        var records: [SkipRecord] = []
        for dir in directories {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasSuffix("_skip.json") }
            for file in files {
                let data = try Data(contentsOf: file)
                let record = try decoder.decode(SkipRecord.self, from: data)
                records.append(record)
            }
        }
        return records.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Work-Log I/O

    /// Reads the per-project work-log stream from the corpus.
    ///
    /// The work-log joins metric snapshots to the human work behind them. It is
    /// a single file per project (`work-log.json`) rather than a per-day
    /// artifact.
    ///
    /// - Returns: The recorded work-events sorted by date, or an empty array if
    ///   the file is absent.
    /// - Throws: `IJSError.telemetryReadFailed` if the file exists but cannot be deserialized.
    public func readWorkLog(from corpus: CorpusPath) async throws -> [WorkEvent] {
        let fileURL = try sanitizedURL(corpus.workLogPath, within: corpus.basePath)
        // SAFETY: Path is sanitized against the corpus base before use.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let events = try decoder.decode([WorkEvent].self, from: data)
            return events.sorted { $0.date < $1.date }
        } catch {
            throw IJSError.telemetryReadFailed(
                reason: "Cannot read \(fileURL.path): \(error.localizedDescription)"
            )
        }
    }

    /// Upserts a work-event into the per-project work-log, idempotently.
    ///
    /// Loads the existing log, then upserts by the key `(calendar-day of date,
    /// commitSHA)`: if an entry with the same day and SHA already exists it is
    /// **replaced**; otherwise the event is appended. The resulting list is kept
    /// sorted by date and written pretty-printed.
    ///
    /// - Throws: `IJSError.telemetryWriteFailed` if directory creation or the
    ///   write fails, or `IJSError.telemetryReadFailed` if the existing log
    ///   cannot be read.
    public func writeWorkEvent(_ event: WorkEvent, to corpus: CorpusPath) async throws {
        var events = try await readWorkLog(from: corpus)

        let key = Self.workLogKey(for: event)
        if let index = events.firstIndex(where: { Self.workLogKey(for: $0) == key }) {
            events[index] = event
        } else {
            events.append(event)
        }
        events.sort { $0.date < $1.date }

        let projectDir = try sanitizedURL(corpus.projectDirectory, within: corpus.basePath)
        try createDirectoryIfNeeded(at: projectDir)

        let fileURL = try sanitizedURL(corpus.workLogPath, within: corpus.basePath)
        try writeJSON(events, to: fileURL)
    }

    /// The idempotency key for a work-event: the calendar-day (UTC) of its date plus its commit SHA.
    private static func workLogKey(for event: WorkEvent) -> String {
        let day = workLogDayFormatter.string(from: event.date)
        return "\(day)|\(event.commitSHA ?? "")"
    }

    private static let workLogDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    // MARK: - Path Sanitization

    /// Validates that `path` is contained within `basePath` and returns a
    /// filesystem URL anchored on the base's canonical (symlink-free) location.
    ///
    /// Containment is checked **lexically and component-wise**: the target is
    /// standardized to collapse `.`/`..` without touching the filesystem, and
    /// the base's path components must be an exact prefix of the target's. This
    /// avoids two failure modes of a naive `hasPrefix` on symlink-resolved
    /// strings:
    /// - **Symlinked-base false rejection.** `resolvingSymlinksInPath()`
    ///   canonicalizes an existing base and a not-yet-created target subtree
    ///   asymmetrically (e.g. `/tmp` ↔ `/private/tmp`), so string prefixing
    ///   spuriously fails and breaks every corpus write under a symlinked path.
    /// - **Prefix-sibling escape.** String `hasPrefix` treats `/a/corpus-evil`
    ///   as inside `/a/corpus`; component comparison rejects it.
    ///
    /// The validated relative suffix is re-anchored onto the base resolved once
    /// via `resolvingSymlinksInPath()`, so the returned URL points at the real
    /// location even when the base is reached through a symlink.
    private func sanitizedURL(_ path: String, within basePath: String) throws -> URL {
        let lexicalBase = URL(fileURLWithPath: basePath).standardized
        let lexicalTarget = URL(fileURLWithPath: path).standardized

        let baseComponents = lexicalBase.pathComponents
        let targetComponents = lexicalTarget.pathComponents

        guard targetComponents.count >= baseComponents.count,
              Array(targetComponents.prefix(baseComponents.count)) == baseComponents else {
            throw IJSError.telemetryWriteFailed(reason: "Path \(path) escapes corpus base \(basePath)")
        }

        var resolved = URL(fileURLWithPath: basePath).resolvingSymlinksInPath()
        for component in targetComponents.dropFirst(baseComponents.count) {
            resolved.appendPathComponent(component)
        }
        return resolved
    }

    // MARK: - Private Helpers

    private func createDirectoryIfNeeded(at url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw IJSError.telemetryWriteFailed(reason: "Cannot create directory \(url.path): \(error.localizedDescription)")
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch let error as IJSError {
            throw error
        } catch {
            throw IJSError.telemetryWriteFailed(reason: "Cannot write \(url.path): \(error.localizedDescription)")
        }
    }

    private func dailyDirectoryURLs(
        in corpusPath: CorpusPath,
        startDate: Date,
        endDate: Date
    ) throws -> [URL] {
        let projectURL = URL(fileURLWithPath: corpusPath.projectDirectory).standardized.resolvingSymlinksInPath()
        // SAFETY: Path is resolved via standardized + resolvingSymlinksInPath before use
        guard FileManager.default.fileExists(atPath: projectURL.path) else { return [] }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let startDay = dayFormatter.string(from: startDate)
        let endDay = dayFormatter.string(from: endDate)

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: projectURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )
        } catch {
            Self.logger.warning("Failed to list project directory \(projectURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        let baseURL = URL(fileURLWithPath: corpusPath.basePath).standardized.resolvingSymlinksInPath()
        return contents
            .filter { url in
                let name = url.lastPathComponent
                return name >= startDay && name <= endDay
            }
            .filter { url in
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(baseURL.path) else { return false }
                var isDir: ObjCBool = false
                // SAFETY: Path validated against base via hasPrefix above
                return FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) && isDir.boolValue
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func readMetadataFiles(
        in directory: URL,
        decoder: JSONDecoder
    ) throws -> [CheckResultMetadata] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            logger.warning("Failed to list metadata directory \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        return try files
            .filter { $0.lastPathComponent.hasSuffix("_metadata.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { fileURL in
                let standardized = fileURL.standardized
                do {
                    let data = try Data(contentsOf: standardized)
                    return try decoder.decode(CheckResultMetadata.self, from: data)
                } catch {
                    throw IJSError.telemetryReadFailed(reason: "Cannot read \(standardized.path): \(error.localizedDescription)")
                }
            }
    }

    private static func readCalibrationFiles(
        in directory: URL,
        decoder: JSONDecoder
    ) throws -> [JudgmentCalibration] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            logger.warning("Failed to list calibration directory \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        return try files
            .filter { $0.lastPathComponent.contains("_calibration_") && $0.lastPathComponent.hasSuffix(".json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { fileURL in
                let standardized = fileURL.standardized
                do {
                    let data = try Data(contentsOf: standardized)
                    return try decoder.decode(JudgmentCalibration.self, from: data)
                } catch {
                    throw IJSError.telemetryReadFailed(reason: "Cannot read \(standardized.path): \(error.localizedDescription)")
                }
            }
    }

    private static func readComplexityFiles(
        in directory: URL,
        decoder: JSONDecoder
    ) throws -> [ComplexityReport] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            logger.warning("Failed to list complexity directory \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        return try files
            .filter { $0.lastPathComponent.hasSuffix("_complexity.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { fileURL in
                let standardized = fileURL.standardized
                do {
                    let data = try Data(contentsOf: standardized)
                    return try decoder.decode(ComplexityReport.self, from: data)
                } catch {
                    throw IJSError.telemetryReadFailed(reason: "Cannot read \(standardized.path): \(error.localizedDescription)")
                }
            }
    }
}
