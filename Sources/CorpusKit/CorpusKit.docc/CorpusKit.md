# ``CorpusKit``

The one implementation of the quality-gate corpus: the types written into it,
the deterministic path layout, the telemetry readers and writers, and git sync.

## Overview

`CorpusKit` is consumed by both `quality-gate-swift` (the gate that produces
telemetry) and `org-judgement-system` (the pipeline that consumes it). Both
sides depend on agreeing byte-for-byte about where an artifact lives and how it
decodes, so a defect here propagates to every consumer.

Four groups of types carry that contract:

- **Schema types** stamp a schema version and follow the skip-newer decode
  policy in ``CorpusSchema``, so an old reader meeting a newer artifact skips it
  rather than misreading it.
- **Paths** are computed by ``CorpusPath`` alone. Nothing else in the package
  builds a corpus path by string concatenation.
- **I/O** goes through ``TelemetryWriter`` and the ``CorpusTransport`` family,
  which spool and fail open rather than lose a run's telemetry.
- **Sync** is ``CorpusManager``, which wraps the `git` CLI around the local
  corpus directory.

## Subprocess safety

Every subprocess this package spawns goes through ``ProcessRunner``, and that
containment is enforced by the gate's `bounded-io` checker rather than by
convention. `Process.run()`, `waitUntilExit()`, and `readDataToEndOfFile()` are
each unbounded on their own: a child that outlives its usefulness pins the
caller forever, and a child that writes more than a pipe buffer deadlocks
against a reader that is not draining it. Keeping all three in one file does not
make them correct — it makes one file the only place that has to be.

## Topics

### Paths and Schema

- ``CorpusPath``
- ``CorpusSchema``

### Telemetry

- ``TelemetryWriter``
- ``CorpusTransport``

### Sync

- ``CorpusManager``
- ``ProcessRunner``
- ``ProcessResult``
