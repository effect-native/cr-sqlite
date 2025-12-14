# TASK-041: Spec Phase 1 — New Package: `@effect-native/crsql-mesh` (core sync engine)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] `effect-native/.specs/crsql-mesh/instructions.md` exists and follows Phase 1 rules.
- [x] Doc explicitly states what "eventual consistency" means for callers.
- [x] Doc explicitly excludes "global uniqueness" / "linearizable reads".
- [x] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning
- Created `effect-native/.specs/crsql-mesh/` directory
- Created `instructions.md` following Phase 1 rules (no technical jargon, no implementation details)
- Doc includes explicit definition of "eventual consistency" for callers
- Doc explicitly excludes "global uniqueness" and "linearizable reads" in Out of Scope section
- Task complete — awaiting Phase 2 approval

## Completion Notes
Phase 1 spec created. Document covers:
- Context: Why a sync engine is needed (duplicated ad-hoc sync logic across projects)
- User Story: Developer wanting transport-agnostic sync engine
- High-Level Goals: Transport-agnostic core, anti-entropy loop, transactional apply, local-first, eventual consistency, idempotency, observability
- Out of Scope: Transport implementations, global uniqueness, linearizable reads, ordering guarantees, auth/identity, schema migrations, conflict resolution customization, snapshots, compaction, sync state persistence

STOPPED as required — Phase 2 requires explicit approval.
