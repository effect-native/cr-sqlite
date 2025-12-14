# TASK-045: Spec Phase 1 — New Package: `@effect-native/crsql-mesh-runtime-*` (platform adapters)

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
- Package-map spec (parent): [`effect-native/.specs/crsqlite-global-mesh-packages/instructions.md`](../../effect-native/.specs/crsqlite-global-mesh-packages/instructions.md)
- Global mesh proposal: [`research/zig-cr/102-proposal-crsqlite-global-mesh.md`](../../research/zig-cr/102-proposal-crsqlite-global-mesh.md)

## Description
Create Phase-1 `instructions.md` for the platform-specific runtime packages that provide:
- concrete transports (browser tabs, node processes, etc.)
- persistence details (OPFS vs filesystem)

This task is specifically about scoping and naming the packages (e.g. `...-browser`, `...-node`, `...-react-native`).

No implementation in this task.

## Files to Create/Modify
- `effect-native/.specs/crsql-mesh-runtime/instructions.md`

## Acceptance Criteria
- [ ] `effect-native/.specs/crsql-mesh-runtime/instructions.md` exists and follows Phase 1 rules.
- [ ] Doc has a clear rationale for each runtime package (why separate).
- [ ] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning

## Completion Notes
[fill in when done]
