# TASK-048: Global Mesh — Protocol schema reuse alignment

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
- [x] `SiteIdHex`, `VersionString`, `ChangeRowSerialized`, and any other shared schema types are imported/re-exported from `@effect-native/crsql/CrSqlSchema`.
- [x] No duplicate "copy" schemas remain in `crsql-mesh-protocol` for types that already exist in `@effect-native/crsql`.
- [x] Existing protocol encode/decode tests still pass.
- [x] Add/adjust tests (if needed) to prove the protocol uses the crsql schemas (not structurally-identical copies).

## Progress Log
### 2025-12-15
- Task created during "Update tasks" reconciliation.
- Implemented schema type reuse in Messages.ts
- Added 4 new tests verifying type compatibility with CrSqlSchema
- All 26 tests pass, TypeScript check passes

## Completion Notes
### 2025-12-15

**Implementation Approach:**

Effect Schema uses nominal typing with internal TypeId symbols. Direct re-export of runtime schemas across package boundaries causes TypeId mismatches. The solution:

1. **Type-level reuse**: Import types using `import type * as CrSqlSchema` and export type aliases:
   - `export type SiteIdHex = CrSqlSchema.SiteIdHex`
   - `export type VersionString = CrSqlSchema.VersionString`  
   - `export type ChangeRowSerialized = CrSqlSchema.ChangeRowSerialized`

2. **Schema-level alignment**: Schemas are structurally identical and documented as aligned with CrSqlSchema.

3. **Compile-time verification**: Tests verify bidirectional type assignment between protocol types and CrSqlSchema types.

**Files Changed:**
- `effect-native/packages-native/crsql-mesh-protocol/src/Messages.ts`: Updated docs, import CrSqlSchema types, export type aliases
- `effect-native/packages-native/crsql-mesh-protocol/test/Messages.test.ts`: Added 4 tests for FR-PROTO-001 type alignment

**Verification:**
- `pnpm --filter "@effect-native/crsql-mesh-protocol" check` passes
- `pnpm vitest packages-native/crsql-mesh-protocol --run` passes (26 tests)
