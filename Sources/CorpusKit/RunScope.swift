import Foundation

/// Which checkers a gate run covered (Phase 0.1).
///
/// Subset runs (`--check <subset>`) are real evidence about the checkers
/// that ran, but a green subset must never count as a green gate — readers
/// filter on this scope when computing pass rates.
public enum RunScope: Sendable, Equatable {
    /// The standard full gate.
    case full
    /// A partial run covering only the named checkers.
    case subset(checkers: [String])
}

extension RunScope: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, checkers
    }

    private enum Kind: String, Codable {
        case full, subset
    }

    /// Decodes a scope from its tagged representation.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .full:
            self = .full
        case .subset:
            self = .subset(checkers: try container.decodeIfPresent([String].self, forKey: .checkers) ?? [])
        }
    }

    /// Encodes the scope as `{type, checkers?}`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .full:
            try container.encode(Kind.full, forKey: .type)
        case .subset(let checkers):
            try container.encode(Kind.subset, forKey: .type)
            try container.encode(checkers, forKey: .checkers)
        }
    }
}
