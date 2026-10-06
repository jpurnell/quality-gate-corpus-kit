# Design Proposal — A Run Is One Line

**Status:** approved 2026-10-06 and implemented in 1.22.0. One departure: `HistorySignature`
carries the run-file count as well as the index's size and time (§3.3, §4) — see the CHANGELOG.
Open question 1 was settled as a parallel `counts` map in `RunIndexEntry`; question 2 as
"committed".
**Date:** 2026-10-06
**Affects:** `TelemetryWriter.write(metadata:calibrations:to:)`; `CorpusPath`; `CorpusReader`
(`loadHistory`, a new `loadLatestRun`); a new artifact, `telemetry/<project>/index.jsonl`
**Prompted by:** the dashboard memory fix (1.21.0, `7b91c67`). `loadHistory` made reading a
project's history cheap in memory. It is still expensive in I/O: it opens every run file to learn
what a few kilobytes of each one say, and the dashboard still stats every file in the corpus
every thirty seconds to learn whether anything changed.
**Format:** `design_proposal.md` as of development-guidelines `d616461` (§9 *Resource Budget*).

---

## 1. Objective

Record each run's outline once, when the run is written, in one append-only file per project —
so that reading a project's history is reading one file, and noticing a change is one `stat`.

**Master plan reference:** *Priorities* 6 — "a reader's cost is part of its contract."

## 2. Motivation

Measured on the real corpus, 2026-10-06 (20,763 run files, 3.16 GB, 82 projects with telemetry):

| operation | today | why |
|---|---|---|
| "did anything change?" (dashboard, every 30 s) | **1–2 s**, ~90,000 `stat` calls | the only signal is the newest mtime in the tree |
| cold load of the dashboard | **19–34 s** (debug build), 3.16 GB read | every run file is opened to extract an outline |
| reload after one run of `quality-gate-swift` | **3–5 s**, 1.4 GB read | one new file means re-reading that project's 2,554 |
| `ijs-mcp-server` consistency query | a whole project's history decoded, diagnostics included | to use `runs.last` |

Memory is no longer the problem: the dashboard peaks at 128 MB. The cost that remains is that
**the corpus has no table of contents.** An outline — which checkers ran, how each ended, when,
by whom — averages **6.0 KB** of a run file that averages **126 KB** (400-file sample), and every
reader re-derives it from the full file on every read.

**The workaround** is what 1.21.0 does: scan, but scan frugally. It is correct and bounded, and it
gets slower by about 450 run files a day.

## 3. Proposed Architecture

```
telemetry/<project>/
├── index.jsonl                 ← new: one line per run, append-only
├── work-log.json               ← existing per-project file; the precedent for this one
└── 2026-10-06/
    └── 135346_metadata.json    ← unchanged, and still the truth
```

**The index is derived and the run files are the truth.** Every line can be regenerated from the
file it names. Nothing reads the index for anything a run file would contradict.

### 3.1 What a line is

```json
{"schemaVersion":1,"file":"2026-10-06/135346_metadata.json","bytes":771884,"run":{…}}
```

`run` is the run's `CheckResultMetadata` exactly as written, with each result's `diagnostics`
emptied and replaced by counts (`errors`, `warnings`, `notes`). It decodes through `RunOutline`,
the type 1.21.0 added, so **the index has no schema of its own for a run** — a field added to
`CheckResultMetadata` appears in new lines without this file changing. Compact encoding, one
line, newline-terminated.

### 3.2 Who writes it

`TelemetryWriter.write(metadata:calibrations:to:)` — the one path every writer already takes
(four call sites in quality-gate-swift, one in org-judgement-system). After the run file is
written atomically, the line is appended with a single `write(2)` on a descriptor opened
`O_APPEND`.

**Order matters and failure is tolerated in one direction only.** Run file first, then the line.
If the append fails, the run is recorded and unindexed, which §3.4 detects; the write logs and
does not throw. The reverse — a line naming a file that does not exist — cannot happen.

### 3.3 How it is read

- **`loadHistory(for:)`** keeps its signature. It reads `index.jsonl`, reconciles (§3.4), and
  reads in full only the files holding each checker's latest standard result — as now, but
  finding them by name instead of by scanning.
- **`loadLatestRun(for:)`** — new. The newest line names one file; that file is read. This is
  what `ijs-mcp-server` wants and has no cheap way to ask for.
- **`historySignature(for:)`** — new. The index file's size and mtime: the change signal for one
  project, one `stat`. A poller that remembers the size can read only the bytes past it.

### 3.4 Reconciliation — why the index can be trusted

A cache that can silently disagree with its source is worse than no cache. The reader does not
assume the index is complete:

1. **List, don't stat.** `readdir` each date directory and collect the `*_metadata.json` names.
   For the whole corpus that is 6,121 directories and **0.23 s** (measured), with no file opened.
2. **Compare** with the set of `file` values in the index.
3. **Unindexed runs** — written by a gate older than this change, arrived by `git pull` from CI,
   or orphaned by a failed append — are outlined from their files, in memory, for this read. The
   reader logs the count and **does not write**: a reader that repairs is a second writer.
4. **Lines naming a missing file** are dropped and logged.
5. **Duplicate lines** (a union merge, a retried write): last one wins, keyed by `file`.
6. **A torn final line** (a crash mid-append): ignored and logged; its run is then unindexed and
   handled by 3.
7. **Order is not assumed.** Merged lines arrive out of order; the reader sorts by timestamp.

A project with no index at all is entirely case 3, which is exactly 1.21.0's behaviour. **The
index is an optimisation that degrades to the current implementation**, never to a wrong answer.

### 3.5 Backfill and repair

`TelemetryWriter.rebuildIndex(for:)` writes a project's index from its run files, atomically
(temp file, rename). The gate exposes it as a command. It runs once to backfill 20,763 runs and
afterwards only when reconciliation reports unindexed runs that are not going away.

### 3.6 Sync

The corpus is a git repository auto-committed every two hours, in a Dropbox folder.

- **git:** `.gitattributes` gains `telemetry/*/index.jsonl merge=union`. Two branches that each
  appended lines merge to both sets; §3.4 rules 5 and 7 absorb the result.
- **Dropbox:** two machines appending to the same file while both are offline would produce a
  conflicted copy. In the last 14 days 3,321 of 3,336 sampled runs came from one machine and the
  rest from CI runners that arrive by git, and the corpus contains no conflicted copies of
  `work-log.json`, which every run already rewrites in full. A conflicted copy of the index loses
  nothing — its runs are unindexed and reconciled — but it is the failure to watch for.

## 4. API Surface

```swift
// CorpusKit
public struct RunIndexEntry: VersionedCorpusArtifact, Equatable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let file: String          // relative to the project directory
    public let bytes: Int
    public let run: CheckResultMetadata   // diagnostics empty
}
extension CorpusPath { public var runIndexPath: String { get } }
extension TelemetryWriter {
    public func rebuildIndex(for corpus: CorpusPath) async throws -> Int   // lines written
}

// IJSDashboardCore
extension CorpusReader {
    public func loadLatestRun(for project: String) throws -> TimestampedRun?
    public func historySignature(for project: String) -> HistorySignature?
}
public struct HistorySignature: Sendable, Equatable { public let bytes: Int; public let modified: Date }
```

Per-result diagnostic counts need a home. `CheckResult` (quality-gate-types) has none, so they
ride in `RunIndexEntry` as a parallel `[String: DiagnosticCounts]` keyed by checker id — see §16.

## 5. MCP Schema

N/A — no tool is added. `ijs-mcp-server`'s existing tools get faster.

## 6. Constraints & Compliance

**Concurrency:** the append is inside the `TelemetryWriter` actor; across processes it relies on
`O_APPEND`, which positions and writes atomically for a single `write(2)`.
**Containment:** the index path goes through `sanitizedURL(_:within:)` like every other write;
`file` values read back are checked with `CorpusPath.contains` before anything is opened — a
line is corpus content, and corpus content is not trusted (1.19.1).
**Versioning:** `RunIndexEntry` is a `VersionedCorpusArtifact`; a line newer than the reader is
skipped, and its run falls to reconciliation.
**Corpus safety:** tests write to a temp directory, never the real corpus.

## 7. Source & API Compatibility

**Breaking changes:** none. `loadHistory` is unchanged in signature and in result; a test pins
that it returns the same `ProjectHistory` with and without an index.
**Old readers** ignore `index.jsonl` — every existing reader filters on file suffix.
**Old writers** (a gate built before this) produce unindexed runs; §3.4 handles them.
**Adoption:** the reader ships first and changes nothing until an index exists.

## 8. Backend Abstraction

N/A.

## 9. Resource Budget

**Data read:** one `index.jsonl` per project. Projected from the 400-file sample: **6.0 KB a
line, 125 MB across the corpus today**, the largest single index (`quality-gate-swift`, 2,554
runs) about 20 MB. Growing by about 450 lines — 2.7 MB — a day.
**Held vs streamed:** lines are decoded one at a time and reduced by the caller; `loadHistory`
returns the outlines, as it does now, so a project's history is held while its summary is
computed and then released. The index bytes themselves are memory-mapped, not copied.
**Growth:** linear in runs, at 4% of the rate the corpus grows. A year at today's rate adds
about 1 GB of index to about 21 GB of run files.
**Budget:** no change to any consumer's budget — the dashboard stays at 200 MB peak. The writer
adds one encoded line (≤ 132 KB, the largest outline in the sample) per run.
**Measured by:** the dashboard's footprint, re-measured against the real corpus after backfill;
and a test here that reads a generated 2,500-line index and asserts peak footprint.
**Disk:** 125 MB added to a 4.0 GB corpus directory, and to the git repository.
**Lifetime:** the index lives as long as the corpus. Nothing compacts it; see §15.

*What this section forced:* the first estimate, written before measuring, was 2 KB a line and
40 MB. The sample says 6 KB and 125 MB — the per-checker results alone are 5 KB. The design
survives the correction, and §14 has the alternative that would get the 40 MB back.

## 10. Dependencies

None new.

## 11. Test Strategy

- **Write appends a line** that decodes to the run minus diagnostics, with correct counts.
- **Two writes, two lines**, in order; the second does not rewrite the first.
- **`loadHistory` is identical** with an index, without one, and with a partial one — the same
  `ProjectHistory`, compared against 1.21.0's scan. *This is the reference truth.*
- **Reconciliation:** an unindexed run file is found; a line with no file is dropped; duplicates
  collapse; a torn last line is ignored; out-of-order lines are sorted.
- **A `file` value of `../../x`** is refused, not opened.
- **A line with a newer schema version** is skipped and its run reconciled.
- **`loadLatestRun`** returns the newest run with its diagnostics; nil for an empty project.
- **`rebuildIndex`** over a fixture equals the index the writer would have produced.
- **Append failure** (read-only directory) leaves the run file written and the write not thrown.

## 12. Architecture Decision Review

- **Per project, not one file.** One corpus-wide file is one merge conflict per concurrent
  writer and a rewrite on every run. Per project, a change is local and the poll is 82 `stat`s.
- **In the corpus, not a local cache.** A local cache has no sync problem and has to be built
  per machine and invalidated by something. In the corpus, the writer that knows a run exists is
  the one that records it.
- **JSONL, not a JSON array.** `work-log.json` is rewritten whole on every run and is 1.3 MB for
  `quality-gate-swift`. An array cannot be appended to or union-merged.
- **Full outline per line, not a compact digest.** See §14.

## 13. Adversarial Review

**The counter-design: don't store it, cache it.** Keep the corpus exactly as it is and have each
reader keep its own outline cache in `~/Library/Caches`, keyed by run-file name and size. No new
artifact, no schema, no sync semantics, no writer change, nothing to backfill, and nothing in
git. The first read on a machine costs what a read costs today and every later one is
incremental. Everything in §3.4 exists only because the index is shared.

**Response.** That design is simpler and is the right one if the corpus has one reader. It has
three — the dashboard, the gate's terminal dashboard, `ijs-mcp-server` — plus the server, and
each would build and invalidate its own copy of the same 125 MB. More to the point, a reader's
cache cannot answer "did anything change" without listing the tree; only the writer knows a run
was added at the moment it is added. Accepted cost: reconciliation, which is 0.23 s and is the
price of the index being shared.

**The assumption whose failure breaks this:** that every writer goes through
`TelemetryWriter.write`. If something writes a `_metadata.json` any other way — a script, a
restore, a hand-edit the package forbids — the run is permanently unindexed. Reconciliation
still returns the right answer, but slowly and with a log line nobody is reading, and the index
quietly stops being an optimisation for that project.

**The critic's objection:** *"You fixed a problem caused by re-deriving data, by adding a second
copy of it that can drift."* Yes. The defence is §3.4 and the identity test in §11; if either is
weak, the objection is right.

## 14. Alternatives Considered

| alternative | for | against |
|---|---|---|
| Reader-side cache (§13) | no new artifact, no sync | per-reader, per-machine; cannot signal change |
| Compact digest per line (id, status, counts — ~1.2 KB) | ~30 MB instead of 125 MB | a second schema for a run, which is the thing this package exists to prevent; every summary would need to read two shapes |
| One corpus-wide index | one file, one `stat` | conflicts on every concurrent write; rewritten or appended by everyone |
| SQLite in the corpus | real queries, real indexes | a binary file in git and in Dropbox; merges are impossible |
| Do nothing | 1.21.0 is correct and bounded | 450 more files to open every day, forever |

## 15. Future Directions

- A corpus-level head file could reduce the poll from 82 `stat`s to one. It would have to be
  local and derived (§12), and 82 `stat`s cost 0.4 ms.
- The same treatment for pulses: `listAvailableLabels` decodes every pulse to list them.
- Compaction of very old lines into a yearly file, if the index ever needs it.
- Run files are named to the second; two runs of one project in one second share a name. Not
  introduced here, but the index would make it visible as a duplicate.

## 16. Open Questions

1. **Where do per-result diagnostic counts live?** `CheckResult` has no field for them. A
   parallel map in `RunIndexEntry` works and is slightly awkward; adding optional counts to
   `CheckResult` is cleaner and is a quality-gate-types release.
2. **Should the index be committed to git at all,** or gitignored and rebuilt per clone? Committed
   is 125 MB of repository and no rebuild; ignored is the reverse. This proposal assumes
   committed.
3. **Who runs the backfill, and when?** It is one command. It should probably be run by a person,
   once, with the auto-commit job paused.
4. **Does the corpus service write through `TelemetryWriter`?** Not verified. §13's breaking
   assumption depends on it.

## 17. Documentation Strategy

The README's layout block gains `index.jsonl`, with one sentence: derived, rebuildable, never
the truth. `master_plan.md` *The contract* gains the reconciliation rule. `DRIFT.md` records the
decision that readers reconcile and do not repair.
