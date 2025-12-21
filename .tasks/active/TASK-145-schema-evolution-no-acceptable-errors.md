# TASK-145 — Tighten schema evolution sync semantics (stop accepting SQL logic errors as PASS)

## Goal
Turn the "acceptable error" paths in `zig/harness/test-schema-evolution.sh` into explicit, stable behavior assertions, so schema-evolution sync does not silently mask real compatibility issues.

## Status
- State: active
- Priority: medium

## Problem Statement
`zig/harness/test-schema-evolution.sh` currently treats some merge/apply failures as passing:
- Scenario 2b: Apply changeset for dropped column
  - reports `WARN: SQL error (may be expected behavior)`
  - then treats error as acceptable and marks PASS
- Scenario 3a: Merge changesets from different schema evolution paths
  - reports error and marks PASS if error message is "column-related"

This is a potential invalidation surface:
- We might be masking a real bug (wrong error class, partial apply, data corruption).
- Behavior may differ between implementations (Zig vs Rust/C).

## Files to Modify
- `zig/harness/test-schema-evolution.sh`
- Potentially: `zig/harness/test-oracle-parity.sh` (if we decide to oracle-compare schema-evolution errors)

## Acceptance Criteria
1. The schema evolution harness encodes explicit expectations, e.g.:
   - exact error type/classification (not "SQL logic error" catch-all)
   - state invariants after the failed apply (no partial writes; db_version unchanged; table schema unchanged)
2. The test fails if the observed behavior drifts (different error, partial apply, inconsistent clock state).
3. If Rust/C behaves differently, the test records it as a parity gap with clear reproduction.

## Parent Docs / Cross-links
- `zig/harness/test-schema-evolution.sh`

## Progress Log
- 2025-12-21: Task created from observed "PASS with SQL logic error" patterns in schema evolution harness.

## Completion Notes
(Empty until done.)
