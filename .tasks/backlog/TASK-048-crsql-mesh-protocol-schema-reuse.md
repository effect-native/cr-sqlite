# TASK-048: Global Mesh — Protocol schema reuse alignment

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
- Protocol Phase 1: `effect-native/.specs/crsql-mesh-protocol/instructions.md`
- Protocol Phase 2: `effect-native/.specs/crsql-mesh-protocol/requirements.md`
- Protocol Phase 3: `effect-native/.specs/crsql-mesh-protocol/design.md`
- Protocol Phase 4: `effect-native/.specs/crsql-mesh-protocol/plan.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Align `@effect-native/crsql-mesh-protocol` implementation with Phase 2 requirement **FR-PROTO-001** (schema reuse): reuse schema definitions from `@effect-native/crsql/CrSqlSchema` instead of re-declaring near-identical schemas.

This is about tightening the single-source-of-truth boundary at the DB/IO boundary.

## Files to Modify
- `effect-native/packages-native/crsql-mesh-protocol/src/Messages.ts`
- `effect-native/packages-native/crsql-mesh-protocol/src/index.ts` (if exports change)
- `effect-native/packages-native/crsql-mesh-protocol/test/*`

## Acceptance Criteria
- [ ] `SiteIdHex`, `VersionString`, `ChangeRowSerialized`, and any other shared schema types are imported/re-exported from `@effect-native/crsql/CrSqlSchema`.
- [ ] No duplicate “copy” schemas remain in `crsql-mesh-protocol` for types that already exist in `@effect-native/crsql`.
- [ ] Existing protocol encode/decode tests still pass.
- [ ] Add/adjust tests (if needed) to prove the protocol uses the crsql schemas (not structurally-identical copies).

## Progress Log
### 2025-12-15
- Task created during “Update tasks” reconciliation.

## Completion Notes
[fill in when done]
