import Foundation

/// The mandatory artifact generated whenever a practitioner overrides a quality gate check.
///
/// Every override produces a calibration record that captures not just *what* was bypassed
/// but *why* — including root cause analysis, adversarial dissent, and a summary suitable
/// for inclusion in the Institutional Pulse. This ensures overrides become calibration events
/// that improve the organization's collective judgment rather than silent bypasses.
public struct JudgmentCalibration: VersionedCorpusArtifact, Equatable {
    /// The corpus schema version this build writes.
    public static let currentSchemaVersion = 1

    /// The corpus schema version this artifact was written with.
    public let schemaVersion: Int
    /// When the override occurred.
    public let date: Date
    /// The stakeholder who authorized the override, per the DRM.
    public let decisionOwner: String
    /// The developer or AI agent that produced the overridden code.
    public let practitioner: String
    /// The risk tier of the overridden check.
    public let riskTier: RiskTier
    /// Structured analysis separating proximate cause from root cause.
    public let rootCauseAnalysis: RootCauseAnalysis
    /// Mandatory adversarial dissent. AI-generated when no human red team is available.
    public let redTeamDissent: String
    /// Suggested update to quality gate rules or coding guidelines, if any.
    public let proposedPolicyUpdate: String?
    /// Summary for the next Institutional Pulse (2-3 sentences).
    public let pulseContribution: String

    /// Creates a new judgment calibration record.
    /// - Parameters:
    ///   - date: When the override occurred.
    ///   - decisionOwner: Stakeholder who authorized the override.
    ///   - practitioner: Developer or AI agent that produced the code.
    ///   - riskTier: Risk tier of the overridden check.
    ///   - rootCauseAnalysis: Structured proximate/root cause analysis.
    ///   - redTeamDissent: Mandatory adversarial dissent.
    ///   - proposedPolicyUpdate: Suggested rule or guideline change.
    ///   - pulseContribution: Summary for the Institutional Pulse.
    public init(
        date: Date,
        decisionOwner: String,
        practitioner: String,
        riskTier: RiskTier,
        rootCauseAnalysis: RootCauseAnalysis,
        redTeamDissent: String,
        proposedPolicyUpdate: String?,
        pulseContribution: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.date = date
        self.decisionOwner = decisionOwner
        self.practitioner = practitioner
        self.riskTier = riskTier
        self.rootCauseAnalysis = rootCauseAnalysis
        self.redTeamDissent = redTeamDissent
        self.proposedPolicyUpdate = proposedPolicyUpdate
        self.pulseContribution = pulseContribution
    }

    /// Decodes a calibration, treating pre-versioning artifacts as schema v1.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        date = try container.decode(Date.self, forKey: .date)
        decisionOwner = try container.decode(String.self, forKey: .decisionOwner)
        practitioner = try container.decode(String.self, forKey: .practitioner)
        riskTier = try container.decode(RiskTier.self, forKey: .riskTier)
        rootCauseAnalysis = try container.decode(RootCauseAnalysis.self, forKey: .rootCauseAnalysis)
        redTeamDissent = try container.decode(String.self, forKey: .redTeamDissent)
        proposedPolicyUpdate = try container.decodeIfPresent(String.self, forKey: .proposedPolicyUpdate)
        pulseContribution = try container.decode(String.self, forKey: .pulseContribution)
    }
}
