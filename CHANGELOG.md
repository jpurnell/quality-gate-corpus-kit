# Changelog

All notable changes to quality-gate-corpus-kit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Added
- `swift-docc-plugin` dependency so the quality gate's `doc-lint` checker can
  run `generate-documentation`.

## [1.12.0]

- Baseline release prior to the path-guard containment fix. See git history and
  `DRIFT.md` for the Phase 0.3 reconciliation record.
