import Foundation
import QualityGateLogging
import QualityGateTypes
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// How many diagnostics of each severity one checker recorded in one run.
///
/// The index drops the diagnostics themselves — they are nearly all of a run file — and keeps
/// this, so a reader can say "12 warnings" without opening the run.
public struct DiagnosticCounts: Sendable, Codable, Equatable {
    /// Diagnostics of severity `error`.
    public let errors: Int
    /// Diagnostics of severity `warning`.
    public let warnings: Int
    /// Diagnostics of severity `note`.
    public let notes: Int

    /// Creates a count.
    public init(errors: Int, warnings: Int, notes: Int) {
        self.errors = errors
        self.warnings = warnings
        self.notes = notes
    }

    /// A checker that recorded nothing.
    public static let zero = DiagnosticCounts(errors: 0, warnings: 0, notes: 0)

    /// Counts a result's diagnostics by severity.
    public init(of diagnostics: [Diagnostic]) {
        var errors = 0, warnings = 0, notes = 0
        for diagnostic in diagnostics {
            switch diagnostic.severity {
            case .error: errors += 1
            case .warning: warnings += 1
            case .note: notes += 1
            }
        }
        self.init(errors: errors, warnings: warnings, notes: notes)
    }
}

/// One line of a project's run index: a run, without its diagnostics, and where it lives.
///
/// `telemetry/<project>/index.jsonl` holds one of these per run, appended when the run is
/// written. It is **derived**: every entry can be regenerated from the file it names, and a
/// reader that finds the two disagreeing believes the file.
///
/// `run` is the run's own ``CheckResultMetadata``, so the index has no schema of its own for a
/// run — a field added there appears in new lines without this type changing.
public struct RunIndexEntry: VersionedCorpusArtifact, Equatable {
    /// The schema version this build writes.
    public static let currentSchemaVersion = 1
    /// The schema version this line was written with.
    public let schemaVersion: Int
    /// The run file, relative to the project directory: `YYYY-MM-DD/HHmmss_metadata.json`.
    public let file: String
    /// The run file's size in bytes when the line was written.
    public let bytes: Int
    /// The run's metadata with every result's `diagnostics` empty.
    public let run: CheckResultMetadata
    /// Diagnostic counts per checker id, standing in for the diagnostics `run` omits.
    ///
    /// Only checkers that recorded something appear. Most checkers in most runs record
    /// nothing, and writing forty zeroes a line made the counts a third of the index. Read
    /// through ``diagnosticCounts(for:)``, which answers zero for a checker that is absent.
    public let counts: [String: DiagnosticCounts]

    /// The diagnostic counts for one checker in this run — zero when it recorded none.
    public func diagnosticCounts(for checkerId: String) -> DiagnosticCounts {
        counts[checkerId] ?? .zero
    }

    /// Creates an entry for a run. `run` is stored without its diagnostics, which are counted
    /// into ``counts`` first.
    public init(file: String, bytes: Int, run: CheckResultMetadata) {
        var counts: [String: DiagnosticCounts] = [:]
        for result in run.results {
            let count = DiagnosticCounts(of: result.diagnostics)
            counts[result.checkerId] = count == .zero ? nil : count
        }
        self.init(file: file, bytes: bytes,
                  outline: CheckResultMetadata(strippingDiagnosticsFrom: run), counts: counts)
    }

    /// Creates an entry from an outline whose diagnostics were already counted.
    init(file: String, bytes: Int, outline: CheckResultMetadata, counts: [String: DiagnosticCounts]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.file = file
        self.bytes = bytes
        self.run = outline
        self.counts = counts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, file, bytes, run, counts
    }

    /// Decodes a line, refusing one written by a newer schema before reading anything else.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw RunIndex.LineError.newerSchema(schemaVersion)
        }
        file = try container.decode(String.self, forKey: .file)
        bytes = try container.decode(Int.self, forKey: .bytes)
        run = try container.decode(RunOutline.self, forKey: .run).metadata
        counts = try container.decodeIfPresent([String: DiagnosticCounts].self, forKey: .counts) ?? [:]
    }
}

/// A run file read for its outline and its diagnostic counts, and nothing else.
///
/// What ``TelemetryWriter/rebuildIndex(for:)`` decodes: the diagnostics are visited for their
/// severity only, so a run with fifteen thousand findings costs fifteen thousand bytes.
struct RunDigest: Decodable {
    let outline: CheckResultMetadata
    let counts: [String: DiagnosticCounts]

    private enum CodingKeys: String, CodingKey { case results }

    private struct ResultSeverities: Decodable {
        let checkerId: String
        let diagnostics: [SeverityOnly]
    }

    private struct SeverityOnly: Decodable {
        let severity: Diagnostic.Severity
    }

    init(from decoder: Decoder) throws {
        outline = try CheckResultMetadata(from: decoder, omittingDiagnostics: true)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var counts: [String: DiagnosticCounts] = [:]
        for result in try container.decode([ResultSeverities].self, forKey: .results) {
            var errors = 0, warnings = 0, notes = 0
            for diagnostic in result.diagnostics {
                switch diagnostic.severity {
                case .error: errors += 1
                case .warning: warnings += 1
                case .note: notes += 1
                }
            }
            let count = DiagnosticCounts(errors: errors, warnings: warnings, notes: notes)
            counts[result.checkerId] = count == .zero ? nil : count
        }
        self.counts = counts
    }
}

/// Reading and writing a project's run index.
public enum RunIndex {
    private static let logger = Logger(subsystem: "com.quality-gate", category: "RunIndex")

    /// The index file's name inside a project's telemetry directory.
    public static let fileName = "index.jsonl"

    /// Why one line could not be used.
    enum LineError: Error {
        /// The line was written by a schema this build does not know.
        case newerSchema(Int)
    }

    /// What an index file held.
    public struct Contents: Sendable {
        /// The lines that decoded, in file order. Duplicates and ordering are the caller's to
        /// resolve — a union merge produces both.
        public let entries: [RunIndexEntry]
        /// Lines that could not be used: torn by a crash mid-append, damaged, or written by a
        /// newer schema. Their runs are simply unindexed.
        public let skippedLines: Int
    }

    /// Encodes one index line for a run, newline-terminated.
    ///
    /// - Parameters:
    ///   - run: The run as recorded, diagnostics included; they are counted and dropped.
    ///   - file: The run file relative to the project directory.
    ///   - bytes: The run file's size.
    /// - Returns: One line of compact JSON ending in `\n`.
    public static func line(for run: CheckResultMetadata, file: String, bytes: Int) throws -> Data {
        try line(for: RunIndexEntry(file: file, bytes: bytes, run: run))
    }

    /// Encodes one entry as a newline-terminated line.
    static func line(for entry: RunIndexEntry) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted so that the same run always produces the same bytes — a rebuilt index can be
        // compared with a written one — and one line, so that a line is a record.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Reads an index file. A file that does not exist is an empty index.
    ///
    /// Never throws: the index is an optimisation, and a reader that cannot use it falls back
    /// to the run files. What could not be used is counted in ``Contents/skippedLines``.
    public static func read(at url: URL) -> Contents {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch CocoaError.fileReadNoSuchFile {
            logger.debug("No run index at \(url.path, privacy: .public); its project's runs will be read from their files")
            return Contents(entries: [], skippedLines: 0)
        } catch {
            logger.warning("Run index at \(url.path, privacy: .public) could not be read; its runs will be read from their files: \(error.localizedDescription, privacy: .public)")
            return Contents(entries: [], skippedLines: 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [RunIndexEntry] = []
        var skipped = 0
        for line in data.split(separator: UInt8(ascii: "\n")) {
            do {
                entries.append(try decoder.decode(RunIndexEntry.self, from: line))
            } catch {
                skipped += 1
                logger.debug("Skipping an unusable run-index line in \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if skipped > 0 {
            logger.notice("Run index at \(url.path, privacy: .public) has \(skipped, privacy: .public) unusable line(s); those runs will be read from their files")
        }
        return Contents(entries: entries, skippedLines: skipped)
    }

    /// Appends one line to an index file, creating the file if needed.
    ///
    /// The descriptor is opened `O_APPEND`, so the kernel positions and writes each `write(2)`
    /// as one step: two gate processes finishing at once each land a whole line, in some order.
    /// Seeking to the end and then writing would not give that.
    static func append(_ line: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw IJSError.telemetryWriteFailed(
                reason: "Cannot open run index \(url.path) for appending (errno \(errno))")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: line)
            try handle.close()
        } catch {
            throw IJSError.telemetryWriteFailed(
                reason: "Cannot append to run index \(url.path): \(error.localizedDescription)")
        }
    }
}
