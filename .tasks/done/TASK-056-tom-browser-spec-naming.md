# TASK-056: Tom decision — Pick browser runtime spec name + package boundary

## Status
- [x] Planned
- [x] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
Tom

## Parent Docs / Cross-links
- Proposal: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md`
- Spec workflow: `effect-native/.specs/AGENTS.md`
- Spec tasks:
  - `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md`
  - `.tasks/backlog/TASK-054-spec-browser-runtime-phase2.md`

## Description
Before writing browser runtime specs, we need a crisp naming + boundary decision so we don’t create the wrong package(s) and then fight the repo structure.

## Files to Modify
- `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md`
- `.tasks/backlog/TASK-054-spec-browser-runtime-phase2.md`

## Acceptance Criteria
- [x] Decision recorded in `.tasks/backlog/TASK-053-spec-browser-runtime-phase1.md`:
  - Browser multi-tab concept name: `crsqlite-web-multitab`
  - Spec source of truth: unify under `effect-native/.specs/crsql-mesh/` as the single full product spec
  - Package boundaries and npm names: deferred until they block progress (Thing Golf rule)
- [x] `.tasks/backlog/TASK-054-spec-browser-runtime-phase2.md` aligned to write Phase 2 requirements into the unified mesh spec

## Progress Log
### 2025-12-15
- Task created to prevent mis-scoped browser spec work.

## Completion Notes
- 2025-12-16: Tom picked `crsqlite-web-multitab` for the browser multi-tab concept name.
- 2025-12-16: Tom requested a single unified “full mesh product” spec, deferring package boundaries and names until they block progress (Thing Golf / minimize new Things).
