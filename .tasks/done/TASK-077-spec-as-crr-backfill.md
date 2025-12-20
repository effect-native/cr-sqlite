# TASK-077: Spec (RGRTDD) — `crsql_as_crr` backfills existing rows

## Status
- [x] Planned
- [x] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(completed by TASK-096)

## Parent Docs / Cross-links
- Rust reference: `core/rs/core/src/create_crr.rs`, `core/rs/core/src/backfill.rs`
- Rust integration tests: `core/rs/integration_check/src/t/backfill.rs`
- Zig implementation: `zig/src/as_crr.zig`
- Zig parity tests: `zig/harness/test-parity.sh`
- **Test harness**: `zig/harness/test-backfill.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Implementation task: `.tasks/backlog/TASK-078-impl-as-crr-backfill.md`

## Description
Define the required behavior when upgrading a pre-populated table to a CRR.

In real systems, schema conversion often happens after data exists (migrations, importing from legacy DBs).

This is a **spec/tests-only** task.

## Files to Modify
- ~~`zig/harness/test-as-crr-backfill.sh` (new)~~ → Created as `zig/harness/test-backfill.sh`
- `zig/harness/test-parity.sh` (wire into suite) ✓
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Test fails on current Zig (currently it only creates schema/triggers).
- [x] Test asserts at least:
  1. If a table already contains rows, after `SELECT crsql_as_crr('t')`:
     - `t__crsql_pks` contains an entry per row.
     - `t__crsql_clock` contains entries for each non-PK column per row; and if no non-PK columns exist, it contains sentinel (`'-1'`) entries.
  2. Backfill is idempotent: calling `crsql_as_crr` twice does not duplicate clock/pk entries.
  3. Backfill does not rewrite rows already present in `__crsql_pks`/`__crsql_clock`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Spec fulfilled by TASK-096 which created `zig/harness/test-backfill.sh`
- 12 test cases covering all acceptance criteria
- Tests wired into `zig/harness/test-parity.sh`
- Current results: 1 PASS, 11 FAIL (as expected - backfill not implemented)

## Completion Notes
**Completed: 2025-12-20**

Spec fulfilled by TASK-096. Test harness created at `zig/harness/test-backfill.sh` with 12 test cases covering:
- Empty table baseline
- Single/multiple row backfill
- col_version/db_version verification
- crsql_changes vtab integration
- Idempotency (re-applying crsql_as_crr)
- Multiple non-PK columns
- Compound primary keys

Implementation work tracked in TASK-078.
