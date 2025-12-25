# TASK-213 — Browser Provider Loads Local CR-SQLite WASM (no CDN sql.js)

## Goal
Ensure the browser provider uses the local bundled CR-SQLite WASM (`zig/browser-dist/sql-wasm.js` + `sql-wasm.wasm`) instead of loading `sql.js` from cdnjs.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

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
1. [ ] No `https://cdnjs.cloudflare.com/ajax/libs/sql.js/...` references remain in provider artifacts
2. [ ] Provider successfully initializes from `sql-wasm.js` and locates sibling `sql-wasm.wasm`
3. [ ] `make -C zig test-browser` passes
4. [ ] `bun --hot scratch/browser-scratchpad/src/index.ts` works with no external CDN dependency

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
