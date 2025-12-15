# TASK-046: Phase 2 requirements — `crsql-mesh` slice (node-first)

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
- [ ] All requirements use EARS notation.
- [ ] Requirements reference reuse of `@effect-native/crsql` schemas (no duplicate serialization types).
- [ ] `unhex()` requirement is explicit and includes fail-fast behavior (`UnhexUnavailable`).
- [ ] Node runtime requirements explicitly depend on `@effect/platform` capabilities.
- [ ] Each requirements.md has a short “Out of Scope” section aligned with Phase 1.

## Progress Log
### 2025-12-15
- Task created from Tom-approved Phase 2 gate

## Completion Notes
[fill in when done]
