# TASK-186 — Decide schema mismatch behavior for unknown columns

## Goal
Decide whether Zig should error or ignore unknown columns during sync, then align implementations.

## Status
- State: done
- Priority: MEDIUM (behavioral difference, not data corruption)
- Discovered: Round 62 (TASK-173 test suite)

## Problem
When source has a column that destination doesn't have, the implementations differ:
- **Zig**: Returns ERROR
- **Rust/C**: Gracefully IGNORES the unknown column, syncs known columns

**Test failure from `test-schema-mismatch.sh`:**
```
Divergences found:
  - source_has_extra_column: Zig='ERROR' vs Rust='IGNORED'
```

## Scenario
1. Site A: table with columns (id, name, extra)
2. Site B: table with columns (id, name) — no 'extra' column
3. Site A: INSERT with extra='value'
4. Sync A→B
5. **Rust/C**: Row synced, 'extra' column data ignored, known columns applied
6. **Zig**: ERROR returned, nothing synced

## Analysis
Both approaches have merit:
- **Zig (strict)**: Catches schema drift early, prevents silent data loss
- **Rust/C (lenient)**: Allows staggered migrations, more forgiving in production

## Decision Made
**Align with Rust/C (lenient behavior)** — ignore unknown columns during sync.

Rationale:
- Production systems with rolling upgrades need this
- Strict behavior breaks staggered migration scenarios
- Other columns in the same row should still be applied
- Silent data "loss" is acceptable since the column doesn't exist locally anyway

## Files Modified
- `zig/src/merge_insert.zig` — added `columnExistsInTable()` helper
- `zig/src/changes_vtab.zig` — added column existence check before merge

## Acceptance Criteria
1. [x] Decision documented
2. [x] `bash zig/harness/test-schema-mismatch.sh` — All tests pass
3. [x] `bash zig/harness/test-app-todo.sh` — Regression test passes
4. [x] `bash zig/harness/test-parity.sh` — No new regressions

## Parent Docs / Cross-links
- Test: `zig/harness/test-schema-mismatch.sh` (Test 1: source_has_extra_column)
- Triggering task: `.tasks/done/TASK-173-schema-mismatch.md`

## Progress Log
- 2025-12-22: Created from Round 62 divergence discovery.
- 2025-12-25: Fixed by adding `columnExistsInTable()` check in `changes_vtab.zig`.
  - Root cause: When applying a change for a column that doesn't exist locally,
    `updateBaseTableColumn` or `insertOrUpdateColumn` would fail with SQLITE_ERROR
    because the generated SQL references a non-existent column.
  - Fix: Check if column exists before attempting to apply the change.
    If column doesn't exist, skip gracefully with SQLITE_OK (lenient mode).
  - Added check in two places:
    1. Before inserting new rows (NoRows case)
    2. Before updating existing rows (after sentinel handling)

## Completion Notes
- 2025-12-25: COMPLETED
- Test results: `test-schema-mismatch.sh` — 12 passed, 0 failed
- Regression check: `test-parity.sh` — 363 passed, 13 failed (pre-existing failures)
- Key changes:
  - Added `pub fn columnExistsInTable()` in `merge_insert.zig:366-386`
  - Added column check at line ~1740 for new rows
  - Added column check at line ~1960 for existing rows
