# TASK-043: Spec Phase 1 — Changes to Existing Package: `@effect-native/crsql`

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
- Existing package: [`effect-native/packages-native/crsql/README.md`](../../effect-native/packages-native/crsql/README.md)
- Upstream Effect SQL:
  - [`./.refs/effect/packages/sql/`](../../.refs/effect/packages/sql/)
  - [`./.refs/effect/packages/sql-sqlite-bun/`](../../.refs/effect/packages/sql-sqlite-bun/)

## Description
Create Phase-1 `instructions.md` for the *mesh-related changes* we expect in `@effect-native/crsql`.

Examples of the kind of integration this spec should cover (as intent, not implementation):
- a typed way to pull ordered rows from `crsql_changes`
- a typed way to apply rows into `crsql_changes`
- helpers that compose cleanly with `@effect/sql` clients

No implementation in this task.

## Files to Create/Modify
- `effect-native/.specs/crsql-mesh-integration/instructions.md`

## Acceptance Criteria
- [x] `effect-native/.specs/crsql-mesh-integration/instructions.md` exists and follows Phase 1 rules.
- [x] Doc explains what part belongs in `@effect-native/crsql` vs `@effect-native/crsql-mesh`.
- [x] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning
- Created `effect-native/.specs/crsql-mesh-integration/instructions.md`
- Spec defines the integration surface between `@effect-native/crsql` and `@effect-native/crsql-mesh-core`
- Clearly separates database primitives (crsql) from sync orchestration (mesh-core)
- STOPPED as required — awaiting approval before Phase 2

## Completion Notes
Phase 1 complete. Created instructions.md covering:
- Context: existing crsql package capabilities and mesh integration needs
- User Story: sync engine developer perspective
- High-Level Goals: typed change access, streaming, cursor management, package boundary principles
- Out of Scope: sync engine logic, protocol, transport, peer discovery, auth, encryption, reactivity
- Questions for Design Phase: streaming approach, cursor enhancement, validation, mutation observation
