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

/// How the run's verdict was applied (Phase 4, trial mode).
///
/// Advisory runs are surveys: every finding downgraded to a note, exit 0.
/// They are recorded — the survey is the point — but statistics that mean
/// "the gate was green" must exclude them.
public enum GateMode: String, Sendable, Codable {
    /// Findings gate normally — the default.
    case standard
    /// `--advisory-all`: findings reported, nothing gates, exit 0.
    case advisory
}

/// The decaying baseline's per-run counts (quality-gate Phase 4c §3).
///
/// When a run applied a `.quality-gate-baseline.json` ledger, these counts
/// feed the dashboard's debt burn-down: covered debts should trend to zero,
/// expired debts demand re-verification, and new findings gate immediately.
public struct BaselineSnapshot: Sendable, Codable, Equatable {
    /// Findings covered by unexpired baseline records — the remaining debt.
    public let baselined: Int
    /// Findings whose baseline record has expired — the re-verify queue.
    public let expired: Int
    /// Findings not in the ledger at all — gating now.
    public let newFindings: Int

    /// Creates a baseline snapshot.
    /// - Parameters:
    ///   - baselined: Findings covered by unexpired records.
    ///   - expired: Findings whose records expired.
    ///   - newFindings: Findings outside the ledger.
    public init(baselined: Int, expired: Int, newFindings: Int) {
        self.baselined = baselined
        self.expired = expired
        self.newFindings = newFindings
    }
}

/// How a run that stopped early stopped (quality-gate Change C).
///
/// A default run halts at its first failing checker, and every checker ordered
/// after it never ran. Without this record, a truncated run is indistinguishable
/// from a clean scoped run — zero findings from an unreached checker reads as a
/// pass, which is how one package's false positives stayed invisible for months.
/// Readers computing pass rates or finding counts must treat `unreached`
/// checkers as absent evidence, not as clean results.
public struct TruncationRecord: Sendable, Codable, Equatable {
    /// The failing checker the run stopped at.
    public let stoppedAt: String
    /// Checker ids selected for this run that never executed because of the stop.
    public let unreached: [String]

    /// Creates a truncation record.
    /// - Parameters:
    ///   - stoppedAt: The failing checker the run stopped at.
    ///   - unreached: Selected checkers that never executed.
    public init(stoppedAt: String, unreached: [String]) {
        self.stoppedAt = stoppedAt
        self.unreached = unreached
    }
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

    /// How the run's verdict was applied. Pre-Phase-4 artifacts decode as
    /// ``GateMode/standard`` (defaulted field — not a schema bump).
    public let gateMode: GateMode

    /// The applied baseline ledger's counts, when the run had one (Phase 4c).
    /// Nil for runs without a ledger and pre-4c artifacts (defaulted — not a
    /// schema bump).
    public let baseline: BaselineSnapshot?

    /// How the run stopped early, when it did (Change C). Nil for complete
    /// runs and pre-Change-C artifacts (defaulted — not a schema bump).
    /// A record with this set carries **absent evidence** for every checker
    /// it names: their zero findings mean "never ran", not "clean".
    public let truncation: TruncationRecord?

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
    ///   - gateMode: How the run's verdict was applied (standard or advisory). Defaults to standard.
    ///   - baseline: The applied baseline ledger's per-run counts, when the run had one. Defaults to nil.
    ///   - truncation: How the run stopped early, when it did. Defaults to nil (complete run).
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
        host: String? = nil,
        gateMode: GateMode = .standard,
        baseline: BaselineSnapshot? = nil,
        truncation: TruncationRecord? = nil
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
        self.gateMode = gateMode
        self.baseline = baseline
        self.truncation = truncation
    }

    /// Decodes a ``CheckResultMetadata`` from an external representation, defaulting `complianceCount` to `0` and `commitSHA` to `nil` when absent.
    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, omittingDiagnostics: false)
    }

    /// The one decoder, shared with ``RunOutline`` so the two readings of a run file cannot
    /// drift: every field is decoded the same way, and only `results` differs.
    ///
    /// - Parameters:
    ///   - decoder: The decoder to read from.
    ///   - omittingDiagnostics: When true, each result is decoded without its diagnostics.
    init(from decoder: Decoder, omittingDiagnostics: Bool) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        projectID = try container.decode(String.self, forKey: .projectID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        environment = try container.decode(Environment.self, forKey: .environment)
        decisionOwner = try container.decode(String.self, forKey: .decisionOwner)
        if omittingDiagnostics {
            results = try container.decode([ResultOutline].self, forKey: .results).map(\.result)
        } else {
            results = try container.decode([CheckResult].self, forKey: .results)
        }
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
        gateMode = try container.decodeIfPresent(GateMode.self, forKey: .gateMode) ?? .standard
        baseline = try container.decodeIfPresent(BaselineSnapshot.self, forKey: .baseline)
        truncation = try container.decodeIfPresent(TruncationRecord.self, forKey: .truncation)
    }
}
