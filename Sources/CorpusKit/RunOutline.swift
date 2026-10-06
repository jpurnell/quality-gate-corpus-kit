import Foundation
import QualityGateTypes

/// A run's metadata, decoded without the diagnostics its checkers recorded.
///
/// Diagnostics are nearly all of a run file — a duplication sweep alone can record fifteen
/// thousand of them — and almost none of what a history reader needs. Pass rates, trends, the
/// writer census and the baseline burn-down read statuses, scopes and timestamps. Decoding
/// `RunOutline` instead of ``CheckResultMetadata`` gives the same value with every result's
/// `diagnostics` empty, and never materialises the findings: `JSONDecoder` builds a string only
/// when a key is asked for.
///
/// The outline is not a second schema. It decodes through ``CheckResultMetadata``'s own
/// initializer, so a field added there is read here too.
public struct RunOutline: Decodable, Sendable {
    /// The run's metadata. Every result's `diagnostics` is empty; everything else is as recorded.
    public let metadata: CheckResultMetadata

    /// Decodes a run file, skipping each result's diagnostics.
    public init(from decoder: Decoder) throws {
        metadata = try CheckResultMetadata(from: decoder, omittingDiagnostics: true)
    }
}

/// One checker's result with its diagnostics left undecoded.
///
/// `CheckResult` belongs to quality-gate-types and decodes its diagnostics unconditionally, so
/// this mirrors its other five fields, with the same defaults for the two that older runs omit.
struct ResultOutline: Decodable {
    let result: CheckResult

    private enum CodingKeys: String, CodingKey {
        case checkerId, status, overrides, complianceRecords, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = CheckResult(
            checkerId: try container.decode(String.self, forKey: .checkerId),
            status: try container.decode(CheckResult.Status.self, forKey: .status),
            diagnostics: [],
            overrides: try container.decodeIfPresent([DiagnosticOverride].self, forKey: .overrides) ?? [],
            complianceRecords: try container.decodeIfPresent([ComplianceRecord].self, forKey: .complianceRecords) ?? [],
            duration: try container.decode(Duration.self, forKey: .duration)
        )
    }
}
