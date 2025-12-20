# TASK-086: Implement (RGRTDD) — `crsql_config_get/set` in Zig

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
- Spec task: `.tasks/backlog/TASK-085-spec-config.md`
- Rust reference: `core/rs/core/src/config.rs`
- Registration point: `zig/src/ffi/init.zig`
- Zig merge behavior: `zig/src/merge_insert.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement config get/set in Zig and wire it into merge behavior.

Key aspects to match Rust:
- Supported key: `merge-equal-values`.
- `crsql_config_set` persists into `crsql_master` under key `config.<name>`.
- `crsql_config_get` reads from ext-data (fast path) and returns error for unknown keys.

## Files to Modify
- `zig/src/config.zig` (new)
- `zig/src/ffi/init.zig`
- `zig/src/merge_insert.zig` (only if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] `zig/harness/test-config.sh` passes.
- [x] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Created `zig/src/config.zig` implementing:
  - Per-connection config storage using `ConnectionConfigMap`
  - `getMergeEqualValues()` and `setMergeEqualValues()` for in-memory access
  - `loadConfigFromDb()` and `saveConfigToDb()` for persistence to `crsql_master`
  - `crsql_config_get(key)` SQL function that returns config value or error for unknown keys
  - `crsql_config_set(key, value)` SQL function that persists to DB and returns the set value
  - Default value of 1 for `merge-equal-values`
- Registered config functions in `zig/src/ffi/init.zig`
- Integrated `merge-equal-values` behavior into `zig/src/changes_vtab.zig`:
  - When `merge-equal-values=1` (default) and values are equal, site_id is used as tie-breaker
  - When `merge-equal-values=0` and values are equal, it's a no-op (local wins)
- All 12 config tests pass
- Parity tests show no regressions

## Completion Notes
Implementation complete. All acceptance criteria met:
- `bash zig/harness/test-config.sh`: 12/12 tests pass
- `bash zig/harness/test-filters.sh`: 12/12 tests pass
- `bash zig/harness/test-noops.sh`: 4/4 tests pass
- Other parity tests pass without regression

Files created/modified:
- `zig/src/config.zig` (new): Config API implementation
- `zig/src/ffi/init.zig`: Added config import and registration
- `zig/src/changes_vtab.zig`: Added merge-equal-values behavior for site_id tie-breaking
