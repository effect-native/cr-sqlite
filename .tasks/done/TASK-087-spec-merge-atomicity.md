# TASK-087: Spec (RGRTDD) — Atomic batch apply via `crsql_changes` inserts

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] Tests fail on current Zig if atomicity is not guaranteed.
- [x] Tests specify at least:
  1. **Statement atomicity**: a single multi-row `INSERT INTO crsql_changes VALUES (...), (...);` either fully applies or applies nothing.
  2. **Error injection**: craft a batch where the 2nd row is invalid (e.g. references a missing column) and assert the 1st row did not apply.
  3. **Rows impacted**: `crsql_rows_impacted()` reflects applied rows only when commit succeeds.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Created `zig/harness/test-merge-atomicity.sh` with 8 test cases
- Wired test into `zig/harness/test-parity.sh`
- All 8 tests pass on current Zig implementation

## Completion Notes
### Test Results (2025-12-20)
All 8 tests **PASS** on the current Zig implementation:

```
Test 1: Single multi-row INSERT applies all rows atomically        PASS
Test 2: Invalid column in batch causes entire statement to fail    PASS
Test 3: rows_impacted is 0 after failed batch                      PASS
Test 4: Failed transaction commits nothing                         PASS
Test 5: Explicit savepoints allow partial rollback                 PASS
Test 6: Duplicate PKs in single batch handled correctly            PASS
Test 7: Base table integrity after failed batch                    PASS
Test 8: rows_impacted accumulates within transaction               PASS
```

### Summary
- **8 tests created** covering batch atomicity scenarios
- **All pass** - Zig implementation already guarantees statement-level atomicity
- SQLite's built-in transaction semantics provide the atomicity (no explicit savepoints needed at the vtab level)
- When a multi-row INSERT fails partway through, SQLite rolls back the entire statement

### Files Created/Modified
1. `zig/harness/test-merge-atomicity.sh` (new) - 8 test cases
2. `zig/harness/test-parity.sh` - Added test invocation

### Note
Unlike Rust which uses explicit savepoints in `changes_vtab_write.rs`, the Zig implementation relies on SQLite's built-in statement-level atomicity which provides equivalent guarantees for the tested scenarios.
