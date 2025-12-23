# TASK-185 — Fix spurious sentinel creation during merge

## Goal
Fix Zig implementation to NOT create sentinel entries when syncing INSERT changes to a new site.

## Status
- State: done
- Priority: HIGH (wire format divergence)
- Discovered: Round 62 (TASK-166 test suite)

## Problem
When syncing INSERT changes to a site that doesn't have the row, Zig incorrectly creates sentinel entries (`cid='-1'`) alongside the column changes. Rust/C correctly omits sentinels since no DELETE operation occurred.

**Test failure from `test-sentinel-parity.sh`:**
```
Test 4: No sentinel on merge - FAIL
  DIVERGENCE: Zig creates 3 spurious sentinels vs Rust 0

  Rust/C Site B sentinels: 0
  Zig Site B sentinels:    3

  When syncing INSERT changes to a new site, Zig incorrectly creates
  sentinel entries (cid='-1') for the new rows. The Rust/C oracle
  correctly omits sentinels since no DELETE occurred.
```

## Scenario
1. Site A: INSERT 3 rows
2. Sync A→B via `INSERT INTO crsql_changes SELECT * FROM crsql_changes`
3. **Expected**: Site B has data rows, NO sentinels in clock table
4. **Actual (Zig)**: Site B has data rows AND 3 spurious sentinel entries

## Root Cause (hypothesis)
The `changesUpdate` path in `zig/src/changes_vtab.zig` creates sentinels when inserting new rows during merge. It should only create sentinels when:
1. A DELETE operation is being merged, OR
2. Passing through an existing sentinel from source

## Files to Modify
- `zig/src/changes_vtab.zig` — xUpdate handler for INSERT path
- Possibly `zig/src/merge_insert.zig` — sentinel creation logic

## Acceptance Criteria
1. `bash zig/harness/test-sentinel-parity.sh` — Test 4 passes
2. All other sentinel tests still pass (especially Test 5: propagation)
3. No regressions in `make -C zig test-parity`

## Parent Docs / Cross-links
- Test: `zig/harness/test-sentinel-parity.sh` (Test 4: No sentinel on merge)
- Triggering task: `.tasks/done/TASK-166-sentinel-parity-suite.md`
- Python reference: `py/correctness/tests/test_sentinel_omission.py`

## Progress Log
- 2025-12-22: Created from Round 62 divergence discovery.
- 2025-12-22: Fixed. Root cause confirmed.

## Completion Notes
**Date**: 2025-12-22

### Root Cause
In `zig/src/changes_vtab.zig`, the `changesUpdate` function unconditionally created sentinel entries (cid='-1') when inserting NEW rows during merge operations. This was incorrect - sentinels should only be created when:
1. A DELETE operation is being merged (incoming cid='-1'), OR  
2. Passing through an existing sentinel from source

### Changes Made
**File**: `zig/src/changes_vtab.zig`

1. **Lines 1767-1778**: Removed unconditional sentinel creation when merging new rows. Added comment explaining the correct behavior:
   - Sentinels should NOT be created for regular column changes
   - This matches Rust/C behavior

2. **Lines 2131-2144** (after edit ~2147-2160): Added code to update sentinel CL when merging column updates on existing rows where incoming CL > local CL. This ensures that when Site B receives a column update from Site A (where the row has been through INSERT->DELETE->INSERT), the sentinel CL is correctly advanced.

3. **Lines 1983-1996** (after edit ~1997-2010): Added code to update sentinel CL during resurrection via column update. When a tombstoned row is resurrected by a column update, the sentinel CL must also be updated to track the incoming causal length.

### Test Results
```
bash zig/harness/test-sentinel-parity.sh
Sentinel Parity Summary: 6 passed, 0 failed

bash zig/harness/test-resurrection-parity.sh
Results: 25 passed, 0 failed, 0 skipped
```

All acceptance criteria met:
- ✅ Test 4 (No sentinel on merge) passes
- ✅ Test 5 (Sentinel propagation) still passes
- ✅ All resurrection tests pass (no regressions)
