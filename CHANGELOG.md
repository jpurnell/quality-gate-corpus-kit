# Changelog

All notable changes to quality-gate-corpus-kit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.17.0] — 2026-09-18

### Added
- **The IJS sensing layer** — `IJSAggregator`, `IJSPolicyDiscovery`, `IJSDashboardCore` — moved
  here from `quality-gate-swift`. They read a corpus and compute over it, and are shared by the
  gate's three corpus-reading checkers, by `ijs-mcp-server` and by `quality-gate-dashboard`.
  Belonging to none of those, they now live beside the format they read.
- `CorpusPath.isSingleComponent(_:)` and `requireSingleComponent(_:label:)` — a corpus
  identifier names one directory; anything carrying a separator or a relative component is a
  path, not an identifier.

### Fixed
- **Path traversal in the corpus readers.** `loadRuns(for:)` and
  `loadLatestOrientationReport(for:)` interpolated their `project` argument into a filesystem
  path with no containment. A crafted `project_id` from an MCP tool call read a **different
  corpus** and returned a valid-looking consistency score. Both now validate the identifier and
  containment-check the resolved path; the MCP tools also refuse a bad `project_id` at the
  boundary, so it fails as a named error rather than an empty result.

  `loadPulse(label:)` was guarded, but by `fileURL.path.hasPrefix(baseURL.path)` — which accepts
  `/corpus-evil` for a base of `/corpus`. It compares path components now, which is why
  `CorpusPath.contains(_:within:)` exists.

  The `// SAFETY:` comments on those lines read *"project from discoverProjects"*. That was true
  when the only caller listed the directory itself, and false once a network-facing server
  passed client strings to a reader.

### Removed
- **`IJSSensor`.** One line — `@_exported import CorpusKit` — kept because it looked free. It
  failed to forward `CorpusPath` where that was wanted, forwarded CorpusKit's new
  `ProcessRunner` into 29 consumer files where it collided with the `swift-process-kernel`
  package that owns that name, and hid the collision behind a wrong-member error instead of an
  ambiguity error. Consumers `import CorpusKit` directly.

### Changed
- `quality-gate-types` floor raised to **1.5.0**. The absorbed code uses `Diagnostic.isViolation`,
  which postdates 1.1.x; the old floor resolved to 1.1.1 and compiled only because nothing here
  needed the newer surface.

## [1.16.0] — 2026-09-17

### Changed
- **Deployment floor lowered to `.macOS(.v14)`.** The package declared `.v15` while depending on
  nothing that needed it: `QualityGateTypes` is v14, Yams and swift-docc-plugin impose nothing, and
  there is not one `@available(macOS 15)` annotation in `Sources/`. The floor was inherited from
  `quality-gate-swift`, where it is load-bearing for the gate's index-store and GPU work, and
  carried here by copy.

  It stopped being free the moment something wanted to read a corpus without being able to run the
  gate. `ijs-mcp-server` is that case — it only reads corpus JSON and serves MCP, both of which
  `SwiftMCPServer` already does at v14 on four production servers, but it could not be hosted
  beside them because this floor put it out of reach of a macOS 14.8.9 host.

### Added
- `ProcessRunner` and `ProcessResult` — the package's single audited subprocess
  kernel. Every spawn now routes through it, bounded by a timeout with
  `SIGTERM` → `SIGKILL` escalation, with both output streams drained
  concurrently. `ProcessResult.outputTruncated` reports a capture cut short
  because a grandchild still held an inherited pipe write end open, rather than
  presenting a partial capture as whole.
- A `CorpusKit.docc` catalogue, **declared as a resource rather than excluded**, so `doc-lint` has
  a target to examine instead of passing vacuously on a package with none.

  The catalogue was added earlier in this cycle with `exclude: ["CorpusKit.docc"]`, which silences
  SwiftPM's unhandled-file warning by removing the catalogue from `sourceFiles` — exactly where
  swift-docc-plugin looks for it. So DocC received nothing and `doc-lint` still passed vacuously,
  while this entry already claimed otherwise. `resources: [.copy(…)]` makes the claim true. The
  gate said so on its own (`doc-lint.catalogue-excluded`), which is the difference between this
  and the three documentation claims corrected elsewhere today that nothing checked.

### Fixed
- Four `coalesced-assertion` findings in this package's own tests —
  `abs((stats.meanConsistencyScore ?? 0) - 0.82) < 1e-6` and three of the same shape — are now
  `try #require` bindings, so a missing score fails by naming itself rather than failing an
  arithmetic comparison it was never about. Two of the four needed their test function marked
  `throws`, which is the gotcha the rule's own diagnostic warns about.

### Fixed
- **Latent hang in `ProjectIdentity.originRemoteURL`.** It attached a `Pipe` to
  the child's stderr and never read it, so a `git` invocation that wrote more
  than the ~64 KB pipe buffer to stderr would block on write while the caller
  blocked in `waitUntilExit()` — a deadlock, reachable in normal operation.
- **Unbounded git waits in `CorpusManager`.** `pull`, `push`, and `clone` had no
  timeout, so an auth prompt or a stalled network pinned the actor
  indefinitely. Network subcommands now carry a 300s bound and local ones 60s.
- `CorpusManagerTests.runShellOutput` waited for exit *before* reading the pipe,
  the same deadlock in test setup.

### Changed
- Test suites build dates through a shared `TestDates` helper instead of 25
  force unwraps across 12 files, removing both the crash risk and a duplicated
  formatter configuration that could have drifted per file.
- `.quality-gate.yml` declares `boundedIO.kernelPath`, and drops the `exclude:`
  and `checkers:` blocks. Neither key is read by the gate, so neither had ever
  taken effect; they were removed rather than renamed, because the literal
  translation (`enabledCheckers: [all, logging]`) is an allow-list and would
  have silently disabled every checker but two.

## [1.15.0] — 2026-08-25

### Added
- `TruncationRecord` and `CheckResultMetadata.truncation` (quality-gate
  Change C): a default gate run halts at its first failing checker, and every
  checker after it never runs. Until now the emitted record could not express
  that — a truncated run was indistinguishable from a clean scoped run, so
  dashboards read "never ran" as "found nothing". Optional and defaulted;
  legacy artifacts decode as complete runs, no schema bump (defaulted-field
  rule).

## [1.14.0] — 2026-07-29

### Added
- `ProseSource` extended from `template`-only to the full narrative-provenance
  vocabulary (`template`, `claude`, `onDeviceLLM`, `preservedLLM`) plus
  `CaseIterable`, and moved to its own `ProseSource.swift` — one shared
  provenance type for both module orientation cards and the pulse narrative
  (retires the duplicate `NarrativeSource` enum in quality-gate-swift).
- `InstitutionalPulse.narrativeSource: ProseSource?` records which engine
  produced the narrative, so the dashboard can badge on-device vs Claude from
  the pulse JSON (previously only in `NARRATIVE_*.md` frontmatter). Optional
  with tolerant decode — no schema-version bump. `withNarrative(_:source:)`
  sets it.

## [1.13.0] — 2026-07-29

### Added
- `CorpusPath.resolvedURL(for:within:)` / `CorpusPath.contains(_:within:)` (plus
  instance sugar `resolvedURL(forContainedPath:)` / `contains(_:)`) — the single
  hardened corpus-base containment check, so every writer shares one
  symlink-safe, component-aware implementation instead of a per-writer copy.
  `TelemetryWriter` now delegates to it. (Downstream `DecisionWriter` /
  `NarrativeWriter` in org-judgement-system migrate to this API in a follow-up.)

## [1.12.1]

### Fixed
- `TelemetryWriter.sanitizedURL` corpus-base containment guard. The previous
  `hasPrefix` check over symlink-resolved paths both rejected legitimate writes
  under a symlinked corpus base (`/tmp` ↔ `/private/tmp`) and admitted
  prefix-sibling escapes (`/a/corpus-evil` as inside `/a/corpus`). Containment
  is now checked lexically and component-wise, with the validated relative
  suffix re-anchored onto the base resolved once via `resolvingSymlinksInPath`.
  Same signature — source-compatible.
- `SpoolingCorpusTransport` fail-open catch blocks now log the caught upstream
  error at the catch site (privacy-annotated); `spool(_:)` no longer
  double-logs.
- `CorpusSchema.decode` logging: added `privacy:` annotations to the schema
  version interpolations.
- Documented `CheckResultMetadata.init`'s `gateMode` and `baseline` parameters.

### Added
- `swift-docc-plugin` dependency so the quality gate's `doc-lint` checker can
  run `generate-documentation`.
- Adopted the standard Design-First TDD `development-guidelines` process:
  `CLAUDE.md`, `.claude/` bridge layer, `.githooks/`, and a pinned
  `.quality-gate.yml` (checker set + `ijs`/`consistency` config), plus this
  `CHANGELOG`. The guidelines live in a gitignored nested clone on the
  `project-state/quality-gate-corpus-kit` branch.

### Test-quality
- `RemainingArtifactVersioningTests` now assert each artifact type directly in
  the test body (helpers return `Bool`) so the assertion auditor sees them.

## [1.12.0]

- Baseline release prior to the path-guard containment fix. See git history and
  `DRIFT.md` for the Phase 0.3 reconciliation record.
