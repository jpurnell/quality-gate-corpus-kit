# quality-gate-corpus-kit — Development Guidelines

**The one implementation of the quality-gate corpus** (Phase 0.3 of the ecosystem
roadmap): every type serialized into the corpus, the deterministic path layout,
the telemetry reader/writer actors, and the git sync manager. Consumed by both
`quality-gate-swift` (the gate) and `org-judgement-system` (the IJS pipeline), so
a defect here propagates to every consumer — this library warrants extra rigor.

This project follows the Design-First TDD workflow defined in `development-guidelines/`.

## Architecture

- **Schema types** — `CheckResultMetadata`, `InstitutionalPulse`, `DailySnapshot`,
  `SkipRecord`, etc., most conforming to `VersionedCorpusArtifact` (schema-version
  stamping + the skip-newer decode policy in `CorpusSchema`).
- **Paths** — `CorpusPath` computes the deterministic on-disk layout
  (`telemetry/<projectID>/YYYY-MM-DD/…`, `snapshots/`, `pulse/`).
- **I/O** — `TelemetryWriter` (actor) and `CorpusTransport` / `SpoolingCorpusTransport`
  (fail-open spool) read/write artifacts; `CorpusManager` handles git sync.
- **Reconciliation** — `DRIFT.md` is the ledger of every behavioral difference
  reconciled while unifying the two prior corpus implementations. Record new
  cross-repo reconciliation decisions there.

## Project Conventions

- **Tests** use swift-testing (`import Testing`, `@Suite`/`@Test`/`#expect`), not XCTest.
- **Path containment** — writers validate that a target is inside the corpus base
  lexically and component-wise (never string `hasPrefix` on symlink-resolved paths),
  re-anchoring the validated suffix onto the base resolved via `resolvingSymlinksInPath`.
- **Safety exemptions** — validated-safe `Process`/`FileManager` calls carry a
  single-line `// SAFETY:` justification on the line above the call (never a bare
  suppression; state *why* it is safe).
- **Corpus safety** — the corpus is written only by the tool; never hand-edit it,
  and tests that write a corpus use a temp directory, never the real corpus path.

## Session Start

Read documents in this order for full context recovery:
1. `project/master_plan.md` — Vision and priorities
2. `development-guidelines/rules/coding_rules.md` — Forbidden patterns, safety rules
3. `development-guidelines/rules/test_driven_development.md` — Testing contract
4. `project/checklists/CURRENT_*.md` — Active tasks (if any)
5. Latest file in `project/summaries/` — Where we left off (if any)

For quick recovery (same-day, simple bug fixes), read only items 4-5.

## After Cloning

`.githooks/` is tracked, but `core.hooksPath` is per-clone git config and cannot
be committed — git will not let a repository enable its own hooks. So a fresh
clone has the hook files and does not run them, until:

```bash
./scripts/bootstrap.sh
```

That sets `core.hooksPath` and checks that `swift` and `quality-gate` are
present, since the hooks need both. It is idempotent. If you would rather not
run a script, `git config core.hooksPath .githooks` is the part that matters.

## Development Workflow

```
0. DESIGN   → Propose architecture (design_proposal.md)
1. RED      → Write failing tests first
2. GREEN    → Minimum code to pass
3. REFACTOR → Clean up, keep tests green
4. DOCUMENT → DocC comments and examples
5. VERIFY   → Run quality-gate (zero warnings/errors)
```

## Key Rules

- No force unwraps (`!`), no `try!`, no force casts (`as!`)
- Guard clauses for all validation; early returns over nested ifs
- Division safety: always check for zero before dividing
- Swift 6 strict concurrency compliance
- All public APIs require DocC documentation

## Quality Gate

Run `quality-gate` before every commit. All checks must pass.

The tracked hooks do it: `.githooks/pre-commit` runs `quality-gate --check all --strict`
and `.githooks/pre-push` runs the same with `--release-boundary`, which is the changelog/tag
parity check the earlier push hook made on its own. There is no CI workflow here, so the
hooks are the only automatic gate. `.git/hooks/` is not consulted while `core.hooksPath`
points at `.githooks`; a hook file there is inert.

The gate binary is built from quality-gate-swift, which depends on this package. That is
not a cycle at hook time: the hooks run the *deployed* binary, which holds the release of
this package it was built against, not the working tree.

## References

- Full guidelines: `development-guidelines/README.md`
- Coding rules: `development-guidelines/rules/coding_rules.md`
- TDD contract: `development-guidelines/rules/test_driven_development.md`
- Session workflow: `development-guidelines/rules/session_workflow.md`