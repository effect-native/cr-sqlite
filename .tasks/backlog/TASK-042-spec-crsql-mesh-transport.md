# TASK-042: Spec Phase 1 — New Package: `@effect-native/crsql-mesh-transport`

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
Create Phase-1 `instructions.md` for a small package that defines the transport adapter interface(s).

Goal: make transports pluggable without infecting the core sync engine.

No implementation in this task.

## Files to Create/Modify
- `effect-native/.specs/crsql-mesh-transport/instructions.md`

## Acceptance Criteria
- [ ] `effect-native/.specs/crsql-mesh-transport/instructions.md` exists and follows Phase 1 rules.
- [ ] Doc names the kinds of transports we anticipate (same-process, browser BroadcastChannel, WS, WebRTC), without specifying libraries.
- [ ] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning

## Completion Notes
[fill in when done]
