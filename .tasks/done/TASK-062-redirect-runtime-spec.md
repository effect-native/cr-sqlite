# TASK-062: Redirect mesh runtime spec to unified product spec

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
low

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Unified product spec entrypoint: `effect-native/.specs/crsql-mesh/instructions.md`
- Runtime spec directory: `effect-native/.specs/crsql-mesh-runtime/`
- Thing Golf: `research/thing-golf.md`

## Description
Make it obvious that runtime adapters are now specified primarily in the unified mesh product spec, with this directory treated as legacy/reference until we decide final boundaries.

## Files to Modify
- `effect-native/.specs/crsql-mesh-runtime/instructions.md`

## Acceptance Criteria
- [x] `effect-native/.specs/crsql-mesh-runtime/instructions.md` starts with a short note:
  - points to `effect-native/.specs/crsql-mesh/`
  - states "package boundaries deferred until blocked"
  - clarifies this directory is reference material for now

## Progress Log
### 2025-12-16
- Task created to reduce confusion while specs are unified.

## Completion Notes
- 2025-12-16: Completed in Round 35 delegate session
- Added redirect notice to `effect-native/.specs/crsql-mesh-runtime/instructions.md`
