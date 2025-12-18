# TASK-086: Implement (RGRTDD) — `crsql_config_get/set` in Zig

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
- [ ] `zig/harness/test-config.sh` passes.
- [ ] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

## Completion Notes
