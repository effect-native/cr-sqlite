# TASK-032: Web Phase-2 — Reactive Subscriptions Surface

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [x] Blocked (reason: depends on TASK-063 browser foundation)
- [ ] Complete

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
- **Blocked by**: `.tasks/backlog/TASK-063-browser-multitab-foundation.md` (F5-F8 must be done first)

## Constraint
This work is TypeScript-heavy.

Per `AGENTS.md` (TypeScript Work Rule): **all TypeScript work happens in the `effect-native/` submodule** and must follow the spec-first workflow in `effect-native/.specs/AGENTS.md`.

This task is unblocked: Phase 2 requirements now exist in `effect-native/.specs/crsql-mesh/requirements.md` (browser multi-tab section).

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

## Completion Notes
[fill in when done]
