# Drift ledger — reconciliations between the two prior corpus implementations

Per the Phase 0.3 proposal: every behavioral difference found while unifying
the quality-gate-swift and org-judgement-system corpus code is recorded here
with its reconciliation decision.

| # | Drift | Decision |
|---|---|---|
| 1 | `IJSError`: org-judgement-system had `narrativeGenerationFailed` and `corpusSyncFailed` cases; quality-gate-swift's copy lacked both (CorpusManager could not even compile against it) | Superset: both cases adopted into CorpusKit's `IJSError` |
| 2 | `CorpusPath`: org had `narrativePath(weekLabel:)` and `manifestPath`; qg-swift's copy had orientation/work-log/skip paths instead | Superset: org's two paths adopted |
| 3 | Manifest model: org used `ProjectEntry` + Yams-Codable serialization (cannot parse the real corpus's quoted ISO dates); qg-swift used `CorpusManifestEntry` + hand-rolled YAML (the format actually on disk, with `tierOverride`/`groups`/`aliases`) | qg-swift model wins; `ProjectEntry` kept as a typealias; org's `setLifecycle`/`projectIDs(matching:)` adopted (setLifecycle preserves an existing `tierOverride`); `TelemetryWriter.loadManifest`/`writeManifest` adopted but delegate to `CorpusManifest.load`/`save` |
| 4 | `ProjectHealthSummary` + org's run-rate `ProjectTrajectory` existed only in org; the name `ProjectTrajectory` was already taken in CorpusKit by the regression-based type | Adopted; org's nested type renamed `RunRateTrajectory` (serialized shape unchanged) |
| 5 | `PulseStatistics`: org had `projectHealth`; qg-swift had riskTier/checker distributions, snapshots, complexity trends, weighted scores, gated anomalies — and its decoder *required* six fields org-written pulses lack | Superset: `projectHealth` adopted (optional); the six collection fields decode tolerantly (absent → empty) per the 0.5 tolerance policy; init gained defaults so both repos' call sites compile |
| 6 | `InstitutionalPulse`: org had `sunsetProjects` (required) + `proposalFirstSeen`; qg-swift had `label`/tiers/trajectories/group snapshots/current snapshot | Superset: both org fields adopted (`sunsetProjects` decodes tolerantly, absent → `[]`), inserted after `generatedAt` to keep org call-site argument order |
| 7 | `TelemetryConfiguration`: org had `remoteURL` for corpus git sync | Adopted, including `ijs.remoteURL` YAML parsing |
| 8 | `TelemetryWriter`: org had `readLatestMetadata`, `discoverProjects(in:)` | Adopted verbatim |
| 9 | `EthicalFlag`/`FiveStepStage`: org's were `CaseIterable` | Conformances adopted. `TrendAnalysis.compute(metric:values:)` NOT adopted — it depends on BusinessMath; it stays in org-judgement-system as an extension on CorpusKit's `TrendAnalysis` |
| 10 | `CorpusManagerTests` (the only coverage of `CorpusManager`) flipped fail→pass on identical code — parallel with the whole fleet, unchecked git exit codes, global git identity, unborn-branch remote | Moved here hardened: `.serialized`, checked setup commands, repo-local identity, seeded remotes. Verified stable across repeated runs |

## #10 — Subprocess spawning unified behind ProcessRunner (2026-08-25)

Both prior implementations spawned `git` ad hoc, and each had drifted into a
different unsafe shape: `CorpusManager` read its pipes before waiting (correct
order, no timeout), `ProjectIdentity` attached a stderr pipe it never drained
(deadlock on chatty stderr), and the test helpers waited before reading
(deadlock on any output at all). The gate's `bounded-io` checker made the
divergence visible by requiring one audited kernel.

Resolution: all sixteen call sites route through `ProcessRunner`. The kernel is
declared to the gate via `boundedIO.kernelPath`, so the containment is enforced
rather than merely documented — a new ad-hoc `Process()` anywhere else in the
package now fails the gate.

Worth recording: bounding the wait was not sufficient. Killing a child does not
close pipe write ends its own children inherited, so reading to EOF could still
outlive the bounded process. The drain carries its own deadline and the result
reports `outputTruncated` when it fires.
