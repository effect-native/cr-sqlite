# TASK-197 — Fix seq Off-by-One in Zig INSERT Triggers

## Goal
Fix the `seq` value divergence where Zig INSERT triggers start at 1 instead of 0 (matching Rust/C).

## Status
- State: triage
- Priority: LOW (sync still works, but ordering edge cases possible)
- Discovered: 2025-12-25 (from TASK-196 clock table inspection)

## Problem
When inserting rows, the Zig implementation starts the `seq` value at 1 instead of 0:

```
Rust/C: seq = 0, 1 (for 2-column INSERT)
Zig:    seq = 1, 2 (for 2-column INSERT)
```

This affects the ordering of changes within the same `db_version` and could cause edge-case sync issues.

## Root Cause (Suspected)
The INSERT trigger in Zig likely uses a 1-based counter instead of 0-based when recording column changes.

## Files to Modify
- `zig/src/triggers.zig` (or equivalent trigger generation code)

## Acceptance Criteria
1. `seq` values start at 0 for INSERT triggers
2. `zig/harness/test-clock-internals.sh` passes without seq divergence notes
3. All other parity tests continue to pass

## Parent Docs / Cross-links
- Discovered in: `.tasks/done/TASK-196-clock-table-direct-inspection.md`
- Test script: `zig/harness/test-clock-internals.sh`

## Progress Log
- 2025-12-25: Created from TASK-196 findings.

## Completion Notes
(Empty until done.)
