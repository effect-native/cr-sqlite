# TASK-100: Decide ALTER TABLE new-column clock semantics (backfill vs lazy)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete (2025-12-20)

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
- [x] A written decision exists in this task's Completion Notes: **Eager backfill** or **Lazy materialize**.
- [x] Decision includes:
  - the intended meaning of `__crsql_clock` entries
  - impact on `crsql_changes` payload size and db_version evolution
  - expected behavior for `ADD COLUMN DEFAULT ...` on existing rows
- [ ] `zig/harness/test-alter-parity.sh` assertions reflect the decision (no "failing-by-design"). → TASK-101
- [x] `research/zig-cr/92-gap-backlog.md` updated to link to follow-up implementation task(s).

## Progress Log
### 2025-12-20
- Observed divergence via `zig/harness/test-alter-parity.sh`:
  - Rust/sqlite-cr: no clock rows for new column until UPDATE
  - Zig: backfills clock rows on ADD COLUMN
- Analyzed Rust source: `core/rs/core/src/alter.rs` and `core/rs/core/src/backfill.rs`
- Key finding: Rust `compact_post_alter` does NOT call `backfill_table` — it only compacts/deletes
- Key finding: Rust `backfill_missing_columns` is only called during `crsql_as_crr`, NOT during `crsql_commit_alter`

## Completion Notes

### Decision: **LAZY MATERIALIZE** (match Rust/C oracle behavior)

### Recommendation

Zig should adopt **lazy materialize** semantics for `ADD COLUMN`, matching the Rust/C oracle:
- `crsql_commit_alter` should NOT create clock entries for newly added columns
- Clock entries should only be created when the column is explicitly written (INSERT or UPDATE)

### Justification

#### 1. Intended Meaning of `__crsql_clock` Entries

A clock entry represents a **write event** — a deliberate modification to a specific cell (row × column). The clock captures:
- `col_version`: How many times this cell has been written
- `db_version`: Which logical database version this write occurred at
- `site_id`: Which node performed the write

**Schema changes are not writes.** Adding a column doesn't represent user intent to set a value; it's a structural change. The column's initial value (NULL or DEFAULT) exists by virtue of the schema definition, not because any user wrote that value.

Creating clock entries for schema changes would:
- Conflate schema evolution with data modification
- Create "phantom writes" that no user requested
- Generate misleading conflict history (col_version=1 for values no one explicitly set)

#### 2. Impact on `crsql_changes` Payload Size and `db_version`

**Eager backfill (current Zig behavior):**
- `ADD COLUMN` on a table with N rows creates N new clock entries
- `crsql_changes` returns N extra change records (value=NULL/DEFAULT for each row)
- `db_version` advances once (via `crsql_db_version()`)
- Sync payload: O(N) extra records per schema migration
- For a 1M row table, this means 1M extra change records per new column!

**Lazy materialize (Rust/C oracle behavior):**
- `ADD COLUMN` creates 0 clock entries
- `crsql_changes` returns nothing for the new column until explicit writes
- `db_version` does not advance for schema-only changes
- Sync payload: O(0) extra records for schema migration
- Nodes receiving the same schema change apply it locally; no re-sync needed

The lazy approach aligns with the principle stated in Rust `backfill.rs:100-104`:
> "We do not grab nextdbversion on migration. The idea is that other nodes will apply the same migration in the future so if they have already seen this node up to the current db version then the migration will place them into the correct state. No need to re-sync post migration."

#### 3. Expected Behavior for `ADD COLUMN DEFAULT ...`

**Scenario:** `ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active'`

- **Eager (Zig):** Creates N clock entries with `value='active'`, `col_version=1`
- **Lazy (Rust/C):** Creates 0 clock entries

**Why lazy is correct:**
- Every node running the same migration gets `status='active'` for existing rows
- No sync is needed — the schema migration IS the write
- If Node A later sets `status='inactive'` for row 1, THEN a clock entry is created
- Node B receives the change, sees `col_version=1` > 0 (local has no entry), accepts it

**Why eager is problematic:**
- Node A creates N clock entries on ALTER
- Node B receives schema change, also creates N clock entries locally
- Both have `col_version=1` — no conflict, but redundant sync traffic
- Or worse: if db_versions differ, may create spurious conflicts

#### 4. Edge Cases

**New row inserted after ADD COLUMN:**
- INSERT trigger creates clock entry for the new column (value from DEFAULT or explicit)
- This is a real write, so clock entry is appropriate

**UPDATE to new column on existing row:**
- UPDATE trigger creates clock entry for the column
- `col_version=1` (first write to this cell)
- This is correct: the first explicit write is version 1

**Row existed before ALTER, never updated:**
- No clock entry for the new column
- `crsql_changes` does not return this column for this row
- Other nodes apply the same ALTER and have the same state
- No sync needed

### Follow-up Implementation Task

TASK-101 (`impl-alter-add-column-no-backfill.md`) should modify `zig/src/schema_alter.zig`:
- Remove `backfillNewColumns(db, table_name_ptr)` call from `crsqlCommitAlterFunc`
- Or: Only call backfill for rows that didn't exist before (i.e., rows missing from `__crsql_pks`)

The simpler approach is to remove the backfill entirely from `commit_alter`, matching Rust/C exactly.
