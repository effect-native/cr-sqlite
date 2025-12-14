# TASK-045: Spec Phase 1 — New Package: `@effect-native/crsql-mesh-runtime-*` (platform adapters)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] `effect-native/.specs/crsql-mesh-runtime/instructions.md` exists and follows Phase 1 rules.
- [x] Doc has a clear rationale for each runtime package (why separate).
- [x] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning
- Created `effect-native/.specs/crsql-mesh-runtime/instructions.md` with Phase 1 content
- Defined 4 candidate runtime packages with clear rationale for separation
- Task complete — awaiting approval before Phase 2

## Completion Notes
**Date:** 2025-12-14

**Created:**
- `effect-native/.specs/crsql-mesh-runtime/instructions.md`

**Runtime Packages Proposed:**
1. `@effect-native/crsql-mesh-runtime-browser` — OPFS persistence, SharedWorker/BroadcastChannel coordination, tab lifecycle
2. `@effect-native/crsql-mesh-runtime-node` — Filesystem persistence, Worker Threads, IPC coordination (also covers Bun/Deno)
3. `@effect-native/crsql-mesh-runtime-react-native` — Native SQLite bindings, app lifecycle, platform-specific background/foreground handling
4. `@effect-native/crsql-mesh-runtime-electron` — Decision point: may be composed from browser+node or warrant its own package

**Key Design Decisions:**
- Separate packages (not universal) to avoid bundle bloat and dependency conflicts
- Each adapter surfaces same abstract capabilities to mesh core
- Transports are explicitly OUT of scope (separate packages)
