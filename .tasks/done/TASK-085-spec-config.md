# TASK-085: Spec (RGRTDD) — `crsql_config_get/set` + merge-equal-values

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] Tests fail on current Zig (missing functions).
- [x] Tests cover:
  1. `SELECT crsql_config_get('merge-equal-values')` returns an integer.
  2. `SELECT crsql_config_set('merge-equal-values', 0)` persists and `crsql_config_get` reflects it.
  3. Unknown setting names return an error.
  4. Merge semantics change is observable with a minimal scenario (must be specified based on Rust behavior; the test must encode the observed contract).

## Progress Log
### 2025-12-18
- Task created from Rust/Zig gap analysis.

### 2025-12-20
- Created `zig/harness/test-config.sh` with 12 tests covering:
  - Test 1-2: Function existence (crsql_config_get, crsql_config_set)
  - Test 3: Return type is integer
  - Test 4-5: Value persistence (set/get round-trip for 0 and 1)
  - Test 6-7: Unknown setting names return error
  - Test 8: merge-equal-values=1 behavior (higher site_id wins tie-break, advances clock)
  - Test 9: merge-equal-values=0 behavior (equal values = no-op, no clock advance)
  - Test 10: Config persists across statements in same connection
  - Test 11: Default value verification
  - Test 12: crsql_config_set returns the set value
- Wired test into `zig/harness/test-parity.sh`
- Verified RED phase: all 12 tests fail with "crsql_config_get/set not implemented"

## Completion Notes
### 2025-12-20
- Spec complete. RED phase confirmed.
- 12 tests created, all failing as expected (functions not implemented in Zig)
- Test output confirms proper RED phase detection and messaging
- Ready for implementation phase (GREEN) in separate task

Test output summary:
```
PASSED:  0
FAILED:  12
SKIPPED: 0

RGRTDD RED PHASE: All tests FAILED as expected
crsql_config_get() and crsql_config_set() are not yet implemented in Zig.
```
