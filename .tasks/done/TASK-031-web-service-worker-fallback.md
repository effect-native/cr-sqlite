# TASK-031: Web Phase-2 — Service Worker Fallback (No COOP/COEP)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked
- [x] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md` (SharedWorker primary, SW fallback)
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (Multi-tab Web Architecture)
- TS workflow rules: `effect-native/.specs/AGENTS.md`
- RGRTDD plan: `effect-native/.specs/crsql-mesh/plan.md` (F11-F12)
- Browser spec tasks (unblock):
  - ✅ `.tasks/done/TASK-056-tom-browser-spec-naming.md` (concept name + boundary deferral)
  - ✅ `effect-native/.specs/crsql-mesh/requirements.md` (contains Phase 2 EARS for browser multi-tab)
  - ✅ `effect-native/.specs/crsql-mesh/design.md` (contains browser multi-tab design sketch)
  - ✅ `effect-native/.specs/crsql-mesh/plan.md` (contains RGRTDD slices)
- ✅ Unblocked by: `.tasks/done/TASK-063-browser-multitab-foundation.md` (F5-F8 complete)

## Constraint
This work is TypeScript-heavy.

Per `AGENTS.md` (TypeScript Work Rule): **all TypeScript work happens in the `effect-native/` submodule** and must follow the spec-first workflow in `effect-native/.specs/AGENTS.md`.

Unblocked prerequisites:
- ✅ Specs exist: `effect-native/.specs/crsql-mesh/requirements.md`, `effect-native/.specs/crsql-mesh/design.md`, `effect-native/.specs/crsql-mesh/plan.md`
- ✅ Foundation exists: `.tasks/done/TASK-063-browser-multitab-foundation.md` (Coordinator/Provider unit-tested scaffolding)

**Tom authorized Phase 5 implementation on 2025-12-16.**

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

### 2025-12-16
- Tom authorized Phase 5 implementation
- Implemented F11-F12 from RGRTDD plan

## Completion Notes
**Date:** 2025-12-16

**Files created:**
- `effect-native/packages-native/crsql-mesh/src/browser/coordinator-sw.ts` (348 lines)
- `effect-native/packages-native/crsql-mesh/test/browser/coordinator-sw.test.ts` (12 tests)

**Files modified:**
- `effect-native/packages-native/crsql-mesh/src/browser/index.ts` (added SW exports)

**Implementation:**
- `ServiceWorkerCoordinator` class mirrors SharedWorker coordinator API
- Uses Service Worker Clients API instead of MessagePorts
- Same election semantics via Web Locks
- Same message routing patterns
- Includes `createServiceWorkerScript()` for bootstrapping

**Tests:** 12 new tests, all passing
**TypeScript:** Check passes
