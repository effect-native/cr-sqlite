# TASK-032: Web Phase-2 — Reactive Subscriptions Surface

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
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md` ("Notifications / subscriptions")
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (Multi-tab Web Architecture)
- Current impl: `zig/browser-test/src/client/db-client.ts`

## Constraint
Likely TypeScript-heavy. Per `.wishes/stop-before-typescript.md`, do not implement without Tom explicitly opting-in.

If Tom has not opted-in, convert this task into a blocked task card with a short design note and a "Tom decision needed" checklist.

## Description
Provide a narrow notification/subscription surface so tab B can react when tab A writes.

MVP can be a "db_version advanced" event broadcast; leave "observable queries" as optional.

## Files to Modify
- `zig/browser-test/src/shared/rpc-types.ts`
- `zig/browser-test/src/client/db-client.ts`
- `zig/browser-test/src/coordinator/shared-worker.ts`
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
