# TASK-031: Web Phase-2 — Service Worker Fallback (No COOP/COEP)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: TS work must follow spec-first in `effect-native/`)
- [ ] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md` (SharedWorker primary, SW fallback)
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (Multi-tab Web Architecture)
- TS workflow rules: `effect-native/.specs/AGENTS.md`
- Browser spec tasks (unblock):
  - ✅ `.tasks/done/TASK-056-tom-browser-spec-naming.md` (concept name + boundary deferral)
  - ✅ `effect-native/.specs/crsql-mesh/requirements.md` (contains Phase 2 EARS for browser multi-tab)
  - ✅ `effect-native/.specs/crsql-mesh/design.md` (contains browser multi-tab design sketch)
  - ✅ `effect-native/.specs/crsql-mesh/plan.md` (contains RGRTDD slices)

## Constraint
This work is TypeScript-heavy.

Per `AGENTS.md` (TypeScript Work Rule): **all TypeScript work happens in the `effect-native/` submodule** and must follow the spec-first workflow in `effect-native/.specs/AGENTS.md`.

This task is unblocked: Phase 2 requirements now exist in `effect-native/.specs/crsql-mesh/requirements.md` (browser multi-tab section).

## Description
Add a Service Worker fallback for environments where SharedWorker is unavailable.

Scope is only the coordinator/port-bridging fallback.
Do not attempt to move OPFS access into the Service Worker.

## Files to Modify
- `effect-native/packages-native/` (exact package(s) TBD; see `effect-native/.specs/crsql-mesh-runtime/instructions.md`)
- `research/zig-cr/92-gap-backlog.md` (status notes)

## Acceptance Criteria
- [ ] In an environment without SharedWorker, multi-tab open still succeeds using SW fallback.
- [ ] Existing Playwright tests extended or a new test added to cover the fallback path.
- [ ] No regression in SharedWorker path.

## Progress Log
### 2025-12-14
- Task created during gap review; awaiting Tom opt-in due to TS constraint

## Completion Notes
[fill in when done]
