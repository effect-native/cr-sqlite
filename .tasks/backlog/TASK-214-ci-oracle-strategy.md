# TASK-214 — CI Oracle Strategy (Rust/C availability)

## Goal
Decide and implement a CI strategy for tests that currently rely on the Rust/C oracle.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Context / Evidence
- CI was disabled partly due to oracle-dependent tests:
  - `.tasks/done/TASK-206-disable-ci-temporarily.md`
  - `.tasks/backlog/TASK-207-reenable-ci-for-release.md`

## Options
- Provide oracle binaries in CI (build `core/` or download prebuilt)
- Split CI: always run Zig-only tests; run oracle parity on a best-effort job
- Remove oracle dependency for release gate (only for preview) and rely on Zig-only suites

## Files to Modify
- `.github/workflows/zig-tests.yaml`
- Potentially add CI scripts under `zig/harness/` for "zig-only" vs "oracle" grouping

## Acceptance Criteria
1. [ ] CI config clearly separates oracle-dependent and zig-only test jobs
2. [ ] Release gating jobs do not silently pass by skipping too much
3. [ ] Document which jobs are required for `0.16.300-preview`

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
