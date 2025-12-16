# TASK-053: Browser runtime specs — Phase 1 instructions (multi-tab, no COOP/COEP)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: requires Phase-approval workflow in `effect-native/.specs/AGENTS.md`)
- [ ] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Spec workflow rules: `effect-native/.specs/AGENTS.md`
- Source proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
- Blocked implementation tasks:
  - `.tasks/backlog/TASK-031-web-service-worker-fallback.md`
  - `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Create Phase 1 spec instructions for browser multi-tab (“crsqlite-web-multitab”) as part of the unified full mesh product spec.

Per Tom (2025-12-16), defer package boundaries and npm names until they block progress (Thing Golf / minimize new Things). This task updates Phase 1 content in the unified spec and ensures it carries the web multi-tab constraints needed to write Phase 2 requirements later.

## Files to Modify
- `effect-native/.specs/crsql-mesh/instructions.md`
- `effect-native/.specs/crsql-mesh/requirements.md`
- `effect-native/.specs/crsql-mesh/design.md`
- `effect-native/.specs/crsql-mesh/plan.md`
- `effect-native/.specs/README.md` (add cross-link, if applicable)
- `research/zig-cr/92-gap-backlog.md` (link to spec)

## Acceptance Criteria
- [x] Unified Phase 1 spec exists in `effect-native/.specs/crsql-mesh/instructions.md` with:
  - Context
  - User Story
  - High-Level Goals
  - Out of Scope
- [x] The spec explicitly references the constraints from `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`:
  - SharedWorker preferred, Service Worker fallback
  - No COOP/COEP requirement
  - Provider-tab dedicated worker owns OPFS
- [x] The spec calls out the minimal “notification/subscription” goal (db_version advanced events) needed by `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`.

## Progress Log
### 2025-12-15
- Task created to unblock Phase 2 browser requirements.

## Completion Notes
[fill in when done]
