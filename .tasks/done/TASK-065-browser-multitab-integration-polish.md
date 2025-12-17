# TASK-065: Browser multi-tab integration polish (F15)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Unified plan (source of truth): `effect-native/.specs/crsql-mesh/plan.md` Section F (F15)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Complete the browser multi-tab integration polish slice from the RGRTDD plan (F15):

- Ensure browser worker modules are tree-shakeable.
- Ensure the `@effect-native/crsql-mesh` public surface for browser multi-tab is clean and minimal.
- Verify build output does not accidentally pull in node-only dependencies.

This task is intended as a packaging/build correctness pass, not feature work.

## Files to Modify
- `effect-native/packages-native/crsql-mesh/src/index.ts`
- `effect-native/packages-native/crsql-mesh/src/browser/index.ts`
- `effect-native/packages-native/crsql-mesh/package.json` (if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Browser multi-tab exports are available from `@effect-native/crsql-mesh` without importing node-only code paths.
- [x] Verification:
  - `pnpm -F @effect-native/crsql-mesh check` ✓
  - `pnpm -F @effect-native/crsql-mesh test --run` ✓ (81 tests passed)
  - `pnpm --filter "@effect-native/crsql-mesh" build` ✓

## Progress Log
### 2025-12-17
- Task created during "update tasks" reconciliation from `research/zig-cr/92-gap-backlog.md` remaining F15 work.

## Completion Notes

### 2025-12-16 - Completed (no changes needed)

**Analysis Results:**

The browser multi-tab integration is already correctly structured:

1. **Tree-shakeability verified:**
   - `src/browser/index.ts` uses explicit named exports (not barrel `export *`)
   - Each browser module (`coordinator.ts`, `provider.ts`, `coordinator-sw.ts`) is standalone
   - `coordinator-sw.ts` only uses `import type` from `coordinator.ts` (no runtime dependency)

2. **No node-only dependencies:**
   - Browser modules have zero external imports - pure TypeScript/browser APIs only
   - Verified via ripgrep: no imports from `fs`, `path`, `crypto`, `node:`, `child_process`, `os`

3. **Clean public surface:**
   - Main index: `export * as Browser from "./browser/index.js"` (namespace export)
   - Direct imports also available: `@effect-native/crsql-mesh/browser/*`

**Verification Commands:**

```
$ pnpm -F @effect-native/crsql-mesh check
> tsc -b tsconfig.json
(no errors)

$ pnpm -F @effect-native/crsql-mesh test --run
 ✓ test/browser/coordinator-sw.test.ts (12 tests)
 ✓ test/browser/coordinator.test.ts (18 tests)
 ✓ test/browser/provider.test.ts (25 tests)
 ✓ test/IntegrationSqlite.test.ts (3 tests)
 ✓ test/Receive.test.ts (4 tests)
 ✓ test/Mesh.test.ts (7 tests)
 ✓ test/VersionVector.test.ts (3 tests)
 ✓ test/Integration.test.ts (4 tests)
 ✓ test/Apply.test.ts (5 tests)
Test Files  9 passed (9)
     Tests  81 passed (81)

$ pnpm --filter "@effect-native/crsql-mesh" build
Successfully compiled 11 files with Babel
```

**Files Modified:** None - code already meets all acceptance criteria

**Commit:** N/A (no changes)
