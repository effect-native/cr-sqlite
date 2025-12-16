# TASK-057: Unify mesh requirements into one place

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
- Existing split specs (to reference, not to extend):
  - `effect-native/.specs/crsql-mesh-protocol/requirements.md`
  - `effect-native/.specs/crsql-mesh-transport/requirements.md`
  - `effect-native/.specs/crsql-mesh-runtime/requirements.md`
- Web multi-tab proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
We want a single, full-product requirements document for the mesh.

Per Tom (2025-12-16): smooth all mesh specs together first; defer package boundaries and npm names until they block progress (Thing Golf: minimize new Things).

## Files to Modify
- `effect-native/.specs/crsql-mesh/requirements.md`

## Acceptance Criteria
- [x] `effect-native/.specs/crsql-mesh/requirements.md` reads as a unified product requirements doc.
- [x] Requirements include (at minimum):
  - Mesh engine anti-entropy requirements (already exists)
  - Protocol requirements (message envelope + diff vocabulary)
  - Transport requirements (opaque bytes + peer routing expectations)
  - Runtime adapter requirements (platform wiring expectations)
  - Browser multi-tab ("crsqlite-web-multitab") requirements written in EARS notation:
    - SharedWorker preferred, Service Worker fallback
    - No COOP/COEP requirement
    - Provider tab dedicated worker owns OPFS
    - Provider death and re-election semantics at MVP level
    - Minimal db_version advanced notifications
- [x] Requirements avoid premature package/module boundaries.

## Progress Log
### 2025-12-16
- Task created to enable parallel spec work with disjoint files.

## Completion Notes
- 2025-12-16: Completed in Round 35 delegate session
- Added Protocol requirements (FR-PROTO-001 through FR-PROTO-007)
- Added Transport requirements (FR-TRANS-001 through FR-TRANS-007)
- Added Runtime Adapter requirements (FR-RUNTIME-001 through FR-RUNTIME-006)
- Added Browser Multi-Tab requirements (FR-MULTITAB-001 through FR-MULTITAB-012) with EARS notation
- Unified non-functional requirements and constraints
- Removed all package boundary references
