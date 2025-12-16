# TASK-054: Browser runtime specs — Phase 2 requirements (unblock TASK-031/032)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked
- [x] Complete

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
Write Phase 2 requirements (EARS) for browser multi-tab (“crsqlite-web-multitab”) as part of the unified full mesh product spec.

Goal: unblock implementation tasks by creating a testable, unambiguous requirement set for:
- SharedWorker coordinator primary path
- Service Worker fallback path
- minimal “db_version advanced” subscription surface

Per Tom (2025-12-16), package boundaries and npm names are deferred until they block progress (Thing Golf / minimize new Things).

## Files to Modify
- `effect-native/.specs/crsql-mesh/requirements.md`
- `effect-native/.specs/crsql-mesh/design.md` (if required for clarification)
- `research/zig-cr/92-gap-backlog.md` (link to spec)

## Acceptance Criteria
- [x] Requirements use EARS notation per `effect-native/.specs/AGENTS.md`.
- [x] Service Worker fallback behavior is specified precisely enough to implement `.tasks/backlog/TASK-031-web-service-worker-fallback.md`.
- [x] Subscription/notification behavior is specified precisely enough to implement `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`.
- [x] Requirements define clear failure modes (e.g., provider death / re-election semantics at MVP level).

## Progress Log
### 2025-12-15
- Task created to unblock TS implementation tasks.

## Completion Notes
Completed 2025-12-16 as part of Round 35 unified mesh specs.

All browser multi-tab requirements now exist in `effect-native/.specs/crsql-mesh/requirements.md` Section 5:
- FR-MULTITAB-001 through FR-MULTITAB-012 cover:
  - Single provider architecture
  - SharedWorker/Service Worker coordinator
  - No COOP/COEP requirement
  - Provider election via Web Locks
  - Provider death detection + re-election
  - OPFS ownership
  - DB version notifications (FR-MULTITAB-008)
  - Idempotent write guard
  - RPC interface
  - Serial execution

This unblocks TASK-031 (Service Worker fallback) and TASK-032 (Reactive subscriptions).

Commits:
- `bf2400ced` (effect-native) — unify mesh specs
- `54fa767f` (root) — delegate round 35
