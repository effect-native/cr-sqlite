# TASK-069: Wire scratchpads for realistic demos

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
low

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: `.wishes/scratchpad.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (add a new section under Gaps)

## Description
Wire up the existing scratchpad projects so they are runnable and demonstrate realistic scenarios:

- `scratch/browser-scratchpad`: minimal bun+react app demonstrating browser multi-tab DB.
- `scratch/bun-scratchpad`: minimal bun script using `bun:sqlite`.

The original wish also asked for an Effect+SQL Bun scratchpad. That is **TypeScript-heavy** and (per repo rules) must live in the `effect-native/` submodule and be spec-gated.

Track that separately as a Tom-blocked wish:
- `.wishes/blocked-on-tom/effect-bun-scratchpad.md`

## Files to Modify
- `scratch/browser-scratchpad/*`
- `scratch/bun-scratchpad/*`
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Each scratchpad has a single documented command to run.
- [x] Browser scratchpad demonstrates cross-tab read/write visibility.
- [x] Bun scratchpad demonstrates CR-SQLite usage with `bun:sqlite`.
- [x] No TypeScript spec-gate violations (Effect scratchpad tracked separately as blocked).

## Progress Log
### 2025-12-17
- Task created from `.wishes/scratchpad.md` during "update tasks".

### 2025-12-16
- Implemented bun-scratchpad:
  - Uses `Database.setCustomSQLite()` to load extension-enabled libsqlite3
  - Loads Zig-built CR-SQLite extension via `db.loadExtension()`
  - Demonstrates CRR table creation, CRUD operations, db_version tracking
  - Run: `bun run scratch/bun-scratchpad/index.ts`
- Implemented browser-scratchpad:
  - Serves CR-SQLite WASM files from `zig/browser-dist/`
  - React app with DbClient connecting to SharedWorker coordinator
  - Shows provider/client roles, db_version, cross-tab item sync
  - Run: `bun --hot scratch/browser-scratchpad/src/index.ts`
- Updated README.md files with run instructions and architecture docs

## Completion Notes
### 2025-12-16

**Bun Scratchpad** (`scratch/bun-scratchpad/`)
- Run: `bun run scratch/bun-scratchpad/index.ts`
- Key discovery: `bun:sqlite` built-in doesn't support extension loading, so we use `Database.setCustomSQLite()` with the libsqlite3 from `effect-native/packages-native/libsqlite/`
- Uses Zig-built extension (`crsqlite-zig-*.dylib`) which has standard `sqlite3_extension_init` entry point
- Demonstrates full CR-SQLite workflow: CRR creation, CRUD, db_version tracking, crsql_changes, site_id

**Browser Scratchpad** (`scratch/browser-scratchpad/`)
- Run: `bun --hot scratch/browser-scratchpad/src/index.ts`
- Serves WASM files from `zig/browser-dist/` at `/crsql-multitab.js`, `/coordinator.js`, `/provider.js`, `/sql-wasm.wasm`
- React app connects via DbClient → SharedWorker (coordinator) → Provider Worker (SQLite WASM)
- Shows provider election (first tab owns DB), cross-tab sync via 1s polling, db_version updates
- Note: The provider.js currently loads sql.js from CDN, not the local CR-SQLite WASM build. Full CR-SQLite WASM integration is pending.
