# TASK-087: Spec (RGRTDD) — Atomic batch apply via `crsql_changes` inserts

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust reference: `core/rs/core/src/changes_vtab_write.rs` (savepoint usage)
- Zig merge entrypoint: `zig/src/changes_vtab.zig` (`changesUpdate`)
- C suite that exercises batching: `core/src/rows-impacted.test.c` (multipart insert)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define atomicity requirements for applying a batch of incoming changes.

Real systems typically ship changes in batches (single SQL statement with multiple VALUES rows, or a transaction). If any element of the batch fails, we need a clear contract for what persists.

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-merge-atomicity.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Tests fail on current Zig if atomicity is not guaranteed.
- [ ] Tests specify at least:
  1. **Statement atomicity**: a single multi-row `INSERT INTO crsql_changes VALUES (...), (...);` either fully applies or applies nothing.
  2. **Error injection**: craft a batch where the 2nd row is invalid (e.g. references a missing column) and assert the 1st row did not apply.
  3. **Rows impacted**: `crsql_rows_impacted()` reflects applied rows only when commit succeeds.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
