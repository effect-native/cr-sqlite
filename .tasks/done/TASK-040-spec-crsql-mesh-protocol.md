# TASK-040: Spec Phase 1 — New Package: `@effect-native/crsql-mesh-protocol`

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
- Global mesh proposal: [`research/zig-cr/102-proposal-crsqlite-global-mesh.md`](../../research/zig-cr/102-proposal-crsqlite-global-mesh.md)

## Description
Create Phase-1 `instructions.md` for a small, purely-data package that defines the mesh protocol surface.

This package is intended to be the shared vocabulary across runtimes:
- message type names
- message envelopes
- version summary concepts (site_id, db_version)

No implementation in this task.

## Files to Create/Modify
- `effect-native/.specs/crsql-mesh-protocol/instructions.md`

## Acceptance Criteria
- [x] `effect-native/.specs/crsql-mesh-protocol/instructions.md` exists and follows Phase 1 rules.
- [x] Doc states what the protocol does not cover (auth, encryption, membership, etc.).
- [x] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning
- Phase 1 instructions.md created at `effect-native/.specs/crsql-mesh-protocol/instructions.md`
- Document follows Phase 1 rules: Context, User Story, High-Level Goals, Out of Scope
- Explicitly lists 12 items that are out of scope (auth, encryption, transport, discovery, persistence, compaction, schema, snapshots, conflict resolution, implementation)

## Completion Notes
Phase 1 complete. Document created and ready for review. STOPPED as instructed — awaiting explicit approval before proceeding to Phase 2.
