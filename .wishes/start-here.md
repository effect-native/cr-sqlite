# start-here

If you're asking "what's left?" start here:

- Canonical status + remaining gaps: `research/zig-cr/92-gap-backlog.md`
- Task queue (what to run next): `.tasks/{backlog,active,done}/`
- Zig implementation: `zig/`
- TS specs + packages:
  - Specs: `effect-native/.specs/`
  - Packages: `effect-native/packages-native/`

## Current Status (2025-12-17)

**MVP is complete:**
- Zig parity tests: 52/52 passing
- Browser tests: 30/30 passing (includes sqlite-vec, FTS5, JSONB)
- Mesh tests: 81/81 passing
- TypeScript: clean

**Scratchpad demos work:**
- `bun run scratch/bun-scratchpad/index.ts` — CR-SQLite with bun:sqlite
- `bun --hot scratch/browser-scratchpad/src/index.ts` — React multi-tab sync

**Size is healthy:**
- Zig crsqlite is 105.72% of SQLite (~103KB overhead)

## Remaining Backlog

**Empty.** All planned work complete. Upstream zig-sqlite tasks cancelled per Tom (2025-12-17).

Only remaining gap: Effect-TS scratchpad (spec-gated) — see `.wishes/blocked-on-tom/effect-bun-scratchpad.md`

## Rules of the game (thing-golf)

Prefer fewer, sharper "Things":
- One task card owns one named delta.
- Each task card lists a tight `Files to Modify` set.
- Each task card links to its parent doc/spec and the parent links back.
