import Foundation
import CorpusKit
import IJSAggregator
import QualityGateTypes

import QualityGateLogging

/// Reads quality gate telemetry from a corpus directory.
///
/// Expected layout:
/// ```
/// <corpusPath>/telemetry/<project>/<date>/<timestamp>_metadata.json
/// ```
public struct CorpusReader: Sendable {
    private let corpusPath: String
    private static let logger = Logger(subsystem: "com.quality-gate", category: "CorpusReader")

    /// Creates a reader for the given corpus directory.
    public init(corpusPath: String) {
        self.corpusPath = corpusPath
    }

    /// Discovers all project IDs in the corpus.
    public func discoverProjects() throws -> [String] {
        let telemetryPath = "\(corpusPath)/telemetry" // SAFETY: corpusPath is set by configuration, not user input
        let fm = FileManager.default
        guard fm.fileExists(atPath: telemetryPath) else { return [] } // SAFETY: read-only existence check on configured path
        let contents = try fm.contentsOfDirectory(atPath: telemetryPath) // SAFETY: reads configured corpus directory
        return contents.filter { name in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: "\(telemetryPath)/\(name)", isDirectory: &isDir) && isDir.boolValue // SAFETY: reads subdir of configured corpus
        }
    }

    /// Loads all runs for a project, sorted by timestamp.
    ///
    /// Every run is decoded in full, findings included, and all of them are held at once. For a
    /// project with a long history that is gigabytes; a reader that wants summaries, trends or
    /// the latest findings should call ``loadHistory(for:)`` instead.
    public func loadRuns(for project: String) throws -> [TimestampedRun] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var runs: [TimestampedRun] = []
        for filePath in try metadataFilePaths(for: project) {
            Self.withTransientMemoryReleased {
                guard let data = FileManager.default.contents(atPath: filePath) else { return } // SAFETY: path from metadataFilePaths, contained in the corpus
                do {
                    let metadata = try decoder.decode(CheckResultMetadata.self, from: data)
                    runs.append(TimestampedRun(metadata: metadata))
                } catch {
                    Self.logger.warning("Skipping malformed JSON at \(filePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        return runs.sorted { $0.metadata.timestamp < $1.metadata.timestamp }
    }

    /// Loads a project's history without holding every finding it ever recorded.
    ///
    /// Each run file is decoded as a ``RunOutline`` — statuses, scopes and timestamps, no
    /// diagnostics — one file at a time. Only the files that hold a checker's most recent
    /// standard-mode result are then read in full, which is usually the last full run and a
    /// handful of targeted re-runs. Peak memory is one run file, not the project's history.
    ///
    /// - Parameter project: The project identifier; must be a single path component.
    /// - Returns: The outline runs and the composed latest results (see ``ProjectHistory``).
    /// - Throws: When `project` is not a single path component or escapes the corpus, or when
    ///   a telemetry directory cannot be listed.
    public func loadHistory(for project: String) throws -> ProjectHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var outlines: [(run: TimestampedRun, filePath: String)] = []
        for filePath in try metadataFilePaths(for: project) {
            Self.withTransientMemoryReleased {
                guard let data = FileManager.default.contents(atPath: filePath) else { return } // SAFETY: path from metadataFilePaths, contained in the corpus
                do {
                    let outline = try decoder.decode(RunOutline.self, from: data)
                    outlines.append((TimestampedRun(metadata: outline.metadata), filePath))
                } catch {
                    Self.logger.warning("Skipping malformed JSON at \(filePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        outlines.sort { $0.run.metadata.timestamp < $1.run.metadata.timestamp }

        // The same fold as `TimestampedRun.latestStandardResults(of:)` — standard runs, oldest
        // to newest, later overwriting earlier — but recording *where* each checker's latest
        // result lives rather than the result itself, which the outline does not have.
        var fileHoldingLatest: [String: String] = [:]
        for outline in outlines where outline.run.metadata.gateMode == .standard {
            for result in outline.run.metadata.results {
                fileHoldingLatest[result.checkerId] = outline.filePath
            }
        }

        var latestForChecker: [String: CheckResult] = [:]
        for filePath in Set(fileHoldingLatest.values) {
            Self.withTransientMemoryReleased {
                guard let data = FileManager.default.contents(atPath: filePath) else { return } // SAFETY: path from metadataFilePaths, contained in the corpus
                do {
                    let metadata = try decoder.decode(CheckResultMetadata.self, from: data)
                    for result in metadata.results where fileHoldingLatest[result.checkerId] == filePath {
                        latestForChecker[result.checkerId] = result
                    }
                } catch {
                    Self.logger.warning("Could not re-read \(filePath, privacy: .public) for its findings; its checkers are missing from the latest results: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        return ProjectHistory(runs: outlines.map(\.run),
                              latestStandardResults: Array(latestForChecker.values))
    }

    /// Every `*_metadata.json` path recorded for a project, after the project id is validated.
    private func metadataFilePaths(for project: String) throws -> [String] {
        // `project` is untrusted. The comment here used to say "project from discoverProjects",
        // which was true when the only caller listed the directory itself — and false once
        // ijs-mcp-server began passing `project_id` straight from a tool call. A crafted value
        // read a different corpus and returned a valid-looking score.
        try CorpusPath.requireSingleComponent(project, label: "project id")

        let projectPath = "\(corpusPath)/telemetry/\(project)"
        guard CorpusPath.contains(projectPath, within: corpusPath) else {
            throw IJSError.telemetryWriteFailed(
                reason: "Project path for '\(project)' escapes corpus base \(corpusPath)")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: projectPath) else { return [] } // SAFETY: contained, read-only

        var paths: [String] = []
        let dateDirs = try fm.contentsOfDirectory(atPath: projectPath) // SAFETY: reads configured corpus subdirectory
        for dateDir in dateDirs {
            let datePath = "\(projectPath)/\(dateDir)" // SAFETY: child of configured corpus path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: datePath, isDirectory: &isDir), isDir.boolValue else { continue } // SAFETY: read-only directory check

            let files = try fm.contentsOfDirectory(atPath: datePath) // SAFETY: reads date subdirectory of corpus
            for file in files where file.hasSuffix("_metadata.json") {
                paths.append("\(datePath)/\(file)") // SAFETY: child of configured corpus path
            }
        }
        return paths
    }

    /// Runs `body`, then releases what it left behind for the autorelease pool.
    ///
    /// Reading a file hands back autoreleased storage on Darwin. A loop over twenty thousand
    /// run files with no pool keeps every one of them alive until the caller's pool drains,
    /// which for a detached task is whenever the thread next goes idle.
    private static func withTransientMemoryReleased(_ body: () -> Void) {
        #if canImport(ObjectiveC)
        autoreleasepool(invoking: body)
        #else
        body()
        #endif
    }

    /// Loads all projects and their runs.
    public func loadAll() throws -> [String: [TimestampedRun]] {
        let projects = try discoverProjects()
        var result: [String: [TimestampedRun]] = [:]
        for project in projects {
            result[project] = try loadRuns(for: project)
        }
        return result
    }

    // MARK: - Manifest Loading

    /// Loads the corpus manifest from `<corpusPath>/manifest.yml`.
    ///
    /// Returns an empty manifest (treating all projects as active) if the
    /// file does not exist.
    ///
    /// - Returns: The decoded ``CorpusManifest``.
    /// - Throws: ``IJSError/configurationError(reason:)`` if the file exists but cannot be parsed.
    public func loadManifest() throws -> CorpusManifest {
        let manifestURL = URL(fileURLWithPath: "\(corpusPath)/manifest.yml") // SAFETY: corpusPath from configuration
        return try CorpusManifest.load(from: manifestURL)
    }

    /// Saves the manifest back to the corpus directory.
    /// - Parameter manifest: The manifest to save.
    public func saveManifest(_ manifest: CorpusManifest) throws {
        let manifestURL = URL(fileURLWithPath: "\(corpusPath)/manifest.yml") // SAFETY: corpusPath from configuration
        try manifest.save(to: manifestURL)
    }

    // MARK: - Pulse Loading

    /// The corpus `pulse/` directory, standardized and checked for containment.
    ///
    /// `corpusPath` reaches this type from configuration, but configuration is a file on
    /// disk that can name anything, so it is not a trusted literal. Standardizing collapses
    /// any `..` it carries *before* the directory is listed, and ``CorpusPath/contains(_:within:)``
    /// compares path components — not a string prefix, which would accept `/corpus-evil`
    /// for a base of `/corpus`. Returns `nil` when the pulse directory would fall outside
    /// the corpus, so every caller reports "no pulse" rather than reading a foreign tree.
    private static func pulseDirectoryURL(inCorpusAt corpusPath: String) -> URL? {
        let baseURL = URL(fileURLWithPath: corpusPath).standardized
        let pulseURL = baseURL.appendingPathComponent("pulse", isDirectory: true).standardized
        guard CorpusPath.contains(pulseURL.path, within: baseURL.path) else { return nil }
        return pulseURL
    }

    /// Names of the label subdirectories directly inside `pulseURL`.
    ///
    /// Listing by URL asks the file system which entries are directories instead of
    /// re-joining each name onto a path string and stat-ing it, so the returned names are
    /// single components by construction — a label can never reintroduce a separator.
    ///
    /// - Throws: `CocoaError.fileReadNoSuchFile` when the pulse directory does not exist,
    ///   which callers treat as an empty corpus rather than an error.
    private static func labelDirectoryNames(in pulseURL: URL) throws -> [String] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: pulseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var names: [String] = []
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            names.append(entry.lastPathComponent)
        }
        return names
    }

    /// The pulse JSON file for `label` inside an already-validated pulse directory.
    ///
    /// Each component is appended separately so that a label is always one path component:
    /// `appendingPathComponent` percent-encodes a separator rather than descending.
    private static func pulseFileURL(in pulseURL: URL, label: String) -> URL {
        pulseURL
            .appendingPathComponent(label, isDirectory: true)
            .appendingPathComponent("PULSE_\(label).json")
    }

    /// Loads the most recent InstitutionalPulse from the corpus pulse directory.
    ///
    /// Scans `<corpusPath>/pulse/` for labeled directories (both `YYYY-WNN`
    /// week labels and `YYYY-MM-DD` date labels), sorts chronologically,
    /// then returns the pulse from the latest one.
    /// Returns nil if no pulse directory exists or all files are malformed.
    public func loadLatestPulse() -> InstitutionalPulse? {
        guard let pulseURL = Self.pulseDirectoryURL(inCorpusAt: corpusPath) else { return nil }

        let labelDirs: [String]
        do {
            labelDirs = try Self.labelDirectoryNames(in: pulseURL)
                .sorted { lhs, rhs in
                    Self.chronologicalDescending(lhs, rhs)
                }
        } catch CocoaError.fileReadNoSuchFile {
            Self.logger.debug("Corpus at \(pulseURL.path, privacy: .public) has no pulse directory yet")
            return nil
        } catch {
            Self.logger.warning("Failed to list pulse directory \(pulseURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for dirLabel in labelDirs {
            let fileURL = Self.pulseFileURL(in: pulseURL, label: dirLabel)
            do {
                return try decoder.decode(InstitutionalPulse.self, from: Data(contentsOf: fileURL))
            } catch CocoaError.fileReadNoSuchFile {
                Self.logger.debug("Pulse directory \(dirLabel, privacy: .public) holds no pulse file")
                continue
            } catch {
                Self.logger.warning("Skipping malformed pulse at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        return nil
    }

    /// Lists all week labels that have a valid pulse JSON file, sorted ascending.
    ///
    /// Delegates to ``listAvailableLabels()`` for backward compatibility.
    public func listAvailableWeeks() -> [String] {
        listAvailableLabels()
    }

    /// Lists all pulse labels (both `YYYY-WNN` and `YYYY-MM-DD` formats) that
    /// have a valid pulse JSON file, sorted chronologically ascending.
    public func listAvailableLabels() -> [String] {
        guard let pulseURL = Self.pulseDirectoryURL(inCorpusAt: corpusPath) else { return [] }

        let labelDirs: [String]
        do {
            labelDirs = try Self.labelDirectoryNames(in: pulseURL)
        } catch CocoaError.fileReadNoSuchFile {
            Self.logger.debug("Corpus at \(pulseURL.path, privacy: .public) has no pulse directory yet")
            return []
        } catch {
            Self.logger.warning("Failed to list pulse directory \(pulseURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var labels: [String] = []
        for name in labelDirs {
            let fileURL = Self.pulseFileURL(in: pulseURL, label: name)
            do {
                _ = try decoder.decode(InstitutionalPulse.self, from: Data(contentsOf: fileURL))
                labels.append(name)
            } catch CocoaError.fileReadNoSuchFile {
                Self.logger.debug("Pulse directory \(name, privacy: .public) holds no pulse file")
            } catch {
                Self.logger.warning("Skipping malformed pulse at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return labels.sorted { lhs, rhs in
            Self.chronologicalAscending(lhs, rhs)
        }
    }

    /// Loads a specific pulse by label (date or week format).
    ///
    /// - Parameter label: Pulse label (e.g., "2026-W20" or "2026-06-05").
    /// - Returns: The decoded pulse, or nil if not found or malformed.
    public func loadPulse(label: String) -> InstitutionalPulse? {
        // Guarded since it was written, but by string prefix. `hasPrefix` accepts
        // `/corpus-evil` for a base of `/corpus`, which is why `CorpusPathContainment`
        // compares path *components* instead. The label is also checked as an identifier, so
        // a traversal attempt fails as "not a label" rather than as "no such pulse".
        guard CorpusPath.isSingleComponent(label) else { return nil }
        guard let pulseURL = Self.pulseDirectoryURL(inCorpusAt: corpusPath) else { return nil }
        let fileURL = Self.pulseFileURL(in: pulseURL, label: label).standardized
        guard CorpusPath.contains(fileURL.path, within: pulseURL.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(InstitutionalPulse.self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            Self.logger.debug("Corpus holds no pulse for label \(label, privacy: .public)")
            return nil
        } catch {
            Self.logger.warning("Failed to decode pulse \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Loads a specific pulse by week label.
    ///
    /// Delegates to ``loadPulse(label:)`` for backward compatibility.
    ///
    /// - Parameter weekLabel: ISO week label (e.g., "2026-W20").
    /// - Returns: The decoded pulse, or nil if not found or malformed.
    public func loadPulse(weekLabel: String) -> InstitutionalPulse? {
        loadPulse(label: weekLabel)
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

    /// Sorts two labels chronologically descending (latest first).
    private static func chronologicalDescending(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDate = parseLabelDate(lhs)
        let rhsDate = parseLabelDate(rhs)
        switch (lhsDate, rhsDate) {
        case let (.some(l), .some(r)):
            return l > r
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs > rhs
        }
    }

    /// Sorts two labels chronologically ascending (earliest first).
    private static func chronologicalAscending(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDate = parseLabelDate(lhs)
        let rhsDate = parseLabelDate(rhs)
        switch (lhsDate, rhsDate) {
        case let (.some(l), .some(r)):
            return l < r
        case (.some, .none):
            return false
        case (.none, .some):
            return true
        case (.none, .none):
            return lhs < rhs
        }
    }

    /// The most recent orientation report for a project, or `nil` when none exists.
    public func loadLatestOrientationReport(for project: String) throws -> OrientationReport? {
        try CorpusPath.requireSingleComponent(project, label: "project id")

        let projectPath = "\(corpusPath)/telemetry/\(project)"
        guard CorpusPath.contains(projectPath, within: corpusPath) else {
            throw IJSError.telemetryWriteFailed(
                reason: "Project path for '\(project)' escapes corpus base \(corpusPath)")
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectPath) else { return nil } // SAFETY: read-only existence check

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var latest: OrientationReport?
        let dateDirs = try fm.contentsOfDirectory(atPath: projectPath) // SAFETY: reads configured corpus subdirectory
        for dateDir in dateDirs {
            let datePath = "\(projectPath)/\(dateDir)" // SAFETY: child of configured corpus path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: datePath, isDirectory: &isDir), isDir.boolValue else { continue } // SAFETY: read-only directory check

            let files = try fm.contentsOfDirectory(atPath: datePath) // SAFETY: reads date subdirectory of corpus
            for file in files where file.hasSuffix("_orientation.json") {
                let filePath = "\(datePath)/\(file)" // SAFETY: child of configured corpus path
                guard let data = fm.contents(atPath: filePath) else { continue } // SAFETY: reads JSON from corpus
                do {
                    let report = try decoder.decode(OrientationReport.self, from: data)
                    if latest == nil || report.timestamp > (latest?.timestamp ?? .distantPast) {
                        latest = report
                    }
                } catch {
                    Self.logger.warning("Skipping malformed orientation JSON at \(filePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }
        }
        return latest
    }

    /// The latest orientation report for every project in the corpus.
    public func loadAllOrientationReports() throws -> [String: OrientationReport] {
        var result: [String: OrientationReport] = [:]
        for project in try discoverProjects() {
            if let report = try loadLatestOrientationReport(for: project) {
                result[project] = report
            }
        }
        return result
    }
}
