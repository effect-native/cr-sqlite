# TASK-078: Implement (RGRTDD) — `crsql_as_crr` backfill in Zig

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Spec task: `.tasks/triage/TASK-077-spec-as-crr-backfill.md` (triage → move to backlog/done as appropriate)
- Test harness: `zig/harness/test-backfill.sh` (created by TASK-096)
- Rust reference backfill: `core/rs/core/src/backfill.rs`
- Zig implementation: `zig/src/as_crr.zig`
- Registration point: `zig/src/ffi/init.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement backfill behavior for `crsql_as_crr` in Zig.

Design intent:
- Populate `__crsql_pks` and `__crsql_clock` for existing rows.
- Use savepoints for atomicity.
- Keep behavior idempotent (EXCEPT/LEFT JOIN style filters like Rust).

### Current Behavior (as of 2025-12-20)
When `crsql_as_crr()` is called on a table with existing data:
- Clock table is created but **empty** (no backfill occurs)
- `crsql_changes` returns 0 rows for pre-existing data
- `db_version` stays at 0 instead of incrementing

### Expected Behavior
- Clock entries created for each existing row
- `col_version = 1`, `db_version = 1` for all backfilled entries
- `crsql_changes` returns backfilled data
- Re-applying `crsql_as_crr()` is idempotent (no duplicates)

## Files to Modify
- `zig/src/as_crr.zig`
- `zig/src/backfill.zig` (new, if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] `bash zig/harness/test-backfill.sh` passes all 12 tests
- [ ] No regression in `make -C zig test-parity`

### Test Cases to Pass (from test-backfill.sh)
1. Empty table baseline (PASS - already works)
2. Single row → 1 clock entry
3. Multiple rows (5) → 5 clock entries
4. col_version = 1 for backfilled rows
5. db_version = 1 for backfilled rows
6. crsql_changes returns backfilled data
7. Backfilled values match original data
8. Re-applying crsql_as_crr() idempotency
9. Multiple non-PK columns handling
10. db_version = 1 after backfill
11. Insert after backfill increments db_version to 2
12. Compound primary key backfill

## Reproducible Command
```bash
# Run backfill tests (currently 1 PASS, 11 FAIL)
bash zig/harness/test-backfill.sh

# Current output:
# Backfill Tests Summary: 1 passed, 11 failed
```

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Test harness created: `zig/harness/test-backfill.sh` (TASK-096)
- Tests wired into `zig/harness/test-parity.sh`
- Current status: 1 PASS (empty table), 11 FAIL (backfill not implemented)

## Completion Notes
