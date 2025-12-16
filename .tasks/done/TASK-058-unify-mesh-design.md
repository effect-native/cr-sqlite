# TASK-058: Unify mesh design into one place

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
- Thing Golf: `research/thing-golf.md`
- Unified product spec entrypoint: `effect-native/.specs/crsql-mesh/instructions.md`
- Requirements (target): `effect-native/.specs/crsql-mesh/requirements.md`
- Existing split designs (to consult):
  - `effect-native/.specs/crsql-mesh-protocol/design.md`
  - `effect-native/.specs/crsql-mesh-transport/design.md`
  - `effect-native/.specs/crsql-mesh-runtime/design.md`
- Web multi-tab proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`

## Description
Create a single, full-product design for mesh that describes how protocol, transport, engine, and runtime adapters compose.

This is not a package design exercise. Per Tom (2025-12-16), we defer package boundaries until they block progress.

## Files to Modify
- `effect-native/.specs/crsql-mesh/design.md`

## Acceptance Criteria
- [x] `effect-native/.specs/crsql-mesh/design.md` includes:
  - A product-level module/concern map (protocol / transport / engine / runtime adapters)
  - Clear responsibilities and dependency directions between those concerns
  - A browser multi-tab ("crsqlite-web-multitab") design sketch:
    - coordinator vs provider vs clients responsibilities
    - the "only provider touches OPFS" invariant
    - liveness and provider election strategy at MVP level
    - notification pathway for db_version advanced
- [x] The design stays prose-only (no copy/pasteable TS) per `effect-native/.specs/AGENTS.md`.

## Progress Log
### 2025-12-16
- Task created to enable parallel spec work with disjoint files.

## Completion Notes
- 2025-12-16: Completed in Round 35 delegate session
- Added Product-Level Module Map at top of design
- Added "Browser Multi-Tab Design (crsqlite-web-multitab)" section with:
  - Architectural Roles table (coordinator/provider/clients)
  - "Only Provider Touches OPFS" invariant
  - Provider Election Strategy using Web Locks
  - Liveness and Death Detection
  - Notification Pathway for db_version advances
  - Migration Safety section
