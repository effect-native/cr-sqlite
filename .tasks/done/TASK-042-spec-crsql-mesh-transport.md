# TASK-042: Spec Phase 1 — New Package: `@effect-native/crsql-mesh-transport`

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
Create Phase-1 `instructions.md` for a small package that defines the transport adapter interface(s).

Goal: make transports pluggable without infecting the core sync engine.

No implementation in this task.

## Files to Create/Modify
- `effect-native/.specs/crsql-mesh-transport/instructions.md`

## Acceptance Criteria
- [x] `effect-native/.specs/crsql-mesh-transport/instructions.md` exists and follows Phase 1 rules.
- [x] Doc names the kinds of transports we anticipate (same-process, browser BroadcastChannel, WS, WebRTC), without specifying libraries.
- [x] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning
- Created `effect-native/.specs/crsql-mesh-transport/instructions.md`
- Phase 1 spec covers Context, User Stories, High-Level Goals, Out of Scope
- Enumerated transport categories: same-process, same-origin browser (BroadcastChannel), network (WS), peer-to-peer (WebRTC), local network (UDP/mDNS), platform-native (Bluetooth/Multipeer), IPC (unix sockets)
- No libraries specified, only interface intent
- STOPPED after Phase 1 as required

## Completion Notes
- Phase 1 instructions.md created at `effect-native/.specs/crsql-mesh-transport/instructions.md`
- Document follows Phase 1 rules: no technical jargon, no implementation details, no "shall" statements
- Awaiting approval to proceed to Phase 2 (requirements.md)
