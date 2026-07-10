import Foundation
import QualityGateTypes

/// Ethical risk signals detected by the quality gate's automated auditors.
public enum EthicalFlag: String, Sendable, Codable, CaseIterable {
    /// Data collection without meaningful user consent.
    case unauthorizedDataCollection // LIVE: domain taxonomy for ethical audit findings
    /// UI patterns designed to trick users into unintended actions.
    case manipulativeUX // LIVE: domain taxonomy for ethical audit findings
    /// Data transmission code missing a required consent guard.
    case missingConsentGuard // LIVE: domain taxonomy for ethical audit findings
    /// Automated decision-making that legally requires human-in-the-loop.
    case automatedDecisionRequiringHumanReview // LIVE: domain taxonomy for ethical audit findings
    /// Features that track or monitor users without disclosure.
    case surveillanceFeature // LIVE: domain taxonomy for ethical audit findings
}

/// Where the quality gate was executed.
public enum Environment: String, Sendable, Codable {
    /// Developer's local machine.
    case local
    /// Continuous integration pipeline.
    case ci
}

/// Whose repository the gate ran against (Phase 1, overlay model).
///
/// Foreign runs record under the upstream identity but stay distinguishable
/// from the project's own runs, so dashboards group them separately and gate
/// statistics stay honest.
public enum IdentityKind: String, Sendable, Codable {
    /// The gate ran in the project's own checkout — today's normal run.
    case resident
    /// A contributor analyzed a repository they don't control; contributor
    /// configuration, overlay-redirected writes.
    case foreign
}

/// An override enriched with IJS judgment context.
///
/// Wraps a `DiagnosticOverride` from the quality gate with institutional
/// metadata: who authorized it, at what risk tier, and with what authority.
public struct OverrideRecord: Sendable, Codable, Equatable {
    /// The underlying diagnostic override from the quality gate.
    public let diagnosticOverride: DiagnosticOverride
    /// The practitioner or stakeholder who authorized the override.
    public let author: String
    /// The risk tier of the overridden rule.
    public let riskTier: RiskTier
    /// The authority level of the person approving the override.
    public let authorityLevel: AuthorityLevel

    /// Creates a new override record.
    /// - Parameters:
    ///   - diagnosticOverride: The underlying diagnostic override from the quality gate.
    ///   - author: The practitioner who authorized the override.
    ///   - riskTier: The risk tier of the overridden rule.
    ///   - authorityLevel: The authority level of the approver.
    public init(
        diagnosticOverride: DiagnosticOverride,
        author: String,
        riskTier: RiskTier,
        authorityLevel: AuthorityLevel
    ) {
        self.diagnosticOverride = diagnosticOverride
        self.author = author
        self.riskTier = riskTier
        self.authorityLevel = authorityLevel
    }
}

/// Extended quality gate result with judgment system fields.
///
/// Bridges the gap between technical pass/fail status and human discernment
/// by capturing decision ownership, override rationale, ethical flags, and
/// institutional consistency scoring alongside standard checker results.
public struct CheckResultMetadata: VersionedCorpusArtifact, Equatable {
    /// The corpus schema version this build writes.
    /// v2 (Phase 0.1): added `runScope`; v1 artifacts decode as full runs.
    public static let currentSchemaVersion = 2

    /// Repository or project identifier.
    public let projectID: String
    /// When the quality gate was executed.
    public let timestamp: Date
    /// Whether the gate ran locally or in CI.
    public let environment: Environment
    /// The stakeholder with authority to ship this artifact, per the DRM.
    public let decisionOwner: String
    /// Results from each quality gate checker.
    public let results: [CheckResult]
    /// Documented overrides of quality gate checks, enriched with judgment context.
    public let overrides: [OverrideRecord]
    /// The overall risk classification for this gate run.
    public let riskTier: RiskTier
    /// Ethical risk signals detected by automated auditors.
    public let ethicalFlags: [EthicalFlag]
    /// How consistent this implementation is with institutional lessons. Nil if not yet scored.
    public let consistencyScore: Double?
    /// Total compliance annotations verified across all checkers (not overrides).
    public let complianceCount: Int
    /// Git commit SHA the gate ran against; the join key linking metrics to work-events. Nil if not a git repo.
    public let commitSHA: String?

    /// The corpus schema version this artifact was written with.
    public let schemaVersion: Int

    /// Which checkers this run covered. Pre-v2 artifacts decode as ``RunScope/full``.
    public let runScope: RunScope

    /// Build identity of the gate binary that produced this run, when known.
    public let gateBuild: GateBuild?

    /// Whose repository the gate ran against. Pre-Phase-1 artifacts decode
    /// as ``IdentityKind/resident`` (defaulted field — not a schema bump).
    public let identityKind: IdentityKind

    /// Provider-verified identity when the run happened in CI (Phase 2).
    /// Nil for local runs and pre-Phase-2 artifacts (defaulted — not a bump).
    public let ciIdentity: CIIdentity?

    /// Machine attribution for asserted (local) runs, so the second-writer
    /// tripwire can tell "same person, two Macs" from "two people".
    /// Nil on pre-Phase-2 artifacts (defaulted — not a bump).
    public let host: String?

    /// The writer-identity key the second-writer tripwire clusters on:
    /// `ci:<provider>:<actor>` when provider-verified, else
    /// `asserted:<owner>@<host>` (or `asserted:<owner>` for legacy artifacts
    /// with no host attribution).
    public var writerIdentity: String {
        if let ci = ciIdentity {
            return "ci:\(ci.provider):\(ci.actor)"
        }
        if let host {
            return "asserted:\(decisionOwner)@\(host)"
        }
        return "asserted:\(decisionOwner)"
    }

    /// Creates a new check result metadata record.
    /// - Parameters:
    ///   - projectID: Repository or project identifier.
    ///   - timestamp: When the gate was executed.
    ///   - environment: Local or CI.
    ///   - decisionOwner: Stakeholder with shipping authority.
    ///   - results: Results from each checker.
    ///   - overrides: Documented overrides with judgment context.
    ///   - riskTier: Overall risk classification.
    ///   - ethicalFlags: Ethical risk signals.
    ///   - consistencyScore: Institutional consistency score, if available.
    ///   - complianceCount: Total compliance annotations verified.
    ///   - commitSHA: Git commit SHA the gate ran against; the join key linking metrics to work-events. Nil if not a git repo.
    ///   - runScope: Which checkers this run covered. Defaults to a full gate.
    ///   - gateBuild: Build identity of the gate binary, when known.
    ///   - identityKind: Whose repository the gate ran against. Defaults to resident.
    ///   - ciIdentity: Provider-verified identity for CI runs. Defaults to nil (asserted run).
    ///   - host: Machine attribution for asserted runs. Defaults to nil.
    public init(
        projectID: String,
        timestamp: Date,
        environment: Environment,
        decisionOwner: String,
        results: [CheckResult],
        overrides: [OverrideRecord],
        riskTier: RiskTier,
        ethicalFlags: [EthicalFlag],
        consistencyScore: Double?,
        complianceCount: Int = 0,
        commitSHA: String? = nil,
        runScope: RunScope = .full,
        gateBuild: GateBuild? = nil,
        identityKind: IdentityKind = .resident,
        ciIdentity: CIIdentity? = nil,
        host: String? = nil
    ) {
        self.projectID = projectID
        self.timestamp = timestamp
        self.environment = environment
        self.decisionOwner = decisionOwner
        self.results = results
        self.overrides = overrides
        self.riskTier = riskTier
        self.ethicalFlags = ethicalFlags
        self.consistencyScore = consistencyScore
        self.complianceCount = complianceCount
        self.commitSHA = commitSHA
        self.schemaVersion = Self.currentSchemaVersion
        self.runScope = runScope
        self.gateBuild = gateBuild
        self.identityKind = identityKind
        self.ciIdentity = ciIdentity
        self.host = host
    }

    /// Decodes a ``CheckResultMetadata`` from an external representation, defaulting `complianceCount` to `0` and `commitSHA` to `nil` when absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        projectID = try container.decode(String.self, forKey: .projectID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        environment = try container.decode(Environment.self, forKey: .environment)
        decisionOwner = try container.decode(String.self, forKey: .decisionOwner)
        results = try container.decode([CheckResult].self, forKey: .results)
        overrides = try container.decode([OverrideRecord].self, forKey: .overrides)
        riskTier = try container.decode(RiskTier.self, forKey: .riskTier)
        ethicalFlags = try container.decode([EthicalFlag].self, forKey: .ethicalFlags)
        consistencyScore = try container.decodeIfPresent(Double.self, forKey: .consistencyScore)
        complianceCount = try container.decodeIfPresent(Int.self, forKey: .complianceCount) ?? 0
        commitSHA = try container.decodeIfPresent(String.self, forKey: .commitSHA)
        runScope = try container.decodeIfPresent(RunScope.self, forKey: .runScope) ?? .full
        gateBuild = try container.decodeIfPresent(GateBuild.self, forKey: .gateBuild)
        identityKind = try container.decodeIfPresent(IdentityKind.self, forKey: .identityKind) ?? .resident
        ciIdentity = try container.decodeIfPresent(CIIdentity.self, forKey: .ciIdentity)
        host = try container.decodeIfPresent(String.self, forKey: .host)
    }
}
