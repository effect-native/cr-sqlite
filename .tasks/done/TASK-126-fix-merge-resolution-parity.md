# TASK-126: Fix merge resolution parity with oracle

## Status
- [x] Completed

## Priority
medium

## Assigned To
(completed)

## Parent Docs / Cross-links
- Test: `zig/harness/test-oracle-parity.sh` (Test 3a, 3b)
- Test: `zig/harness/test-parity.sh` (ValueWin test)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The Zig implementation's merge resolution differs from the Rust/C oracle:

**Test 3a: Remote wins with higher col_version**
- Zig: returns "local" (local value kept)
- Rust/C: returns "remote_winner" (remote value applied)

**Test 3b: site_id tiebreaker (lower site_id wins on equal col_version)**
- Zig: returns empty
- Rust/C: returns "low_site"

**ValueWin test (test-parity.sh)**
- Expected rows_impacted = 1
- Got: empty (merge not applied)

This suggests the merge logic in `changes_vtab.zig` or `merge_insert.zig` is not correctly determining when remote wins.

## Files to Modify
- `zig/src/changes_vtab.zig` — merge resolution logic
- `zig/src/merge_insert.zig` — merge helpers

## Acceptance Criteria
- [x] `zig/harness/test-oracle-parity.sh` Test 3a passes
- [x] `zig/harness/test-oracle-parity.sh` Test 3b passes
- [x] `zig/harness/test-parity.sh` ValueWin test passes
- [x] No regressions in other parity tests

## Progress Log

### 2024-12-20: Root Cause Found and Fixed

**Root Cause:**
The `setWinnerClock` and `setWinnerClockCached` functions in `merge_insert.zig` were attempting to bind a 16-byte site_id BLOB directly to the clock table's `site_id` column, but that column is declared as `INTEGER` (for storing ordinals, not raw blobs).

When applying remote changes via `INSERT INTO crsql_changes`, the incoming site_id is a 16-byte BLOB. The Rust/C oracle correctly converts this to an ordinal via the `crsql_site_id` table before storing in the clock table. The Zig implementation was missing this conversion step, causing a STRICT constraint violation ("cannot store BLOB value in INTEGER column").

This caused ALL remote change merges to fail silently (SQL error at the clock update step), which is why:
- Test 3a failed: remote change with higher col_version couldn't be applied
- Test 3b failed: site_id tiebreaker couldn't work because merges failed
- ValueWin failed: remote value couldn't win because clock update failed

**Fix Applied:**
Modified `merge_insert.zig`:
1. Added import for `site_identity` module
2. Updated `setWinnerClock()` to convert site_id blob to ordinal using `site_identity.getOrCreateSiteOrdinal()` before binding
3. Updated `setWinnerClockCached()` with the same fix

The clock table stores site_id as an integer ordinal (0 = local, 1+ = remote sites), and the `crsql_site_id` table maintains the mapping between ordinals and actual 16-byte site_id blobs.

## Completion Notes
- Date: 2024-12-20
- Files modified:
  - `zig/src/merge_insert.zig` (added site_identity import, fixed setWinnerClock and setWinnerClockCached)
- All acceptance criteria verified:
  - test-oracle-parity.sh: 18 passed, 0 failed
  - test-parity.sh: All rows_impacted tests pass including ValueWin
  - No regressions in test-filters.sh, test-rowid-slab.sh, test-alter.sh, test-noops.sh
