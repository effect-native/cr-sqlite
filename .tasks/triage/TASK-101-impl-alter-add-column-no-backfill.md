# TASK-101: Align Zig ALTER ADD COLUMN clocks with oracle (no eager backfill)

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
- Oracle parity test: `zig/harness/test-alter-parity.sh`
- Zig alter implementation: `zig/src/schema_alter.zig`
- Rust/C alter implementation (reference): `core/rs/core/src/alter.rs`
- sqlite-cr wrapper: `nix run github:subtleGradient/sqlite-cr -- ...`
- Origin task: `.tasks/active/TASK-094-alter-table-history-preservation.md`
- Decision task: `.tasks/backlog/TASK-100-decide-alter-new-column-clock-semantics.md`

## Description
After TASK-094, Zig diverges from the oracle on `ALTER TABLE ... ADD COLUMN`:

- Zig eagerly backfills `__crsql_clock` entries for the new column.
- Oracle (sqlite-cr / Rust/C) does not create clock rows for new columns until the column is explicitly written.

This task implements the **oracle-matching behavior** in Zig (assuming TASK-100 chooses “lazy materialize”), and updates the parity test so it becomes fully green.

## Files to Modify
- `zig/src/schema_alter.zig`
- `zig/harness/test-alter-parity.sh`
- `zig/harness/test-parity.sh`

## Acceptance Criteria
- [ ] `zig/harness/test-alter-parity.sh` passes with **0 failures**.
- [ ] After `ADD COLUMN` (nullable) with existing rows:
  - [ ] Zig does **not** create `__crsql_clock` rows for the new column.
  - [ ] Existing column clock rows are unchanged.
- [ ] After `ADD COLUMN ... DEFAULT ...` with existing rows:
  - [ ] Zig does **not** create `__crsql_clock` rows for the new column.
  - [ ] Later explicit `UPDATE` to the new column creates a clock row with `col_version = 1`.
- [ ] After sequential alters (add column then add column then drop column):
  - [ ] Zig clock column set matches oracle when columns are never written.
- [ ] Large-table case (1000+ rows) does not backfill clock rows.

## Progress Log
### 2025-12-20
- Evidence from `zig/harness/test-alter-parity.sh` shows Zig eager-backfill causes:
  - extra clock rows after `ADD COLUMN`
  - different `col_version` after first UPDATE to new column

## Completion Notes
