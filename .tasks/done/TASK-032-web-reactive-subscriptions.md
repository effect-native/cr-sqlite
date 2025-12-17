# TASK-032: Web Phase-2 — Reactive Subscriptions Surface

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
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md` ("Notifications / subscriptions")
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (Multi-tab Web Architecture)
- TS workflow rules: `effect-native/.specs/AGENTS.md`
- RGRTDD plan: `effect-native/.specs/crsql-mesh/plan.md` (F9-F10)
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
Provide a narrow notification/subscription surface so tab B can react when tab A writes.

MVP can be a "db_version advanced" event broadcast; leave "observable queries" as optional.

## Files to Modify
- `effect-native/packages-native/` (exact package(s) TBD; see `effect-native/.specs/crsql-mesh-runtime/instructions.md`)
- `research/zig-cr/92-gap-backlog.md` (status notes)

## Acceptance Criteria
- [ ] Provider publishes a notification when `crsql_db_version()` advances.
- [ ] Clients can subscribe/unsubscribe and receive events.
- [ ] Playwright test proves cross-tab visibility within one notification round.

## Progress Log
### 2025-12-14
- Task created during gap review; awaiting Tom opt-in due to TS constraint

### 2025-12-16
- Tom authorized Phase 5 implementation
- Implemented F9-F10 from RGRTDD plan

## Completion Notes
**Date:** 2025-12-16

**Files modified:**
- `effect-native/packages-native/crsql-mesh/src/browser/provider.ts`
  - Added `DbVersionNotification` interface
  - Added `onVersionChange(callback)` subscription method
  - Added `checkAndNotifyVersionChange()` after writes
  - Provider queries `crsql_db_version()` after exec and notifies on advance
- `effect-native/packages-native/crsql-mesh/src/browser/coordinator.ts`
  - Added `DbVersionChangedMessage` interface
  - Added `handleDbVersionChanged()` to broadcast notifications
  - Routes `db-version-changed` messages from provider to all clients
- `effect-native/packages-native/crsql-mesh/src/browser/index.ts`
  - Exported new types

**Tests:** 8 new tests (4 coordinator, 4 provider), all passing
**TypeScript:** Check passes
