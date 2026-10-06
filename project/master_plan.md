# quality-gate-corpus-kit Master Plan

**Purpose:** The contract this package offers everything that reads or writes the corpus.

> **Provenance:** Written 2026-08-04 from README, `Package.swift`, and the source tree.
> **This is a foundation library, not a product.**

---

## Mission

The **one implementation** of the quality-gate corpus: the shared reader and writer for
telemetry, snapshots, and derived judgment artifacts.

"One implementation" is the entire point. A corpus with two writers acquires two schemas,
and the telemetry series stops being comparable — which destroys the only thing longitudinal
data is for.

## Who depends on this

`quality-gate-swift` (writing telemetry, generating pulses), the corpus service, and the
dashboard. Anything that touches corpus data should route through `CorpusKit` rather than
reading the layout directly.

## The reading layer

Between 2026-09-17 and 2026-09-18 this package stopped being only the *format* and became
the format plus **the shared code that reads it**. Four modules moved here from
`quality-gate-swift` (1.17.0, 1.18.0):

| Module | Role |
|---|---|
| `IJSAggregator` | calibration reports and classification over a run series |
| `IJSPolicyDiscovery` | policy-discovery auditing and the institutional consistency score |
| `IJSDashboardCore` | `CorpusReader`, trends, portfolio and project summaries, daily runs |
| `JudgmentWorkbench` | the findings inbox, acknowledgeable rules, acknowledgment markers |

They belong here by the same argument the package rests on: each is shared by the gate,
`ijs-mcp-server` and `quality-gate-dashboard`, and belongs to none of them, so a copy in
each consumer is a second reader — the thing "one implementation" exists to prevent.

`IJSDashboardCore` is now a misnomer: its one dashboard-specific file left for
`quality-gate-dashboard`. Renaming it touches every import in three packages for no
behavioural gain, so it is recorded here rather than done.

---

## The contract

| Protocol | Role |
|---|---|
| `CorpusTransport` | storage seam — local filesystem, remote service, or test double |
| `VersionedCorpusArtifact` | every artifact declares its schema version |

`VersionedCorpusArtifact` is the load-bearing one. Telemetry accumulates for years; a
reader will meet artifacts written by versions of the tool that no longer exist. Versioning
each artifact is what makes that survivable.

**Domain types** cover baselines and drift (`BaselineSnapshot`, `AnomalyGate`,
`AnomalyDirection`, `AnomalySeverity`), judgment (`Actionability`, `AuthorityLevel`),
complexity (`ComplexityReport`, `ComplexitySnapshot`), and run identity (`CIIdentity`,
`CheckResultMetadata`).

Depends on **`quality-gate-types`** for the shared vocabulary and **`Yams`** for YAML.

## Boundaries

**Inside:** corpus schema, serialization, versioning, transport abstraction, the types
describing a run.

**Outside:** running checkers, deciding verdicts, rendering dashboards. This package knows
how a result is *stored*, never how it is *produced* or *judged*.

**The 1.17.0–1.18.0 absorption bent that line, and it is worth being exact about how.**
"Never how it is judged" was written when the package held only the format. `IJSPolicyDiscovery`
computes the institutional consistency score and `JudgmentWorkbench` turns recorded diagnostics
into acknowledgeable findings — both are readings *derived from* stored results, and neither
runs a checker or decides a verdict. That is the boundary as it actually stands: **deriving**
from the corpus is inside, **producing** or **adjudicating** a result stays outside. If a
future move needs to run an auditor to do its job, it belongs in `quality-gate-swift`; that
test is what kept `JudgmentWorkbench`'s golden re-audit suite there.

## Stability

**Schema changes are the risk, not source compatibility.** A Swift API break is a compile
error someone fixes in an afternoon. A schema change that silently reinterprets existing
artifacts corrupts a longitudinal series retroactively, and nothing errors.

Rules that follow:

- Every artifact carries its schema version. No exceptions, including new types.
- Readers tolerate older versions; writers never rewrite history.
- A field's meaning is fixed once written. Need different semantics? New field.

### Versions in force

There is no single "corpus schema version". Versioning is **per artifact type**, and the
types are deliberately not in lockstep — a bump to one must not force a rewrite of the
other six. As of 2026-08-25:

| Artifact type | Version |
| --- | --- |
| `CheckResultMetadata` | **2** — added `runScope` (Phase 0.1, commit `c759b99`) |
| `ComplexityReport` | 1 |
| `DailySnapshot` | 1 |
| `InstitutionalPulse` | 1 |
| `ModuleOrientationCard` | 1 |
| `JudgmentCalibration` | 1 |
| `SkipRecord` | 1 |

Do not collapse this into one number. A package-wide scalar would be wrong the moment the
next type bumps, and wrong *silently* — which is the failure mode this whole section exists
to prevent.

### Oldest supported version: 1, permanently

Readers accept **v1 forever**, for every type. `CorpusSchema.decode` enforces only an upper
bound (`version <= current` → skip, never half-decode); it has no lower bound, and it should
not acquire one by default.

This is a decision, not an accident of the current implementation. The corpus is an
append-only longitudinal series, not a wire protocol: nothing migrates old artifacts, and
they sit on disk indefinitely. A rolling support window would mean 2026 telemetry silently
stops being readable in 2028 — destroying exactly what this package exists to protect. The
cost stays bounded because of the bump rules above: an optional or defaulted field is not a
bump, so version skew is absorbed by defaults, and real bumps are rare (one to date).

**The one way the floor may move:** an explicit migration that rewrites old artifacts
forward, after which the floor rises to the migrated version. Never a passive deprecation.

### The skew hazard this creates

The policy is asymmetric, so the risk moves to the *newer* side. If `quality-gate-swift`
ships a bump before `org-judgement-system` picks it up, IJS skips those runs rather than
misreading them — correct, but it means a producer upgrade silently thins the consumer's
series until the consumer catches up. `decode` logs each skip and returns `.skippedNewer`,
but nothing inside `CorpusKit` acts on it; handling belongs to the consumers, and both
should surface it rather than discard it. Bump a producer only in step with its readers.

## Current Status

### What's Working

- [x] CorpusKit — schema types, deterministic paths, telemetry I/O, git sync
- [x] IJSAggregator — calibration reports and classification
- [x] IJSPolicyDiscovery — policy-discovery auditing, institutional consistency score
- [x] IJSDashboardCore — `CorpusReader`, trends, portfolio and project summaries
- [x] JudgmentWorkbench — findings inbox, acknowledgeable rules, marker writing

- [x] 64 source files, **81 test files** across five modules (CorpusKit alone: 48 and 56)
      — the best-covered package in this tier, which is appropriate for something whose
      failures are silent and retroactive
- [x] **One audited subprocess kernel.** Every spawn routes through `ProcessRunner`,
      declared to the gate as `boundedIO.kernelPath`. This closed a real deadlock:
      `ProjectIdentity` attached a stderr pipe it never drained, so a `git` call with
      more than ~64 KB of stderr would hang the caller rather than fail it.
- [x] Gate clean at 0 errors / 0 warnings against quality-gate 3.1.2, with the
      institutional consistency score at 1.00 (it had fallen to 0.00).
- [x] **A history read that does not hold the history.** `CorpusReader.loadHistory(for:)`
      (1.21.0) decodes runs without their diagnostics and reads findings only for the
      present state. It exists because a consumer was hurt: the dashboard's `loadAll()`
      peaked at 11.9 GB against a 3.16 GB corpus. `loadRuns` and `loadAll` still load
      everything, and say so.
- [x] **Containment on every corpus read.** The pulse readers were the last ones taking
      a path by interpolation without it; they now resolve and component-check like the
      rest. See *Priorities* for what this class of defect still costs.

**Priorities**

1. **Make the v1 floor real.** *Quality Standards* below has always called for round-trip
   tests against fixed fixtures from older schema versions. There are none on disk: old
   version decode is covered by inline JSON literals in `CorpusSchemaVersionTests`,
   `RunScopeTests`, and `InstitutionalPulseNarrativeSourceTests`, which exercises
   `CheckResultMetadata` v1 but leaves the other six types without a pinned v1 artifact.
   Until each conforming type has a checked-in v1 fixture it round-trips against, "v1
   forever" is an intention rather than a guarantee.
2. **Give `.skippedNewer` a consumer.** It is currently observed only by tests. Whatever
   the consumers do with it, a skipped artifact should reach a human somewhere.
3. Keep the subprocess kernel the only spawn site; the gate now enforces this, so the
   work is to resist adding a second one rather than to detect it.
4. **Absorbed code needs the same audit the format got.** The 2026-09-19 pass found two
   defects the three absorption commits carried in, neither visible from a passing local
   build: `CorpusReader`'s pulse readers interpolated a path with no containment — the one
   reader class the 1.17.0 security fix missed — and eight test files still imported the
   retired `IJSSensor`, compiling only against stale `.build` artifacts that re-exported
   `CorpusKit`. A clean checkout would not have built. Moving a module does not re-run the
   reasoning that hardened its destination; assume the next absorption arrives with the
   same gaps and check for them deliberately.
5. **Run the gate to completion when absorbing.** Both defects above sat behind a `safety`
   failure that stopped the run at checker 3 of 45, so 26 checkers never executed and
   reported nothing — which reads identically to reporting no findings. `--continue-on-failure`
   is the difference between "clean" and "unexamined".

6. **A reader's cost is part of its contract.** Nothing here said what `loadAll()` costs,
   and nothing measured it: the corpus grew to 3.16 GB under a reader that was written when
   it was a few megabytes, and the first report was a machine out of memory. `loadHistory`
   fixes the one consumer that was hurt. `ijs-mcp-server` and the gate's own terminal
   dashboard still call `loadRuns`/`loadAll` and have not been measured against the real
   corpus; until they are, "one project's full history fits in memory" is an assumption
   with a known counterexample (quality-gate-swift: 2,554 runs, 1.4 GB).

## Quality Standards

`coding_rules.md`, Swift 6 strict concurrency, zero warnings, DocC on every public type.
**Round-trip tests against fixed fixtures**, including artifacts from older schema versions
— that is the only way a compatibility guarantee is more than an intention.

---

**Last Updated:** 2026-10-06 — added `loadHistory` (1.21.0) to *What's Working* and
priority 6, the unmeasured readers it leaves behind. Also recorded 1.20.0 in the CHANGELOG,
which had been tagged without an entry. Previously: 2026-09-19 — reconciled against quality-gate 3.1.2 after the
1.17.0–1.18.0 absorption, which had shipped without touching this document. Added *The
reading layer* and the four absorbed targets the `status` checker had been asking for
(`IJSAggregator`, `IJSPolicyDiscovery`, `IJSDashboardCore`, `JudgmentWorkbench`), refreshed
the file counts (47/54 → 64/81) and the gate version, and stated where the absorption moved
the *Boundaries* line rather than leaving a claim the source tree contradicts. Priorities 4
and 5 record what the pass cost: two defects carried in by the absorption, both hidden
behind a gate run that stopped at checker 3 of 45.

**Prior — 2026-08-25:** reconciled against quality-gate 3.1.0: recorded the `ProcessRunner`
kernel and the deadlock it closed, added the `CorpusKit` target entry the status checker had
been asking for, and closed both open-question markers under *Stability* — per-type version
table (no package-wide scalar exists), a permanent v1 floor with migration as the only way it
moves, and the producer/consumer skew hazard the asymmetric policy creates. Priorities named
the two gaps that keep that floor from being enforceable: missing v1 fixtures and an
unconsumed `.skippedNewer`.
