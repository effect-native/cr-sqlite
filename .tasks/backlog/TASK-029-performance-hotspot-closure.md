# TASK-029: Performance Hotspot Closure (schema/data version + persistent prepares)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md` ("Remaining Gaps → Performance Optimizations")
- Hotspot analysis: `research/zig-cr/11-performance-hotspots.md`
- Likely code hotspots: `zig/src/stmt_cache.zig`, `zig/src/changes_vtab.zig`, `zig/src/ffi/api.zig`

## Description
Close the remaining post-MVP performance gaps that are explicitly tracked but not yet implemented:

1) `PRAGMA schema_version` keyed invalidation caching (avoid unnecessary union rebuild / stmt recreation)
2) `PRAGMA data_version` check amortization (avoid polling/pragma spam on hot loops)
3) Prefer `sqlite3_prepare_v3(..., SQLITE_PREPARE_PERSISTENT)` for long-lived statements

This task is intentionally narrow: improve hot-path behavior without changing query semantics.

## Files to Modify
- `zig/src/stmt_cache.zig`
- `zig/src/changes_vtab.zig`
- `zig/src/ffi/api.zig` (if prepare_v3 / flags wiring needed)
- `research/zig-cr/92-gap-backlog.md` (check off items + add brief notes)

## Acceptance Criteria
- [ ] `stmt_cache` exposes an explicit "schema version changed" signal that callers can use to invalidate cached derived artifacts.
- [ ] `changes_vtab` avoids rebuilding or repreparing union statements when schema_version unchanged.
- [ ] `PRAGMA data_version` checks are amortized (e.g. once per transaction / once per cursor scan loop) with no correctness regressions.
- [ ] If supported by the SQLite target, long-lived statements are prepared using `sqlite3_prepare_v3` with `SQLITE_PREPARE_PERSISTENT`.
- [ ] `make test-unit` and `make test-parity` pass.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started

## Completion Notes
[fill in when done]
