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

## Stability

**Schema changes are the risk, not source compatibility.** A Swift API break is a compile
error someone fixes in an afternoon. A schema change that silently reinterprets existing
artifacts corrupts a longitudinal series retroactively, and nothing errors.

Rules that follow:

- Every artifact carries its schema version. No exceptions, including new types.
- Readers tolerate older versions; writers never rewrite history.
- A field's meaning is fixed once written. Need different semantics? New field.

**[NEEDS INPUT]** — the current schema version, and the oldest version readers still
support. Both belong here.

## Current Status

- [x] 47 source files, **54 test files** — the best-covered package in this tier, which is
      appropriate for something whose failures are silent and retroactive

**Priorities: [NEEDS INPUT]**

## Quality Standards

`coding_rules.md`, Swift 6 strict concurrency, zero warnings, DocC on every public type.
**Round-trip tests against fixed fixtures**, including artifacts from older schema versions
— that is the only way a compatibility guarantee is more than an intention.

---

**Last Updated:** 2026-08-04
