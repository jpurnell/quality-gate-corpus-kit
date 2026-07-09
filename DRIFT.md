# Drift ledger — reconciliations between the two prior corpus implementations

Per the Phase 0.3 proposal: every behavioral difference found while unifying
the quality-gate-swift and org-judgement-system corpus code is recorded here
with its reconciliation decision.

| # | Drift | Decision |
|---|---|---|
| 1 | `IJSError`: org-judgement-system had `narrativeGenerationFailed` and `corpusSyncFailed` cases; quality-gate-swift's copy lacked both (CorpusManager could not even compile against it) | Superset: both cases adopted into CorpusKit's `IJSError` |
