# TASK-059: Unify mesh RGRTDD plan into one place

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
- Thing Golf: `research/thing-golf.md`
- Spec workflow: `effect-native/.specs/AGENTS.md`
- Unified product plan target: `effect-native/.specs/crsql-mesh/plan.md`
- Existing split plans (to consult):
  - `effect-native/.specs/crsql-mesh-protocol/plan.md`
  - `effect-native/.specs/crsql-mesh-transport/plan.md`
  - `effect-native/.specs/crsql-mesh-runtime/plan.md`
- Browser multi-tab proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`

## Description
The repo currently has multiple “mesh” plans spread across spec directories. We want one top-level RGRTDD plan that sequences the full product and makes it easy to delegate.

Per Tom (2025-12-16), do not finalize package boundaries until blocked.

## Files to Modify
- `effect-native/.specs/crsql-mesh/plan.md`

## Acceptance Criteria
- [x] `effect-native/.specs/crsql-mesh/plan.md` becomes the single product-level plan.
- [x] Plan includes explicit delegation-friendly slices with verification commands.
- [x] Plan includes browser multi-tab ("crsqlite-web-multitab") slices:
  - spec phases (Phase 1/2/3/4 artifacts)
  - then implementation slices (Phase 5) explicitly blocked until approval

## Progress Log
### 2025-12-16
- Task created to enable parallel spec work with disjoint files.
- Added Section F "Browser Multi-Tab (crsqlite-web-multitab)" to plan.md

## Completion Notes
- Modified: `effect-native/.specs/crsql-mesh/plan.md`
- Added Section F with:
  - Architecture summary referencing `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
  - Spec phases F1-F4 (instructions, requirements, design, plan refinement)
  - Implementation slices F5-F15 (RED/GREEN/REFACTOR for coordinator, provider, notifications, Service Worker fallback, provider migration)
  - All slices include verification commands
  - Implementation slices explicitly blocked until spec approval
- File grew from 106 to 199 lines
