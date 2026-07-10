import Foundation

/// The second-writer tripwire (quality-gate Phase 2 §4b).
///
/// Counts the distinct *persons* who wrote a project's telemetry within a
/// rolling window. Two or more persons is the personal→professional
/// transition, detected by the system rather than remembered by a human:
/// the gate and the dashboard surface ``standingWarning`` until Phase 3's
/// trust controls exist. Warning-only by design — the tripwire never blocks.
///
/// Machines (``machines``) are counted and surfaced for write-coordination
/// context but never trip alone: the owner running two Macs is normal solo
/// operation, not a transition.
public struct WriterCensus: Sendable, Equatable {
    /// Rolling window the census considers, in days.
    public static let defaultWindowDays = 30

    /// Distinct persons who wrote within the window, sorted. A person is the
    /// provider-verified CI actor when present, else the asserted
    /// `decisionOwner` — so a CI actor matching the local owner is one
    /// person, not two.
    public let persons: [String]

    /// Distinct writer-identity keys (person + machine granularity), sorted.
    public let machines: [String]

    /// Whether a second distinct person appeared within the window.
    public var tripped: Bool {
        persons.count >= 2
    }

    /// The standing warning for gate output and the dashboard, or nil while
    /// the project remains single-writer.
    public var standingWarning: String? {
        guard tripped else { return nil }
        return """
        ⚠ multi-writer activity detected without trust service: writers \
        [\(persons.joined(separator: ", "))] within \(Self.defaultWindowDays) days. \
        Phase 3 controls (verified identity, review semantics, write \
        coordination, read governance) are now required.
        """
    }

    /// Runs the census over a project's metadata.
    ///
    /// - Parameters:
    ///   - metadata: The project's telemetry records (any order).
    ///   - windowDays: Rolling window length; defaults to
    ///     ``defaultWindowDays``.
    ///   - now: The census time (injectable for determinism).
    /// - Returns: The census; ``tripped`` is true at two or more persons.
    public static func census(
        of metadata: [CheckResultMetadata],
        windowDays: Int = WriterCensus.defaultWindowDays,
        now: Date
    ) -> WriterCensus {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var persons: Set<String> = []
        var machines: Set<String> = []
        for record in metadata where record.timestamp >= cutoff && record.timestamp <= now {
            persons.insert(record.ciIdentity?.actor ?? record.decisionOwner)
            machines.insert(record.writerIdentity)
        }
        return WriterCensus(persons: persons.sorted(), machines: machines.sorted())
    }
}
