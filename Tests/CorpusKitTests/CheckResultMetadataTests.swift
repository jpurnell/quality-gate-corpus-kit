import Testing
import Foundation
@testable import CorpusKit
import QualityGateTypes

@Suite("EthicalFlag")
struct EthicalFlagTests {

    @Test("All five cases exist with correct raw values")
    func rawValues() {
        #expect(EthicalFlag.unauthorizedDataCollection.rawValue == "unauthorizedDataCollection")
        #expect(EthicalFlag.manipulativeUX.rawValue == "manipulativeUX")
        #expect(EthicalFlag.missingConsentGuard.rawValue == "missingConsentGuard")
        #expect(EthicalFlag.automatedDecisionRequiringHumanReview.rawValue == "automatedDecisionRequiringHumanReview")
        #expect(EthicalFlag.surveillanceFeature.rawValue == "surveillanceFeature")
    }

    @Test("Codable round-trip for each case")
    func codableRoundTrip() throws {
        let allCases: [EthicalFlag] = [
            .unauthorizedDataCollection, .manipulativeUX, .missingConsentGuard,
            .automatedDecisionRequiringHumanReview, .surveillanceFeature,
        ]
        for flag in allCases {
            let data = try JSONEncoder().encode(flag)
            let decoded = try JSONDecoder().decode(EthicalFlag.self, from: data)
            #expect(decoded == flag)
        }
    }
}

@Suite("Environment")
struct EnvironmentTests {

    @Test("Both cases with raw string values")
    func rawValues() {
        #expect(Environment.local.rawValue == "local")
        #expect(Environment.ci.rawValue == "ci")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for env in [Environment.local, .ci] {
            let data = try JSONEncoder().encode(env)
            let decoded = try JSONDecoder().decode(Environment.self, from: data)
            #expect(decoded == env)
        }
    }
}

@Suite("OverrideRecord")
struct OverrideRecordTests {

    static let sampleDiagnosticOverride = DiagnosticOverride(
        ruleId: "force-unwrap",
        justification: "SAFETY: Necessary for legacy C-API compatibility",
        filePath: "Sources/Interop/Bridge.swift",
        lineNumber: 42
    )

    static let sample = OverrideRecord(
        diagnosticOverride: sampleDiagnosticOverride,
        author: "j_doe_senior_dev",
        riskTier: .safety,
        authorityLevel: .decisionOwner
    )

    @Test("Golden path: all fields populated")
    func goldenPath() {
        let record = Self.sample
        #expect(record.diagnosticOverride.ruleId == "force-unwrap")
        #expect(record.diagnosticOverride.justification.contains("C-API"))
        #expect(record.author == "j_doe_senior_dev")
        #expect(record.riskTier == .safety)
        #expect(record.authorityLevel == .decisionOwner)
    }

    @Test("Codable round-trip with camelCase keys")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let decoded = try JSONDecoder().decode(OverrideRecord.self, from: data)
        #expect(decoded == Self.sample)

        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"diagnosticOverride\""))
        #expect(json.contains("\"ruleId\""))
        #expect(json.contains("\"riskTier\""))
        #expect(json.contains("\"authorityLevel\""))
    }
}

@Suite("CheckResult (shared type integration)")
struct CheckResultIntegrationTests {

    static let sampleDiagnostic = Diagnostic(
        severity: .error,
        message: "Division by zero protection missing",
        filePath: "Sources/Math/Division.swift",
        lineNumber: 42,
        ruleId: "safety.division-by-zero",
        suggestedFix: "Add zero check guard"
    )

    static let sample = CheckResult(
        checkerId: "SafetyAuditor",
        status: .failed,
        diagnostics: [sampleDiagnostic],
        duration: .seconds(2)
    )

    @Test("Shared CheckResult type integrates with IJS")
    func properties() {
        #expect(Self.sample.checkerId == "SafetyAuditor")
        #expect(Self.sample.status == .failed)
        #expect(Self.sample.diagnostics.count == 1)
        #expect(Self.sample.diagnostics[0].filePath == "Sources/Math/Division.swift")
        #expect(Self.sample.diagnostics[0].isFixable == true)
    }

    @Test("Codable round-trip with camelCase checkerId")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"checkerId\""))
        #expect(json.contains("\"filePath\""))
        #expect(json.contains("\"lineNumber\""))

        let decoded = try JSONDecoder().decode(CheckResult.self, from: data)
        #expect(decoded == Self.sample)
    }
}

@Suite("CheckResultMetadata")
struct CheckResultMetadataTests {

    static func makeSample(
        ethicalFlags: [EthicalFlag] = [],
        overrides: [OverrideRecord] = [],
        consistencyScore: Double? = nil
    ) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "BusinessMath-Lib",
            timestamp: Date(timeIntervalSince1970: 1_777_536_311),
            environment: .ci,
            decisionOwner: "j_doe_senior_dev",
            results: [CheckResultIntegrationTests.sample],
            overrides: overrides,
            riskTier: .safety,
            ethicalFlags: ethicalFlags,
            consistencyScore: consistencyScore
        )
    }

    @Test("Golden path: full metadata with results and overrides")
    func goldenPath() {
        let meta = Self.makeSample(
            overrides: [OverrideRecordTests.sample],
            consistencyScore: 0.85
        )
        #expect(meta.projectID == "BusinessMath-Lib")
        #expect(meta.environment == .ci)
        #expect(meta.decisionOwner == "j_doe_senior_dev")
        #expect(meta.results.count == 1)
        #expect(meta.overrides.count == 1)
        #expect(meta.riskTier == .safety)
        #expect(abs((meta.consistencyScore ?? 0) - 0.85) < 1e-6)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let meta = Self.makeSample(
            ethicalFlags: [.manipulativeUX],
            overrides: [OverrideRecordTests.sample],
            consistencyScore: 0.92
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(meta)
        let decoded = try decoder.decode(CheckResultMetadata.self, from: data)
        #expect(decoded == meta)
    }

    @Test("camelCase JSON keys match MCP schema")
    func camelCaseKeys() throws {
        let meta = Self.makeSample(consistencyScore: 0.5)
        let data = try JSONEncoder().encode(meta)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"projectID\""))
        #expect(json.contains("\"decisionOwner\""))
        #expect(json.contains("\"riskTier\""))
        #expect(json.contains("\"ethicalFlags\""))
        #expect(json.contains("\"consistencyScore\""))
    }

    @Test("Empty overrides array")
    func emptyOverrides() throws {
        let meta = Self.makeSample(overrides: [])
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(CheckResultMetadata.self, from: data)
        #expect(decoded.overrides.isEmpty)
    }

    @Test("Empty ethical flags array")
    func emptyEthicalFlags() throws {
        let meta = Self.makeSample(ethicalFlags: [])
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(CheckResultMetadata.self, from: data)
        #expect(decoded.ethicalFlags.isEmpty)
    }

    @Test("consistencyScore nil encodes correctly")
    func nilConsistencyScore() throws {
        let meta = Self.makeSample(consistencyScore: nil)
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(CheckResultMetadata.self, from: data)
        #expect(decoded.consistencyScore == nil)
    }

    @Test("consistencyScore populated")
    func populatedConsistencyScore() throws {
        let meta = Self.makeSample(consistencyScore: 0.75)
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(CheckResultMetadata.self, from: data)
        #expect(abs((decoded.consistencyScore ?? 0) - 0.75) < 1e-6)
    }

    @Test("Multiple results with multiple diagnostics")
    func multipleResults() throws {
        let result2 = CheckResult(
            checkerId: "ConcurrencyAuditor",
            status: .failed,
            diagnostics: [
                Diagnostic(severity: .error, message: "msg1", filePath: "A.swift", lineNumber: 1, ruleId: "concurrency.1"),
                Diagnostic(severity: .warning, message: "msg2", filePath: "B.swift", lineNumber: 2, ruleId: "concurrency.2", suggestedFix: "Fix"),
            ],
            duration: .seconds(1)
        )
        let meta = CheckResultMetadata(
            projectID: "Test",
            timestamp: Date(timeIntervalSince1970: 0),
            environment: .local,
            decisionOwner: "tester",
            results: [CheckResultIntegrationTests.sample, result2],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil
        )
        #expect(meta.results.count == 2)
        #expect(meta.results[1].diagnostics.count == 2)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let decoded = try decoder.decode(CheckResultMetadata.self, from: data)
        #expect(decoded.results.count == 2)
    }

    @Test("Date encodes as ISO 8601")
    func dateEncoding() throws {
        let meta = Self.makeSample()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("2026-"))
    }

    @Test("Old JSON lacking commitSHA decodes with commitSHA == nil")
    func backwardCompatibleCommitSHA() throws {
        // Simulate legacy metadata JSON written before commitSHA existed by
        // encoding a real value (which HAS a commitSHA) and stripping the key.
        let meta = CheckResultMetadata(
            projectID: "BusinessMath-Lib",
            timestamp: Date(timeIntervalSince1970: 1_777_536_311),
            environment: .ci,
            decisionOwner: "j_doe_senior_dev",
            results: [CheckResultIntegrationTests.sample],
            overrides: [],
            riskTier: .safety,
            ethicalFlags: [],
            consistencyScore: 0.5,
            complianceCount: 0,
            commitSHA: "should-be-stripped"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "commitSHA")
        #expect(object["commitSHA"] == nil)
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CheckResultMetadata.self, from: legacyData)
        #expect(decoded.commitSHA == nil)
        #expect(decoded.projectID == "BusinessMath-Lib")
    }

    @Test("Round-trip preserves a set commitSHA")
    func commitSHARoundTrip() throws {
        let meta = CheckResultMetadata(
            projectID: "Test",
            timestamp: Date(timeIntervalSince1970: 0),
            environment: .local,
            decisionOwner: "tester",
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil,
            complianceCount: 0,
            commitSHA: "abc123def456"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"commitSHA\""))
        let decoded = try decoder.decode(CheckResultMetadata.self, from: data)
        #expect(decoded.commitSHA == "abc123def456")
        #expect(decoded == meta)
    }
}

/// Phase 1 (quality-gate overlay model) — identity kind.
///
/// Foreign runs record telemetry under the upstream identity but must be
/// distinguishable from the project's own runs, so dashboards can group
/// them separately and gate statistics stay honest. A defaulted field, so
/// per the 0.5 bump rules this is NOT a schema bump: pre-Phase-1 artifacts
/// decode as `.resident`.
@Suite("CheckResultMetadata identityKind")
struct IdentityKindTests {

    private func makeMeta(identityKind: IdentityKind) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "twostraws__ignite",
            timestamp: Date(timeIntervalSince1970: 1_777_536_311),
            environment: .local,
            decisionOwner: "contributor",
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil,
            identityKind: identityKind
        )
    }

    @Test("raw values are stable")
    func rawValues() {
        #expect(IdentityKind.resident.rawValue == "resident")
        #expect(IdentityKind.foreign.rawValue == "foreign")
    }

    @Test("foreign round-trips and appears in the encoded JSON")
    func foreignRoundTrip() throws {
        let meta = makeMeta(identityKind: .foreign)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"identityKind\""))
        #expect(json.contains("\"foreign\""))
        let decoded = try decoder.decode(CheckResultMetadata.self, from: data)
        #expect(decoded.identityKind == .foreign)
        #expect(decoded == meta)
    }

    @Test("omitting the parameter records a resident run")
    func defaultsToResident() {
        let meta = CheckResultMetadata(
            projectID: "Test",
            timestamp: Date(timeIntervalSince1970: 0),
            environment: .local,
            decisionOwner: "tester",
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil
        )
        #expect(meta.identityKind == .resident)
    }

    @Test("pre-Phase-1 artifacts without the field decode as resident")
    func legacyDecodesAsResident() throws {
        let meta = makeMeta(identityKind: .resident)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(
            with: encoder.encode(meta)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "identityKind")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CheckResultMetadata.self, from: stripped)
        #expect(decoded.identityKind == .resident)
    }

    @Test("identityKind does not bump the schema version (defaulted field rule)")
    func noSchemaBump() {
        #expect(CheckResultMetadata.currentSchemaVersion == 2)
    }
}

/// Phase 2 (CI parity) — verified CI identity + machine attribution.
///
/// `CIIdentity` is the first identity in the ecosystem verified by an
/// external system (the CI provider) rather than asserted. `host` gives
/// asserted local runs a machine attribution so the second-writer tripwire
/// can distinguish "same person, two Macs" from "two people". Both are
/// defaulted fields — per the 0.5 bump rules, NOT a schema bump.
@Suite("CheckResultMetadata CIIdentity")
struct CIIdentityMetadataTests {

    private static let sample = CIIdentity(
        provider: "github-actions",
        actor: "jpurnell",
        workflowRunID: "9876543210",
        commit: "abc123def456",
        repository: "jpurnell/quality-gate-swift")

    private func makeMeta(ciIdentity: CIIdentity?, host: String? = nil) -> CheckResultMetadata {
        CheckResultMetadata(
            projectID: "jpurnell__quality-gate-swift",
            timestamp: Date(timeIntervalSince1970: 1_777_536_311),
            environment: ciIdentity == nil ? .local : .ci,
            decisionOwner: "jpurnell",
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil,
            ciIdentity: ciIdentity,
            host: host)
    }

    @Test("CIIdentity round-trips with every field intact")
    func ciIdentityRoundTrip() throws {
        let meta = makeMeta(ciIdentity: Self.sample)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"github-actions\""))
        #expect(json.contains("\"9876543210\""))
        let decoded = try decoder.decode(CheckResultMetadata.self, from: data)
        #expect(decoded.ciIdentity == Self.sample)
        #expect(decoded == meta)
    }

    @Test("host attribution round-trips")
    func hostRoundTrip() throws {
        let meta = makeMeta(ciIdentity: nil, host: "studio.local")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CheckResultMetadata.self, from: encoder.encode(meta))
        #expect(decoded.host == "studio.local")
    }

    @Test("omitting both records an asserted, unattributed run (legacy shape)")
    func defaultsToNil() {
        let meta = CheckResultMetadata(
            projectID: "Test",
            timestamp: Date(timeIntervalSince1970: 0),
            environment: .local,
            decisionOwner: "tester",
            results: [],
            overrides: [],
            riskTier: .operational,
            ethicalFlags: [],
            consistencyScore: nil)
        #expect(meta.ciIdentity == nil)
        #expect(meta.host == nil)
    }

    @Test("pre-Phase-2 artifacts without the fields decode with nils")
    func legacyDecodesAsNil() throws {
        let meta = makeMeta(ciIdentity: Self.sample, host: "studio.local")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(
            with: encoder.encode(meta)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "ciIdentity")
        object.removeValue(forKey: "host")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CheckResultMetadata.self, from: stripped)
        #expect(decoded.ciIdentity == nil)
        #expect(decoded.host == nil)
    }

    @Test("ciIdentity does not bump the schema version (defaulted field rule)")
    func noSchemaBump() {
        #expect(CheckResultMetadata.currentSchemaVersion == 2)
    }

    @Test("writerIdentity: verified CI actor beats asserted owner+host")
    func writerIdentityPrecedence() {
        let ci = makeMeta(ciIdentity: Self.sample, host: "runner-1.local")
        #expect(ci.writerIdentity == "ci:github-actions:jpurnell")

        let local = makeMeta(ciIdentity: nil, host: "studio.local")
        #expect(local.writerIdentity == "asserted:jpurnell@studio.local")

        let legacy = makeMeta(ciIdentity: nil, host: nil)
        #expect(legacy.writerIdentity == "asserted:jpurnell")
    }
}
