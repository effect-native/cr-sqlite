# TASK-053: Browser runtime specs — Phase 1 instructions (multi-tab, no COOP/COEP)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [x] Blocked (reason: requires Phase-approval workflow in `effect-native/.specs/AGENTS.md`)
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
Create Phase 1 spec instructions for the browser multi-tab runtime so that Phase 2 requirements can be written and TS implementation can become unblocked.

This task produces only `instructions.md` (Phase 1) in a new spec directory under `effect-native/.specs/`.

## Files to Modify
- `effect-native/.specs/<new-browser-runtime-spec>/instructions.md`
- `effect-native/.specs/README.md` (add cross-link, if applicable)
- `research/zig-cr/92-gap-backlog.md` (link to spec)

## Acceptance Criteria
- [ ] New Phase 1 spec exists with:
  - Context
  - User Story
  - High-Level Goals
  - Out of Scope
- [ ] The spec explicitly references the constraints from `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`:
  - SharedWorker preferred, Service Worker fallback
  - No COOP/COEP requirement
  - Provider-tab dedicated worker owns OPFS
- [ ] The spec calls out the minimal “notification/subscription” goal (db_version advanced events) needed by `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`.

## Progress Log
### 2025-12-15
- Task created to unblock Phase 2 browser requirements.

## Completion Notes
[fill in when done]
