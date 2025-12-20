# TASK-084: Implement (RGRTDD) — Table compatibility checks in Zig

## Status
- [ ] Planned
- [ ] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
Claude (TASK-084 delegate)

## Parent Docs / Cross-links
- Spec task: `.tasks/done/TASK-083-spec-table-compat.md` (completed 2025-12-20)
- Rust reference: `core/rs/core/src/tableinfo.rs`
- Zig table info extraction: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement Rust-equivalent table compatibility checks in Zig before creating CRR metadata.

Expected approach:
- Query SQLite pragmas (`table_info`, `index_list`, `foreign_key_list`, etc.)
- Enforce the same constraints as Rust.
- Return useful errors.

## Files to Modify
- `zig/src/as_crr.zig` — modified to call compatibility check before CRR creation
- `zig/src/table_compat.zig` — new file with validation logic

## Acceptance Criteria
- [x] `zig/harness/test-table-compat.sh` passes (all 12 tests).
- [x] No regression in parity tests (`bash zig/harness/test-parity.sh`).

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Created `zig/src/table_compat.zig` with table compatibility validation logic.
- Modified `zig/src/as_crr.zig` to:
  - Import `table_compat.zig`
  - Add `tableExists()` check for non-existent tables
  - Add `isAlreadyCrr()` check for idempotency
  - Call `table_compat.checkTableCompatibility()` before creating CRR infrastructure
- Implemented validation checks:
  1. AUTOINCREMENT (checked first for proper error priority)
  2. Primary key existence
  3. Primary key nullability (with special handling for `INTEGER PRIMARY KEY`)
  4. UNIQUE constraints besides PK
  5. Foreign key constraints
  6. NOT NULL columns without DEFAULT values
- Special handling for `INTEGER PRIMARY KEY` which is implicitly NOT NULL even without explicit declaration
- All 12 tests pass in `test-table-compat.sh`
- No regressions in parity tests (pre-existing failures in clset_vtab.zig tests are unrelated)

## Completion Notes
Implementation complete. All 12 table compatibility tests pass:
- Test 1: Table without PRIMARY KEY fails ✓
- Test 2: Table with UNIQUE index (besides PK) fails ✓
- Test 3: Table with AUTOINCREMENT fails ✓
- Test 4: Table with checked foreign keys fails ✓
- Test 5: NOT NULL column without DEFAULT fails ✓
- Test 6: Valid table succeeds ✓
- Test 7: Table with NOT NULL + DEFAULT succeeds ✓
- Test 8: Table with compound primary key succeeds ✓
- Test 9: Already a CRR (idempotent) ✓
- Test 10: Non-existent table fails gracefully ✓
- Test 11: Nullable primary key fails ✓
- Test 12: UNIQUE INDEX (via CREATE UNIQUE INDEX) fails ✓

Files created/modified:
- `zig/src/table_compat.zig` (new)
- `zig/src/as_crr.zig` (modified)

Date: 2025-12-20
