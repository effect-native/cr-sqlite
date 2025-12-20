# TASK-100: Decide ALTER TABLE new-column clock semantics (backfill vs lazy)

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
- Oracle parity test (current evidence): `zig/harness/test-alter-parity.sh`
- Zig alter implementation: `zig/src/schema_alter.zig`
- Rust/C alter implementation (reference): `core/rs/core/src/alter.rs`
- sqlite-cr wrapper (oracle runtime): `nix run github:subtleGradient/sqlite-cr -- ...`
- Origin task: `.tasks/active/TASK-094-alter-table-history-preservation.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
TASK-094 surfaced an **ALTER TABLE semantic ambiguity**:

When a CRR table undergoes `ALTER TABLE ... ADD COLUMN` (nullable or with DEFAULT), should the system:

1) **Eager backfill** the `__crsql_clock` table with entries for the new column for *all existing rows* (so the new column becomes part of the per-row conflict history immediately), OR

2) **Lazy materialize** clock entries for the new column only when that column is explicitly written (so schema evolution does not fabricate per-row “writes”).

The current oracle (sqlite-cr / Rust/C) behavior observed in TASK-094’s test run:
- `ADD COLUMN` does **not** create clock entries for the new column.
- A later `UPDATE` to the new column creates the first clock entry with `col_version = 1`.

The current Zig behavior observed:
- `ADD COLUMN` **does** backfill clock entries for all existing rows.
- A later `UPDATE` increments `col_version` (because the row already has a clock entry).

This task is to decide which behavior is the intended contract for Zig (and by extension, what oracle parity tests should enforce).

## Files to Modify
- `research/zig-cr/92-gap-backlog.md` (record the decided contract)
- `zig/harness/test-alter-parity.sh` (make expectations match the decided contract)
- `.tasks/active/TASK-094-alter-table-history-preservation.md` (update acceptance criteria wording)

## Acceptance Criteria
- [ ] A written decision exists in this task’s Completion Notes: **Eager backfill** or **Lazy materialize**.
- [ ] Decision includes:
  - the intended meaning of `__crsql_clock` entries
  - impact on `crsql_changes` payload size and db_version evolution
  - expected behavior for `ADD COLUMN DEFAULT ...` on existing rows
- [ ] `zig/harness/test-alter-parity.sh` assertions reflect the decision (no “failing-by-design”).
- [ ] `research/zig-cr/92-gap-backlog.md` updated to link to follow-up implementation task(s).

## Progress Log
### 2025-12-20
- Observed divergence via `zig/harness/test-alter-parity.sh`:
  - Rust/sqlite-cr: no clock rows for new column until UPDATE
  - Zig: backfills clock rows on ADD COLUMN

## Completion Notes
