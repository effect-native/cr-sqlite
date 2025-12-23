# start-here

If you're asking "what's left?" start here:

- Canonical status + remaining gaps: `research/zig-cr/92-gap-backlog.md`
- Task queue (what to run next): `.tasks/{backlog,active,done}/`
- Zig implementation: `zig/`
- TS specs + packages:
  - Specs: `effect-native/.specs/`
  - Packages: `effect-native/packages-native/`

## Current Status (2025-12-23)

**Zig parity is essentially complete:**
- Oracle parity: 18/18 passing
- Cross-open parity: 24/24 passing
- rows_impacted: 18/18 passing
- ALTER tests: 6/6 passing
- Cross-platform compat: ALL passing
- Resurrection parity: 25/25 passing
- Sentinel parity: 6/6 passing
- Multinode sync: 6/6 passing
- Savepoint sync: 16/16 passing
- ATTACH CRR: 15/15 passing
- Site ID collision: 13/13 passing
- Trigger CRR: 31/31 passing
- VACUUM CRR: 17/17 passing
- Wide table: 13/13 passing (64-col limit fixed, now 2000)
- Schema mismatch: 11/12 passing (1 intentional divergence)
- Browser tests: 30/30 passing (includes sqlite-vec, FTS5, JSONB)
- Mesh tests: 81/81 passing
- TypeScript: clean
- **Test scripts: 63 total**

**Scratchpad demos work:**
- `bun run scratch/bun-scratchpad/index.ts` — CR-SQLite with bun:sqlite
- `bun --hot scratch/browser-scratchpad/src/index.ts` — React multi-tab sync

**Size is healthy:**
- Zig crsqlite is 105.72% of SQLite (~103KB overhead)

## Remaining Backlog

### Needs Decision (1 item)

| Task | Summary | Blocker |
|------|---------|---------|
| **TASK-186** | Schema mismatch: unknown column behavior | Design decision: error vs ignore |

Current divergence: When source has column destination doesn't know:
- Zig: ERROR (strict)
- Rust/C: IGNORED (lenient)

Options:
1. Align with Rust/C (ignore) — maximizes compatibility
2. Keep strict (error) — catches schema drift early
3. Make configurable — `crsql_config_set('ignore-unknown-columns', 1)`

### Low Priority (1 item)

| Task | Summary | Notes |
|------|---------|-------|
| **TASK-156** | Linux CI parity | CI-only, not blocking local dev |

### Blocked on Tom (TypeScript)

See `.wishes/blocked-on-tom/`:
- Effect-TS scratchpad (spec-gated)
- Implementation-agnostic spec suite
- Browser spec naming
- Upstream feedback scope

## Rules of the game (thing-golf)

Prefer fewer, sharper "Things":
- One task card owns one named delta.
- Each task card lists a tight `Files to Modify` set.
- Each task card links to its parent doc/spec and the parent links back.
