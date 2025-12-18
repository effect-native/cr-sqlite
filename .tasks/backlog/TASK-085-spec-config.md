# TASK-085: Spec (RGRTDD) — `crsql_config_get/set` + merge-equal-values

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust config API: `core/rs/core/src/config.rs`
- Rust merge uses ext-data setting: `core/rs/core/src/changes_vtab_write.rs` (merge semantics)
- Zig merge logic: `zig/src/merge_insert.zig`
- Zig ext data/state: (likely `zig/src/ffi/` + site identity)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define config API behavior and its effect on merge semantics.

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-config.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Tests fail on current Zig (missing functions).
- [ ] Tests cover:
  1. `SELECT crsql_config_get('merge-equal-values')` returns an integer.
  2. `SELECT crsql_config_set('merge-equal-values', 0)` persists and `crsql_config_get` reflects it.
  3. Unknown setting names return an error.
  4. Merge semantics change is observable with a minimal scenario (must be specified based on Rust behavior; the test must encode the observed contract).

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
