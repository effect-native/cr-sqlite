# TASK-046: Phase 2 requirements — `crsql-mesh` slice (node-first)

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
- Tom decisions: `.wishes/done/tom-review-crsql-mesh-instructions.md`
- Spec-first rules: `effect-native/.specs/AGENTS.md`
- Phase 1 docs:
  - `effect-native/.specs/crsql-mesh-protocol/instructions.md`
  - `effect-native/.specs/crsql-mesh-transport/instructions.md`
  - `effect-native/.specs/crsql-mesh/instructions.md`
  - `effect-native/.specs/crsql-mesh-runtime/instructions.md` (node section)

## Description
Write Phase 2 `requirements.md` (EARS) for the first-ship slice:

- `@effect-native/crsql-mesh-protocol`
- `@effect-native/crsql-mesh-transport`
- `@effect-native/crsql-mesh` (core engine)
- `@effect-native/crsql-mesh-runtime-node`

Keep it thing-golf small: define the minimum behaviors needed to run a two-peer sync loop over an in-memory transport and a filesystem-backed DB.

STOP after Phase 2 docs (do not design or implement).

## Files to Modify
- `effect-native/.specs/crsql-mesh-protocol/requirements.md`
- `effect-native/.specs/crsql-mesh-transport/requirements.md`
- `effect-native/.specs/crsql-mesh/requirements.md`
- `effect-native/.specs/crsql-mesh-runtime/requirements.md`

## Acceptance Criteria
- [x] All requirements use EARS notation.
- [x] Requirements reference reuse of `@effect-native/crsql` schemas (no duplicate serialization types).
- [x] `unhex()` requirement is explicit and includes fail-fast behavior (`UnhexUnavailable`).
- [x] Node runtime requirements explicitly depend on `@effect/platform` capabilities.
- [x] Each requirements.md has a short "Out of Scope" section aligned with Phase 1.

## Progress Log
### 2025-12-15
- Task created from Tom-approved Phase 2 gate

### 2025-12-14
- Completed Phase 2 requirements for all four packages

## Completion Notes
**Date:** 2025-12-14

**Summary:** Created Phase 2 `requirements.md` files for the node-first crsql-mesh slice using EARS notation.

**Files Created:**
1. `effect-native/.specs/crsql-mesh-protocol/requirements.md` - 7 FRs covering schema reuse, unhex() check, message types
2. `effect-native/.specs/crsql-mesh-transport/requirements.md` - 7 FRs covering interface, in-memory transport, lifecycle
3. `effect-native/.specs/crsql-mesh/requirements.md` - 12 FRs covering anti-entropy loop, version vectors, change pull/apply
4. `effect-native/.specs/crsql-mesh-runtime/requirements.md` - 9 FRs covering Node runtime with @effect/platform

**Key Decisions Encoded:**
- Schema reuse from `@effect-native/crsql/CrSqlSchema` (no duplicate types)
- `unhex()` fail-fast with `UnhexUnavailable` (FR-PROTO-002)
- Node runtime depends on `@effect/platform` (FR-NODE-001)
- InMemoryTransport for testing two-peer sync (FR-TRANS-002)
- Bun support folded into Node runtime (FR-NODE-009)
