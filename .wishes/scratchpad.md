i wish my scratchpad playgrounds were all wired up

## scratch/browser-scratchpad ✅

Done (Round 40, 2025-12-16)
- `bun --hot scratch/browser-scratchpad/src/index.ts`
- React app with SharedWorker multi-tab coordination
- Shows cross-tab item sync, provider election, db_version tracking

## scratch/bun-scratchpad ✅

Done (Round 40, 2025-12-16)
- `bun run scratch/bun-scratchpad/index.ts`
- CR-SQLite demo with bun:sqlite + extension loading
- Shows CRR tables, CRUD, db_version, crsql_changes, site_id

## scratch/effect-bun-scratchpad ⏸️

Blocked on Tom / spec-gate (TypeScript work must go through effect-native/.specs/)
See: `.wishes/blocked-on-tom/effect-bun-scratchpad.md`

should be a simple Effect-TS project with bun
using @effect/platform @effect/platform-bun @effect/sql @effect/sql-sqlite-bun
using the @effect/language-service
see .refs/effect/tsconfig.base.json
using @effect/vitest @effect/eslint-plugin
see .refs/effect/package.json
using all our new effect-native packages

should have some kind of realistic example that does something neat
