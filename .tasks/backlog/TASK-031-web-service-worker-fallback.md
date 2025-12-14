# TASK-031: Web Phase-2 — Service Worker Fallback (No COOP/COEP)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md` (SharedWorker primary, SW fallback)
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (Multi-tab Web Architecture)
- Current impl: `zig/browser-test/src/coordinator/shared-worker.ts`, `zig/browser-test/src/client/db-client.ts`

## Constraint
This work is likely TypeScript-heavy. Per `.wishes/stop-before-typescript.md`, do not implement without Tom explicitly opting-in.

If Tom has not opted-in, convert this task into a blocked task card with a short design note and a "Tom decision needed" checklist.

## Description
Add a Service Worker fallback for environments where SharedWorker is unavailable.

Scope is only the coordinator/port-bridging fallback.
Do not attempt to move OPFS access into the Service Worker.

## Files to Modify
- `zig/browser-test/src/*` and/or `zig/browser-dist/*`
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
