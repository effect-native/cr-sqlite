# TASK-089: Oracle Parity — API surface completeness

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
- Rust extension entry: `core/rs/core/src/lib.rs`
- Zig extension entry: `zig/src/crsqlite.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that Zig exposes the same SQL API surface as Rust/C. Use `pragma_function_list` and `pragma_module_list` to enumerate all registered functions and virtual table modules, then compare.

This is an **oracle test**: Rust/C is the golden master. Any function or module present in Rust/C but missing from Zig is a gap.

## Files to Modify
- `zig/harness/test-api-surface.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test extracts function list from Rust/C extension: `SELECT name FROM pragma_function_list WHERE name LIKE 'crsql%' ORDER BY name`
- [ ] Test extracts function list from Zig extension using same query.
- [ ] Test extracts module list from both: `SELECT name FROM pragma_module_list WHERE name LIKE 'crsql%' OR name = 'clset' ORDER BY name`
- [ ] Test fails if Rust/C has functions/modules not present in Zig.
- [ ] Test documents which functions are intentionally excluded (if any) with rationale.
- [ ] Functions to verify include (at minimum):
  - `crsql_as_crr`, `crsql_as_table`
  - `crsql_begin_alter`, `crsql_commit_alter`
  - `crsql_changes`, `crsql_tracked_peers`
  - `crsql_db_version`, `crsql_next_db_version`
  - `crsql_site_id`, `crsql_siteid` (alias)
  - `crsql_finalize`
  - `crsql_fract_key_between`
  - `crsql_pack_columns`, `crsql_rows_impacted`
  - `crsql_automigrate` (if implemented)
  - `crsql_config_get`, `crsql_config_set` (if implemented)

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

## Completion Notes
