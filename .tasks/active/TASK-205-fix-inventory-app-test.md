# TASK-205 — Fix Inventory App Simulation Test

## Goal
Fix `test-app-inventory.sh` which fails for BOTH Zig AND Rust/C implementations.

## Status
- State: triage
- Priority: LOW (test bug, not implementation bug)
- Discovered: 2025-12-25 (Round 73)

## Problem

The inventory app test fails with both implementations showing sites don't converge:

```
Step 3: Verify convergence
  FAIL: Sites did not converge
  A: PROD-A|site-a|150
PROD-B|site-a|75
  B: PROD-A|site-b|200
PROD-C|site-b|50
  C: PROD-B|site-c|100
PROD-C|site-c|125
```

Since both implementations fail identically, this is a test design issue, not an implementation bug.

## Root Cause (Suspected)

The test creates inventory at different sites but:
1. Each site creates different products (PROD-A at site-a, PROD-B at site-a, etc.)
2. The sync only transfers data, not schema
3. Sites end up with their local data only

The test should either:
1. Have all sites share the same products first
2. Or verify that each site has ALL products after sync (not just their local ones)

## Files to Modify

- `zig/harness/test-app-inventory.sh` — Fix test logic

## Acceptance Criteria

1. [ ] Test passes for both Zig and Rust/C
2. [ ] Or document as intentional behavior and mark test as xfail

## Parent Docs / Cross-links

- Test script: `zig/harness/test-app-inventory.sh`
- Related: `.tasks/done/TASK-194-real-world-app-simulation.md`

## Progress Log
- 2025-12-25: Created from Round 73 findings.

## Completion Notes
(Empty until done.)
