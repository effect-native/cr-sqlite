# TASK-043: Spec Phase 1 — Changes to Existing Package: `@effect-native/crsql`

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
- [ ] `effect-native/.specs/crsql-mesh-integration/instructions.md` exists and follows Phase 1 rules.
- [ ] Doc explains what part belongs in `@effect-native/crsql` vs `@effect-native/crsql-mesh`.
- [ ] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning

## Completion Notes
[fill in when done]
