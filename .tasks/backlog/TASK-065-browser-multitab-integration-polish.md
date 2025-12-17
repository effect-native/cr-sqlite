# TASK-065: Browser multi-tab integration polish (F15)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

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
- [ ] Browser multi-tab exports are available from `@effect-native/crsql-mesh` without importing node-only code paths.
- [ ] Verification:
  - `pnpm -C effect-native build --filter "./packages-native/crsql-mesh"`
  - (Optional) bundle-size or treeshake spot-check via existing build tooling

## Progress Log
### 2025-12-17
- Task created during "update tasks" reconciliation from `research/zig-cr/92-gap-backlog.md` remaining F15 work.

## Completion Notes
[fill in when done]
