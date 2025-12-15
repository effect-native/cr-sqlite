# TASK-050: Global Mesh — Node runtime Phase 4 completion

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
- Runtime Phase 1: `effect-native/.specs/crsql-mesh-runtime/instructions.md`
- Runtime Phase 2: `effect-native/.specs/crsql-mesh-runtime/requirements.md`
- Runtime Phase 3 (node): `effect-native/.specs/crsql-mesh-runtime/design.md`
- Runtime Phase 4: `effect-native/.specs/crsql-mesh-runtime/plan.md`
- Protocol requirements: `effect-native/.specs/crsql-mesh-protocol/requirements.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Complete the Phase 4 plan for `@effect-native/crsql-mesh-runtime-node`:

- validate and prepare `databasePath`
- open SQLite database at `databasePath`
- load the CR-SQLite extension
- ensure protocol layer init runs (fail-fast on `UnhexUnavailable`)
- wire process lifecycle hooks (SIGINT/SIGTERM) for graceful shutdown within `shutdownTimeout`

## Files to Modify
- `effect-native/packages-native/crsql-mesh-runtime-node/src/**`
- `effect-native/packages-native/crsql-mesh-runtime-node/test/**`

## Acceptance Criteria
- [ ] `NodeRuntimeLive` actually opens the database and loads CR-SQLite.
- [ ] Protocol layer initialization happens during layer acquisition.
- [ ] `UnhexUnavailable` fails runtime without fallback.
- [ ] SIGINT/SIGTERM triggers bounded shutdown.
- [ ] `pnpm -C effect-native vitest packages-native/crsql-mesh-runtime-node` passes.

## Progress Log
### 2025-12-15
- Task created during “Update tasks” reconciliation.

## Completion Notes
[fill in when done]
