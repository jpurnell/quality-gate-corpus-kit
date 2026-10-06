# quality-gate-corpus-kit

The **one implementation** of the quality-gate corpus (Phase 0.3 of the
ecosystem roadmap): every type serialized into the corpus, the deterministic
path layout, the telemetry reader/writer actors, and the git sync manager —
extracted from quality-gate-swift (source of truth) and org-judgement-system
(CorpusManager), consumed by both.

Since 1.17.0 it also holds **the shared code that reads that corpus** — `IJSAggregator`
(calibration), `IJSPolicyDiscovery` (consistency scoring), `IJSDashboardCore` (`CorpusReader`,
trends, summaries) and `JudgmentWorkbench` (findings inbox) — moved here from
quality-gate-swift because each is shared by the gate, `ijs-mcp-server` and
quality-gate-dashboard, and belongs to none of them. Deriving from the corpus is inside;
running a checker or deciding a verdict stays outside. See `project/master_plan.md`.

The corpus directory layout documented here is the canonical schema contract:

```
manifest.yml
telemetry/<projectID>/<YYYY-MM-DD>/<HHmmss>_{metadata,calibration_N,complexity,orientation}.json
telemetry/<projectID>/index.jsonl          one line per run — derived, rebuildable, never the truth
telemetry/<projectID>/work-log.json
snapshots/<projectID>/<YYYY-MM-DD>.json
pulse/<label>/PULSE_<label>.json + NARRATIVE_<label>.md
```
