# 2026-10-06 — A consistency score that can refuse

Branch `fix/gate-clean`, from `origin/main` at 1abee27 (1.22.1). Not merged, not tagged.

## What was asked, and what was already true

The request was to clear two `fallback.clamp-absorbs-nan` warnings in
`Sources/IJSPolicyDiscovery/ConsistencyScorer.swift`. They were already gone: 7b91c67
(1.21.0) guarded the clamp, and `origin/main` was at 0 errors / 0 warnings before this
branch touched anything. The survey that listed them had read the local checkout, which was
on `fix/path-containment` — a branch merged as PR #1 and four releases behind.

What 1.21.0 left was the answer itself. A NaN deduction scored `0.0`, silently; `+∞` scored
`0.0`; and `-∞` still scored `1.0`, which is the original defect with the sign flipped.

## What changed

- `ConsistencyScorer.checkedScore` (both overloads) and
  `PolicyDiscoveryAuditor.checkedAudit` throw `ConsistencyScorer.InvalidDeduction`: a
  `kind` (`notANumber`, `positiveInfinity`, `negativeInfinity`) and the non-finite weights
  by name.
- `ScorerWeights.nonFiniteWeights`.
- `TelemetryConfiguration.load` refuses a non-finite `ijs.scorerWeights` entry.
- `score`/`audit`, which cannot throw: `0.0` for every non-finite deduction, documented,
  logged at `error`. `-∞` moves from `1.0`.

## What did not change

Every score for a finite deduction, bit for bit. `ConsistencyScorerFiniteParityTests` was
committed first (41489e4) and passed against the unmodified scorer.

## Where a NaN can come from

Only the weights — `.quality-gate.yml` (`.nan` and `.inf` are YAML scalars), a caller of
`ScorerWeights.init`, or finite weights that overflow. The scorer reads nothing else from a
finding. Recorded in the CHANGELOG.

## Left for others

- `ConsistencyChecker` (quality-gate-swift) and `QueryConsistencyTool` (ijs-mcp-server)
  call the non-throwing `audit`. Until they adopt `checkedAudit`, a non-finite
  `consistency.scorerWeights` in a gated repository shows as a score of 0.00 and a log
  line, not as a diagnostic. The gate decodes those weights itself
  (`ScorerWeightsConfig`), so the refusal at `TelemetryConfiguration.load` does not cover it.
- `SeverityWeight.swift:66` still draws a `fallback` *note* (a guard that answers `1.0`
  when `totalWeight` is a NaN). A note, not a warning; not touched.
- `org-judgement-system` takes this scorer in place of its copy (`DRIFT.md` #12). It pins
  1.22.1 today; adopting `checkedAudit` there waits for this release's tag.

## Verification

746 tests pass. `quality-gate --check all`: 46 of 46, 0 errors, 0 warnings, consistency 1.00.
No swift-process-kernel dependency: this package's `ProcessRunner` is its own
(`Sources/CorpusKit/ProcessRunner.swift`), so the 1.1.0 `InvalidTimeout` change does not
reach it.
