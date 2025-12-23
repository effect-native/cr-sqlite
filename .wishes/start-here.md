# start-here

If you're asking "what's left?" start here:

- Canonical status + remaining gaps: `research/zig-cr/92-gap-backlog.md`
- Task queue (what to run next): `.tasks/{backlog,active,done}/`
- Zig implementation: `zig/`
- TS specs + packages:
  - Specs: `effect-native/.specs/`
  - Packages: `effect-native/packages-native/`

## Current Status (2025-12-22)

**MVP is complete:**
- Oracle parity: 18/18 passing
- Cross-open parity: 24/24 passing
- rows_impacted: 18/18 passing
- ALTER tests: 6/6 passing
- Cross-platform compat: ALL passing
- Browser tests: 30/30 passing (includes sqlite-vec, FTS5, JSONB)
- Mesh tests: 81/81 passing
- TypeScript: clean

**Scratchpad demos work:**
- `bun run scratch/bun-scratchpad/index.ts` — CR-SQLite with bun:sqlite
- `bun --hot scratch/browser-scratchpad/src/index.ts` — React multi-tab sync

**Size is healthy:**
- Zig crsqlite is 105.72% of SQLite (~103KB overhead)

## Remaining Backlog

**8 parallelizable test tasks** ready for pickup (gap analysis 2025-12-22):

| Task | Test File | Priority |
|------|-----------|----------|
| TASK-161 | `test-resurrection-parity.sh` | HIGH |
| TASK-166 | `test-sentinel-parity.sh` | HIGH |
| TASK-170 | `test-fk-crr.sh` | HIGH |
| TASK-172 | `test-error-handling.sh` | HIGH |
| TASK-173 | `test-schema-mismatch.sh` | MEDIUM |
| TASK-174 | `test-partial-sync.sh` | HIGH |
| TASK-177 | `test-default-merge.sh` | HIGH |
| TASK-179 | `test-multinode-sync.sh` | HIGH |

All 8 can run simultaneously (no file conflicts).

Plus 8 lower-priority items in triage:
- TASK-175: Savepoints, TASK-176: ATTACH, TASK-178: VACUUM
- TASK-180: Site ID collision, TASK-181: crsql_sha(), TASK-182: Triggers
- TASK-183: Wide tables, TASK-156: Linux CI

Other:
- Effect-TS scratchpad (spec-gated) — see `.wishes/blocked-on-tom/effect-bun-scratchpad.md`

## Rules of the game (thing-golf)

Prefer fewer, sharper "Things":
- One task card owns one named delta.
- Each task card lists a tight `Files to Modify` set.
- Each task card links to its parent doc/spec and the parent links back.
