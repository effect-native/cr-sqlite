# TASK-213 — Browser Provider Loads Local CR-SQLite WASM (no CDN sql.js)

## Goal
Ensure the browser provider uses the local bundled CR-SQLite WASM (`zig/browser-dist/sql-wasm.js` + `sql-wasm.wasm`) instead of loading `sql.js` from cdnjs.

## Status
- State: done
- Priority: HIGH
- Created: 2025-12-25
- Completed: 2025-12-25

## Evidence
- Current `provider.js` loads from cdnjs:
  - `zig/browser-dist/provider.js`
  - `zig/browser-test/fixtures/provider.js`
  - `zig/browser-test/src/provider/worker.ts`
- Scratchpad note flags this as pending:
  - `.tasks/done/TASK-069-wire-scratchpads.md`

## Files to Modify
- `zig/browser-test/src/provider/worker.ts`
- `zig/browser-test/fixtures/provider.js` (rebuilt output)
- `zig/browser-dist/provider.js` (rebuilt output)
- Potentially `zig/browser-dist/README.md` (if it documents the old behavior)

## Acceptance Criteria
1. [x] No `https://cdnjs.cloudflare.com/ajax/libs/sql.js/...` references remain in provider artifacts
2. [x] Provider successfully initializes from `sql-wasm.js` and locates sibling `sql-wasm.wasm`
3. [x] `make -C zig test-browser` passes (30/30 tests)
4. [ ] `bun --hot scratch/browser-scratchpad/src/index.ts` works with no external CDN dependency (not tested)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Implemented sql.js-compatible wrapper around raw Emscripten module.
- 2025-12-25: Fixed BigInt serialization for sqlite3_deserialize.
- 2025-12-25: Fixed race condition in handleOpen (made idempotent).
- 2025-12-25: All 30 browser tests passing.

## Completion Notes

### Summary of Changes

The browser provider worker (`zig/browser-test/src/provider/worker.ts`) was loading sql.js from cdnjs CDN. This has been replaced with local loading of our bundled CR-SQLite WASM.

### Key Implementation Details

1. **sql.js-compatible wrapper** (~300 lines)
   - Created `CrSqliteDatabase` class that wraps the raw Emscripten SQLite module
   - Implements sql.js interface: `run()`, `exec()`, `export()`, `close()`
   - Uses raw SQLite C APIs: `sqlite3_prepare_v2`, `sqlite3_step`, `sqlite3_finalize`, etc.

2. **Local WASM loading**
   - Uses `resolveSiblingUrl()` to find `sql-wasm.js` relative to worker script location
   - Uses `initCrSqlite()` (our WASM init function) instead of `initSqlJs()` from CDN

3. **Bug fixes discovered during testing**
   - `sqlite3_deserialize` expects BigInt for size parameters (64-bit integers)
   - `handleOpen` was not idempotent - re-opening the same DB would reload from OPFS and lose in-memory changes
   - Fixed by returning early if DB is already open with the same name

### Files Changed
- `zig/browser-test/src/provider/worker.ts` - Main implementation
- `zig/browser-test/fixtures/provider.js` - Built output
- `zig/browser-dist/provider.js` - Distribution output
- `zig/browser-test/tests/multitab-basic.spec.ts` - Cleaned up debug logging

### Test Results
```
30 passed (15.2s)
```

All browser tests pass including:
- Multi-tab coordination (6 tests)
- OPFS persistence (2 tests)
- CR-SQLite extension (3 tests)
- FTS5 (2 tests)
- JSON functions (4 tests)
- sqlite-vec (6 tests)
- Basic SQLite WASM (7 tests)
