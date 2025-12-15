# TASK-054: Browser runtime specs — Phase 2 requirements (unblock TASK-031/032)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [x] Blocked (reason: depends on Phase 1 instructions approval)
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
Write Phase 2 requirements (EARS) for the browser multi-tab runtime.

Goal: unblock implementation tasks by creating a testable, unambiguous requirement set for:
- SharedWorker coordinator primary path
- Service Worker fallback path
- minimal “db_version advanced” subscription surface

## Files to Modify
- `effect-native/.specs/<new-browser-runtime-spec>/requirements.md`
- `research/zig-cr/92-gap-backlog.md` (link to spec)

## Acceptance Criteria
- [ ] Requirements use EARS notation per `effect-native/.specs/AGENTS.md`.
- [ ] Service Worker fallback behavior is specified precisely enough to implement `.tasks/backlog/TASK-031-web-service-worker-fallback.md`.
- [ ] Subscription/notification behavior is specified precisely enough to implement `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`.
- [ ] Requirements define clear failure modes (e.g., provider death / re-election semantics at MVP level).

## Progress Log
### 2025-12-15
- Task created to unblock TS implementation tasks.

## Completion Notes
[fill in when done]
