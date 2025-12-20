# TASK-101: Align Zig ALTER ADD COLUMN clocks with oracle (no eager backfill)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(completed)

## Parent Docs / Cross-links
- Oracle parity test: `zig/harness/test-alter-parity.sh`
- Zig alter implementation: `zig/src/schema_alter.zig`
- Rust/C alter implementation (reference): `core/rs/core/src/alter.rs`
- sqlite-cr wrapper: `nix run github:subtleGradient/sqlite-cr -- ...`
- Origin task: `.tasks/active/TASK-094-alter-table-history-preservation.md`
- Decision task: `.tasks/backlog/TASK-100-decide-alter-new-column-clock-semantics.md`

## Description
After TASK-094, Zig diverged from the oracle on `ALTER TABLE ... ADD COLUMN`:

- Zig eagerly backfilled `__crsql_clock` entries for the new column.
- Oracle (sqlite-cr / Rust/C) does not create clock rows for new columns until the column is explicitly written.

This task implements the **oracle-matching behavior** in Zig (LAZY MATERIALIZE semantics), and the parity test is now fully green.

## Files to Modify
- [x] `zig/src/schema_alter.zig`
- [x] `zig/harness/test-alter-parity.sh` (no changes needed - already correct)
- [ ] `zig/harness/test-parity.sh` (no changes needed)

## Acceptance Criteria
- [x] `zig/harness/test-alter-parity.sh` passes with **0 failures**.
- [x] After `ADD COLUMN` (nullable) with existing rows:
  - [x] Zig does **not** create `__crsql_clock` rows for the new column.
  - [x] Existing column clock rows are unchanged.
- [x] After `ADD COLUMN ... DEFAULT ...` with existing rows:
  - [x] Zig does **not** create `__crsql_clock` rows for the new column.
  - [x] Later explicit `UPDATE` to the new column creates a clock row with `col_version = 1`.
- [x] After sequential alters (add column then add column then drop column):
  - [x] Zig clock column set matches oracle when columns are never written.
- [x] Large-table case (1000+ rows) does not backfill clock rows.

## Progress Log
### 2025-12-20
- Evidence from `zig/harness/test-alter-parity.sh` shows Zig eager-backfill causes:
  - extra clock rows after `ADD COLUMN`
  - different `col_version` after first UPDATE to new column

### 2025-12-20 (completion)
- Removed `backfillNewColumns()` call from `crsqlCommitAlterFunc` in `zig/src/schema_alter.zig`
- Updated docstring to document LAZY MATERIALIZE semantics
- Rebuilt Zig extension
- All 19 parity tests now pass with 0 failures

## Completion Notes
### 2025-12-20

**Change made**: Removed the call to `backfillNewColumns()` from `crsqlCommitAlterFunc` in `zig/src/schema_alter.zig`.

**Rationale**: Zig now uses LAZY MATERIALIZE semantics for ALTER ADD COLUMN, matching the Rust/C oracle behavior. Clock entries are only created when a column is explicitly written (via UPDATE or INSERT), not eagerly when the column is added.

**Test results**: `bash zig/harness/test-alter-parity.sh` - 19 PASSED, 0 FAILED

**Files changed**:
- `zig/src/schema_alter.zig` - Removed backfill call, updated docstring
