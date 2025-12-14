# TASK-041: Spec Phase 1 — New Package: `@effect-native/crsql-mesh` (core sync engine)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Package-map spec (parent): [`effect-native/.specs/crsqlite-global-mesh-packages/instructions.md`](../../effect-native/.specs/crsqlite-global-mesh-packages/instructions.md)
- Protocol package spec: [`effect-native/.specs/crsql-mesh-protocol/instructions.md`](../../effect-native/.specs/crsql-mesh-protocol/instructions.md)
- Global mesh proposal: [`research/zig-cr/102-proposal-crsqlite-global-mesh.md`](../../research/zig-cr/102-proposal-crsqlite-global-mesh.md)

## Description
Create Phase-1 `instructions.md` for the core mesh sync engine package.

This package is the transport-agnostic engine that:
- pulls changes from a local replica via the CR-SQLite surface
- exchanges summaries / wants / batches
- applies incoming changes transactionally

No implementation in this task.

## Files to Create/Modify
- `effect-native/.specs/crsql-mesh/instructions.md`

## Acceptance Criteria
- [ ] `effect-native/.specs/crsql-mesh/instructions.md` exists and follows Phase 1 rules.
- [ ] Doc explicitly states what “eventual consistency” means for callers.
- [ ] Doc explicitly excludes “global uniqueness” / “linearizable reads”.
- [ ] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning

## Completion Notes
[fill in when done]
