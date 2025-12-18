# TASK-077: Spec (RGRTDD) — `crsql_as_crr` backfills existing rows

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
- Rust reference: `core/rs/core/src/create_crr.rs`, `core/rs/core/src/backfill.rs`
- Rust integration tests: `core/rs/integration_check/src/t/backfill.rs`
- Zig implementation: `zig/src/as_crr.zig`
- Zig parity tests: `zig/harness/test-parity.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define the required behavior when upgrading a pre-populated table to a CRR.

In real systems, schema conversion often happens after data exists (migrations, importing from legacy DBs).

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-as-crr-backfill.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test fails on current Zig (currently it only creates schema/triggers).
- [ ] Test asserts at least:
  1. If a table already contains rows, after `SELECT crsql_as_crr('t')`:
     - `t__crsql_pks` contains an entry per row.
     - `t__crsql_clock` contains entries for each non-PK column per row; and if no non-PK columns exist, it contains sentinel (`'-1'`) entries.
  2. Backfill is idempotent: calling `crsql_as_crr` twice does not duplicate clock/pk entries.
  3. Backfill does not rewrite rows already present in `__crsql_pks`/`__crsql_clock`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
