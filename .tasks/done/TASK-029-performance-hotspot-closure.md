# TASK-029: Performance Hotspot Closure (schema/data version + persistent prepares)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] `stmt_cache` exposes an explicit "schema version changed" signal that callers can use to invalidate cached derived artifacts.
- [x] `changes_vtab` avoids rebuilding or repreparing union statements when schema_version unchanged.
- [x] `PRAGMA data_version` checks are amortized (e.g. once per transaction / once per cursor scan loop) with no correctness regressions.
- [x] If supported by the SQLite target, long-lived statements are prepared using `sqlite3_prepare_v3` with `SQLITE_PREPARE_PERSISTENT`.
- [x] `make test-unit` and `make test-parity` pass (pre-existing rowid slab failures excluded).

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started
- Task started - implementing 3 performance optimizations
- Added `prepare_v3` wrapper with `SQLITE_PREPARE_PERSISTENT` flag to `api.zig`
- Added `schemaVersionChanged()` and `getSchemaVersion()` to `stmt_cache.zig` for invalidation signaling
- Added `checkDataVersionAmortized()` and `resetDataVersionCheck()` to `stmt_cache.zig` for per-transaction amortization
- Added `getOrPreparePersistent()` and `prepareOncePersistent()` for long-lived statements
- Added schema-version keyed table name cache to `ChangesVTab` in `changes_vtab.zig`
- Updated `changesFilter` to use schema-version keyed cache, avoiding re-query of sqlite_master when schema unchanged
- Updated `discoverTablesCached` to use `prepareOncePersistent` for persistent statement preparation
- All unit tests pass (64/64)
- Parity tests pass except for pre-existing rowid slab failures (48/52)

## Completion Notes
### 2025-12-14

**Implemented:**

1. **`PRAGMA schema_version` keyed invalidation caching** (`stmt_cache.zig`, `changes_vtab.zig`)
   - Added `schema_changed_flag` field to `StmtCache` that is set when schema version changes
   - Added `schemaVersionChanged()` method to check and consume the flag
   - Added `getSchemaVersion()` to get cached version without re-checking
   - Added schema-version keyed table name cache to `ChangesVTab` struct
   - `changesFilter` now reuses cached table names when schema_version is unchanged
   - New helper functions: `getCachedTableNames()`, `setCachedTableNames()`, `freeCachedTableNames()`, `copyTableNamesToCursor()`, `discoverTablesCachedWithInvalidation()`

2. **`PRAGMA data_version` check amortization** (`stmt_cache.zig`)
   - Added `data_version_checked_this_txn` flag to `StmtCache`
   - Added `checkDataVersionAmortized()` that only performs actual PRAGMA query once per transaction
   - Added `resetDataVersionCheck()` for clearing the flag at transaction boundaries
   - Added `getDataVersion()` to get cached value

3. **`sqlite3_prepare_v3` with `SQLITE_PREPARE_PERSISTENT`** (`api.zig`, `stmt_cache.zig`)
   - Added `prepare_v3()` wrapper to `api.zig` with fallback to `prepare_v2` if not available
   - Added `SQLITE_PREPARE_PERSISTENT`, `SQLITE_PREPARE_NORMALIZE`, `SQLITE_PREPARE_NO_VTAB` constants
   - Added `getOrPreparePersistent()` method to `StmtCache`
   - Added standalone `prepareOncePersistent()` helper function
   - Updated `checkSchemaVersion()`, `checkDataVersion()`, and `discoverTablesCached()` to use persistent prepares

**Test Results:**
- Unit tests: 64/64 PASS
- Parity tests: 48/52 (4 pre-existing rowid slab failures, not related to this task)
