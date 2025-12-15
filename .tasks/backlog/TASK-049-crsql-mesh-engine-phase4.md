# TASK-049: Global Mesh — Mesh engine Phase 4 completion

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Spec rules: `effect-native/.specs/AGENTS.md`
- Mesh Phase 1: `effect-native/.specs/crsql-mesh/instructions.md`
- Mesh Phase 2: `effect-native/.specs/crsql-mesh/requirements.md`
- Mesh Phase 3: `effect-native/.specs/crsql-mesh/design.md`
- Mesh Phase 4: `effect-native/.specs/crsql-mesh/plan.md`
- Protocol requirements: `effect-native/.specs/crsql-mesh-protocol/requirements.md`
- Transport requirements: `effect-native/.specs/crsql-mesh-transport/requirements.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Complete the Phase 4 plan for `@effect-native/crsql-mesh` so it satisfies the Phase 2 requirements:

- receive routing + protocol decode
- per-peer periodic summary exchange
- diff request/response loop
- transactional apply via `crsql_changes`
- in-memory version vector updates only after successful apply
- progress observation surface

Keep the scope within the `crsql-mesh` package (no new transport implementations beyond in-memory).

## Files to Modify
- `effect-native/packages-native/crsql-mesh/src/**`
- `effect-native/packages-native/crsql-mesh/test/**`

## Acceptance Criteria
- [ ] `Mesh.run` runs fibers owned by scope (not `Effect.never`).
- [ ] Invalid incoming messages are dropped with typed `ProtocolError` handling.
- [ ] Two peers converge using `InMemoryTransport` and a real CR-SQLite DB integration test (or a clearly-scoped interim harness if real DB is not yet available in CI).
- [ ] Version vector updates only after successful transactional apply.
- [ ] `observeProgress` emits after apply-driven db_version advances.
- [ ] `pnpm -C effect-native vitest packages-native/crsql-mesh` passes.

## Progress Log
### 2025-12-15
- Task created during “Update tasks” reconciliation.

## Completion Notes
[fill in when done]
