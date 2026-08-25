# Session Summary — 2026-08-25

## What prompted this

A quality-gate upgrade to 3.1.0 turned the gate red: **42 errors and 42 warnings
across four checkers**. The reported "safety issue" was the smallest part of it.

## The bug that mattered

`ProjectIdentity.originRemoteURL` attached a `Pipe` to the child's stderr and
never drained it. A `git` invocation writing more than the ~64 KB pipe buffer to
stderr would block on write while the caller blocked in `waitUntilExit()` — a
hang, not a crash, reachable in normal operation.

Two adjacent problems shared the root cause: `CorpusManager` put no timeout on
`pull`/`push`/`clone`, so an auth prompt or stalled network pinned the actor
forever; and `CorpusManagerTests.runShellOutput` waited for exit before reading
its pipe, the same deadlock in test setup.

## What was done

- Added `ProcessRunner`, the package's one audited subprocess kernel: concurrent
  draining of both streams, a timeout with `SIGTERM` → `SIGKILL` escalation, and
  all sixteen spawn sites routed through it.
- Declared it via `boundedIO.kernelPath`, so containment is gate-enforced rather
  than documented — a new ad-hoc `Process()` now fails the build.
- Replaced 25 force unwraps across 12 test files with a shared `TestDates`
  helper, removing a duplicated formatter config along with the crash risk.
- Annotated 34 path-traversal findings and 1 HTTP finding with real `// SAFETY:`
  justifications (all temp-directory paths and one fixture string).
- Added a `CorpusKit.docc` catalogue; `doc-lint` had been failing because it had
  nothing to examine.

## Worth remembering

**Bounding the wait was not enough.** The SIGKILL test initially took the full
60s: `sh` traps `TERM` and forks `sleep`, so killing `sh` leaves a grandchild
holding the inherited pipe write ends open, and reading to EOF outlived the
process being bounded. The drain now carries its own deadline and the result
reports `outputTruncated` rather than passing a partial capture off as whole.
The test that caught this is `escalatesToKill`.

**The config was lying in a dangerous direction.** `.quality-gate.yml` set
`exclude:` and `checkers:`, neither of which this gate reads — so neither had
ever taken effect. The literal repair (`enabledCheckers: [all, logging]`) would
have been worse than the bug: `enabledCheckers` is an allow-list, so it would
have silently disabled 43 of 45 checkers while looking correct. Both blocks were
removed instead of renamed.

**Marker comments are position-sensitive.** `// SAFETY:` and `// TIMING:` must
be single-line and sit on line N-1. Multi-line versions are silently ignored,
which reads as "the exemption doesn't work" rather than "it's misplaced".

## Result

Gate at **0 errors / 0 warnings**, 40 of 45 checkers. Institutional consistency
score recovered from 0.00 to 1.00. All 453 tests pass.

## Next

The two `[NEEDS INPUT]` items in `master_plan.md` under *Stability* — the current
schema version and the oldest version readers still support — are still open and
everything else in that document depends on them.
