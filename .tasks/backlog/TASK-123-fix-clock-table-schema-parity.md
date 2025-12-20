# TASK-123: Fix clock table schema parity with oracle

## Status
- [ ] Planned

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Divergence documented in: `.tasks/done/TASK-074-cross-impl-compat-expanded.md`
- Test: `zig/harness/test-oracle-parity.sh` (Test 2)
- Zig clock table creation: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The Zig `__crsql_clock` table schema differs from the Rust/C oracle in two ways:

1. **Column naming**: Zig uses `pk` column, Rust/C uses `key` column
2. **Index**: Rust/C has an index on the clock table, Zig has 0 indexes
3. **Strict**: Rust/C uses STRICT tables, Zig does not

These differences may cause cross-implementation database sharing issues.

## Files to Modify
- `zig/src/as_crr.zig` - clock table creation

## Acceptance Criteria
- [ ] `__crsql_clock` table schema matches oracle exactly
- [ ] Column names match (change `pk` to `key` - careful with pks table relation!)
- [ ] Index structure matches oracle (add `_dbv_idx` on `db_version`)
- [ ] Strict mode enabled
- [ ] `zig/harness/test-oracle-parity.sh` Test 2 passes
