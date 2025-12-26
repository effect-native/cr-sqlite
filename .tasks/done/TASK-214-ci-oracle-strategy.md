# TASK-214 — CI Oracle Strategy (Rust/C availability)

## Goal
Decide and implement a CI strategy for tests that currently rely on the Rust/C oracle.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Context / Evidence
- CI was disabled partly due to oracle-dependent tests:
  - `.tasks/done/TASK-206-disable-ci-temporarily.md`
  - `.tasks/backlog/TASK-207-reenable-ci-for-release.md`

## Options
- Provide oracle binaries in CI (build `core/` or download prebuilt)
- Split CI: always run Zig-only tests; run oracle parity on a best-effort job
- Remove oracle dependency for release gate (only for preview) and rely on Zig-only suites

## Files to Modify
- `.github/workflows/zig-tests.yaml`
- Potentially add CI scripts under `zig/harness/` for "zig-only" vs "oracle" grouping

## Acceptance Criteria
1. [x] CI config clearly separates oracle-dependent and zig-only test jobs
2. [x] Release gating jobs do not silently pass by skipping too much
3. [x] Document which jobs are required for `0.16.300-preview`

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`
- CI re-enable: `.tasks/active/TASK-207-reenable-ci-for-release.md`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Implemented split CI strategy.

## Completion Notes
Implemented in `.github/workflows/zig-tests.yaml`:

**Strategy: Split jobs by oracle dependency**

**Zig-only tests (required, `test-parity-zig-only`):**
23 tests that validate Zig extension independently:
- test-alter.sh, test-automigrate.sh, test-backfill.sh
- test-clock-edge-cases.sh, test-clset-vtab.sh, test-crsqlite.sh
- test-e2e-sync.sh, test-filters.sh, test-fract.sh, test-is-crr.sh
- test-large-data.sh, test-merge-atomicity.sh, test-noops.sh
- test-persistence.sh, test-pk-update.sh
- test-realistic-collab.sh, test-realistic-offline.sh, test-realistic-sync.sh
- test-rowid-slab.sh, test-sync-bit-isolation.sh, test-table-compat.sh
- test-unpack-columns-vtab.sh, test-wal-concurrency.sh

**Oracle parity tests (optional, `test-parity-oracle`):**
Uses `make test-parity` which runs the full test-parity.sh suite.
The suite handles oracle availability internally via `has_oracle()`.
Tests that require the oracle skip gracefully if unavailable.
Job uses `continue-on-error: true` so failures don't block release.

**Oracle availability:**
- Oracle binaries checked into `lib/` (already committed)
- CI checks for `lib/crsqlite-linux-x86_64.so` before running oracle tests
- If oracle unavailable, tests skip gracefully

**Release gate:**
- `release-gate` job aggregates all required checks
- Oracle tests explicitly excluded from release gate
- Tests that exit with code 2 (SKIPPED) don't fail the build
