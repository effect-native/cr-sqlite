# TASK-096: Zig test for backfill verification

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Created by: `.tasks/active/TASK-073-compare-rust-zig-tests.md`
- Rust reference: `core/rs/integration_check/src/t/backfill.rs`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
When `crsql_as_crr()` is called on a table that already has data, it must backfill the clock table (`__crsql_clock`) with entries for all existing rows. The Rust suite explicitly tests:

1. Empty table → `crsql_as_crr()` → no errors
2. Non-empty table → `crsql_as_crr()` → clock entries created for each row
3. Reapplying `crsql_as_crr()` on already-CRR table → idempotent

Current Zig tests create CRRs but don't verify the clock table contents match expected backfill behavior.

## Files to Modify
- `zig/harness/test-backfill.sh` (new file)
- `zig/harness/test-parity.sh` (add test runner call)

## Acceptance Criteria
- [x] New test script `zig/harness/test-backfill.sh` exists
- [x] Tests cover:
  - `crsql_as_crr()` on empty table (baseline)
  - `crsql_as_crr()` on table with 1 row → verify clock entry
  - `crsql_as_crr()` on table with N rows → verify N clock entries
  - Verify col_version = 1, db_version = 1 for backfilled rows
  - Verify `crsql_changes` vtab returns backfilled data
  - Reapply `crsql_as_crr()` → no duplicates
- [x] Reproducible command: `bash zig/harness/test-backfill.sh`

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-backfill.sh
```

## Progress Log
### 2025-12-18
- Task created from TASK-073 coverage analysis

### 2025-12-20
- Created `zig/harness/test-backfill.sh` with 12 test cases
- Integrated into `zig/harness/test-parity.sh`
- Tests run successfully; 1 PASS (empty table baseline), 11 FAIL (backfill not implemented)

## Completion Notes
**Completed: 2025-12-20**

### Files Created/Modified
- `zig/harness/test-backfill.sh` (new, 269 lines)
- `zig/harness/test-parity.sh` (added backfill test runner + header comment)

### Test Coverage
12 test cases covering:
1. Empty table baseline (PASS)
2. Single row backfill
3. Multiple rows (5) backfill
4. col_version = 1 verification
5. db_version = 1 verification
6. crsql_changes vtab returns backfilled data
7. Backfilled values match original data
8. Re-applying crsql_as_crr() idempotency
9. Multiple non-PK columns
10. db_version after backfill
11. Insert after backfill increments db_version
12. Compound primary key backfill

### Current Results
- 1 passed (empty table baseline)
- 11 failed (backfill functionality not yet implemented in Zig extension)

### Reproducible Command
```bash
bash zig/harness/test-backfill.sh
```

### Output
```
Backfill Tests Summary: 1 passed, 11 failed
```

The failing tests document the expected backfill behavior that needs implementation.
