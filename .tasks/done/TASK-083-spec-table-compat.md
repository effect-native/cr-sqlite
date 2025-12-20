# TASK-083: Spec (RGRTDD) — Table compatibility checks for `crsql_as_crr`

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
- Rust reference gating: `core/rs/core/src/tableinfo.rs` (is_table_compatible)
- Rust CRR creation: `core/rs/core/src/create_crr.rs`
- Zig CRR creation: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define (in tests) what tables are eligible to become CRRs.

This is important for real systems because invalid tables can silently produce incorrect triggers/merge behavior.

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-table-compat.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Tests fail on current Zig (it upgrades without checks).
- [x] Tests cover rejections that match Rust behavior:
  1. **No primary key**: conversion fails.
  2. **Unique index besides PK**: conversion fails.
  3. **AUTOINCREMENT present**: conversion fails.
  4. **Checked foreign keys**: conversion fails.
  5. **NOT NULL without DEFAULT**: conversion fails.
- [x] Tests assert error is visible (non-OK return / error message contains a stable substring).

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Created `zig/harness/test-table-compat.sh` with 12 tests covering:
  - Test 1: Table without PRIMARY KEY fails
  - Test 2: Table with UNIQUE index (besides PK) fails
  - Test 3: Table with AUTOINCREMENT fails
  - Test 4: Table with checked foreign keys fails
  - Test 5: NOT NULL column without DEFAULT fails
  - Test 6: Valid table succeeds (positive case)
  - Test 7: Table with NOT NULL + DEFAULT succeeds
  - Test 8: Table with compound primary key succeeds
  - Test 9: Already a CRR (idempotent - second call succeeds)
  - Test 10: Non-existent table fails gracefully
  - Test 11: Nullable primary key fails
  - Test 12: UNIQUE constraint via separate CREATE UNIQUE INDEX fails
- Wired test into `zig/harness/test-parity.sh`
- Ran test suite: **5 PASSED, 7 FAILED** (RED phase as expected)

## Completion Notes
### Test Results Summary (2025-12-20)

**Tests Created:** 12

**Tests Passing:** 5
- Test 6: Valid table succeeds
- Test 7: Table with NOT NULL + DEFAULT succeeds
- Test 8: Table with compound primary key succeeds
- Test 9: Already a CRR (idempotent)
- Test 10: Non-existent table fails gracefully

**Tests Failing (RED phase - expected):** 7
- Test 1: Table without PRIMARY KEY - Zig accepts (should reject)
- Test 2: Table with UNIQUE index - Zig accepts (should reject)
- Test 3: Table with AUTOINCREMENT - Zig accepts (should reject)
- Test 4: Table with foreign keys - Zig accepts (should reject)
- Test 5: NOT NULL without DEFAULT - Zig accepts (should reject)
- Test 11: Nullable primary key - Zig accepts (should reject)
- Test 12: UNIQUE INDEX via CREATE INDEX - Zig accepts (should reject)

**Conclusion:**
The Zig implementation of `crsql_as_crr` does not currently perform table compatibility validation. Invalid tables are silently accepted. The Rust reference implementation (`is_table_compatible` in `core/rs/core/src/tableinfo.rs`) validates all these cases.

**Next Steps:**
Create TASK-084 to implement `is_table_compatible` checks in the Zig extension.
