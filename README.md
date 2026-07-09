# quality-gate-corpus-kit

The **one implementation** of the quality-gate corpus (Phase 0.3 of the
ecosystem roadmap): every type serialized into the corpus, the deterministic
path layout, the telemetry reader/writer actors, and the git sync manager —
extracted from quality-gate-swift (source of truth) and org-judgement-system
(CorpusManager), consumed by both.

The corpus directory layout documented here is the canonical schema contract:

```
manifest.yml
telemetry/<projectID>/<YYYY-MM-DD>/<HHmmss>_{metadata,calibration_N,complexity,orientation}.json
snapshots/<projectID>/<YYYY-MM-DD>.json
pulse/<label>/PULSE_<label>.json + NARRATIVE_<label>.md
```
