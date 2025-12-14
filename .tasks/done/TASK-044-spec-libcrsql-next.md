# TASK-044: Spec Phase 1 — Changes to Existing Package: `@effect-native/libcrsql`

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
- Wish: [`.wishes/effect-native.md`](../../.wishes/effect-native.md)
- Existing package: [`effect-native/packages-native/libcrsql/README.md`](../../effect-native/packages-native/libcrsql/README.md)
- Zig packaging gap task (repo-level): [`./.tasks/backlog/TASK-034-npm-package-zig-native.md`](./TASK-034-npm-package-zig-native.md)

## Description
Create Phase-1 `instructions.md` for what must change in `@effect-native/libcrsql` to support the next stage of the project.

This is likely about *distribution and selection* (native + wasm artifacts), not sync semantics.

No implementation in this task.

## Files to Create/Modify
- `effect-native/.specs/libcrsql-next/instructions.md`

## Acceptance Criteria
- [x] `effect-native/.specs/libcrsql-next/instructions.md` exists and follows Phase 1 rules.
- [x] Doc calls out which changes depend on Zig artifacts vs pure JS packaging.
- [x] STOP after this document (do not proceed to Phase 2 without explicit approval).

## Progress Log
### 2025-12-14
- Task created during TS planning
- Subagent assigned: created `effect-native/.specs/libcrsql-next/instructions.md`
- Phase 1 complete: Document covers context, user stories, high-level goals, out of scope, and dependencies
- Dependencies section explicitly separates "Depends on Zig Artifacts" vs "Pure JS/Packaging Work"
- Open questions raised for orchestrator review

## Completion Notes
Phase 1 `instructions.md` created at `effect-native/.specs/libcrsql-next/instructions.md`.

Key points covered:
- **Context**: C/Rust vs Zig artifact inconsistency between native and browser packages
- **User Stories**: Server devs want Zig, maintainers want unified codebase, app devs want parity
- **Goals**: Transition to Zig, maintain backward compat, support transition period if needed
- **Out of Scope**: Sync protocol, browser package changes, mobile, new APIs
- **Dependencies**: Clearly split into Zig-dependent work vs pure JS/packaging work
- **Open Questions**: Replacement vs coexistence, version semantics, Windows parity, transition timeline

STOPPED as required — awaiting approval before proceeding to Phase 2.
