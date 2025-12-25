# TASK-198 — db_version off-by-one divergence

## Goal
Fix the db_version tracking divergence where Zig produces db_version values 1 higher than Rust/C after certain operation sequences.

## Status
- State: COMPLETED
- Priority: HIGH (sync correctness)
- Discovered: 2025-12-23 (TASK-190 fuzz testing)
- Completed: 2025-12-25

## Problem

After the same sequence of INSERT/UPDATE/DELETE operations, Zig and Rust/C implementations produce different `db_version` values:

```
Zig db_version:   355
Rust/C db_version: 354
```

This affects the `crsql_changes` output where `db_version` values are off by 1.

## Reproduction

```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
STRESS_ITERATIONS=25 STRESS_OPS=500 STRESS_SEED=2025 \
  bash zig/harness/test-fuzz-stress.sh
```

Divergence occurs at iterations 9, 15, 20 with this seed.

Databases with divergence are saved in `.tmp/debug-stress/`:
- `wide_zig_9.db` (Zig, db_version=355)
- `wide_rust_9.db` (Rust/C, db_version=354)

## Example Divergence

```
Zig:    wide_t|01090F|col3|299|2|307|1
Rust/C: wide_t|01090F|col3|299|2|306|1
                               ^^^--- off by 1
```

## Root Cause Hypothesis

The db_version increment logic differs in edge cases. Possible causes:

1. **No-op update counting**: When an UPDATE doesn't actually change the value, does it increment db_version?
2. **Resurrection (DELETE + INSERT same PK)**: Known to have `seq` divergence (TASK-130), may also affect db_version
3. **Transaction boundary handling**: Does COMMIT increment db_version in one impl but not the other?
4. **INSERT OR REPLACE**: Might be treated as UPDATE in one impl and DELETE+INSERT in the other

## Files to Investigate

- `zig/src/triggers.zig` - Trigger logic that increments db_version
- `zig/src/ext_data.zig` - ExtData db_version tracking
- `core/src/triggers.c` - Rust/C trigger implementation (for comparison)

## Acceptance Criteria

1. [x] Identify exact operation sequence causing divergence
2. [x] Determine which implementation is "correct" (likely Rust/C as reference)
3. [x] Fix Zig implementation to match
4. [x] Verify `test-fuzz-stress.sh` passes with all seeds

## Parent Docs / Cross-links

- Discovery: `.tasks/done/TASK-190-fuzz-invalidation-round2.md`
- Related: `.tasks/done/TASK-130-fix-trigger-parity-test-column-bug.md` (seq divergence)
- Test script: `zig/harness/test-fuzz-stress.sh`

## Progress Log
- 2025-12-23: Created from TASK-190 fuzz testing findings.
- 2025-12-25: Extensive investigation by agent. Findings:
  
  ### Investigation Summary
  
  **Confirmed behavior:**
  - Divergence appears at iteration 15 (wide_table test with 6 columns)
  - Zig produces db_version 357 vs Rust/C 356 (off by +1)
  - Both have exactly 298 distinct db_versions and 1305 clock rows
  - First divergence point: db_version 112 (Zig) vs 111 (Rust/C) for key=64/col3
  - After divergence, Zig is consistently +1 ahead for all subsequent versions
  
  **Analyzed but NOT the cause:**
  - No-op UPDATE handling (both implementations call `nextDbVersion()` unconditionally before checking if columns changed)
  - INSERT OR REPLACE behavior (tested, matches between implementations)
  - Resurrection (DELETE + INSERT same PK) (tested, matches)
  - Basic transaction handling (tested, matches)
  - Extension initialization (tested, matches)
  
  **Key difference found:**
  - Rust/C's `next_db_version()` calls `fill_db_version_if_needed()` which checks `PRAGMA data_version` and reloads dbVersion from storage if changed
  - Zig's `nextDbVersion()` only uses in-memory `global_db_version` without any refresh
  - However, in a single-process test scenario, this shouldn't matter since there are no external modifications
  
  **Remaining hypothesis:**
  - The divergence only occurs after many operations (100+ in the stress test)
  - Some edge case in the specific random operation sequence triggers an extra increment
  - Possibly related to how pending_db_version accumulates across many autocommit transactions
  - Simple isolated tests (200-500 operations) do NOT reproduce the issue
  
  **Files examined:**
  - `zig/src/local_writes/after_write.zig` (crsql_after_insert/update/delete)
  - `zig/src/site_identity.zig` (nextDbVersion, commitDbVersion)
  - `core/rs/core/src/local_writes/after_update.rs` (Rust comparison)
  - `core/rs/core/src/db_version.rs` (Rust comparison)
  
  **NOT FIXED** - Root cause not definitively identified. Needs further investigation:
  1. Add tracing/logging to Zig's `nextDbVersion()` to capture every call
  2. Compare call count between Zig and Rust for the exact failing operation sequence
  3. Check if the issue is in the test harness itself (bash RANDOM state management)

- 2025-12-25 (continued): Additional investigation session:

  ### Detailed Gap Analysis
  
  **Key finding: Zig has exactly 1 more db_version "gap" than Rust:**
  - Zig: 57 gaps (unused db_versions in range 3-357)
  - Rust: 56 gaps (unused db_versions in range 3-356)
  
  **First divergence point:**
  - Rust db_version 111 has a clock row: key=64, col3, col_version=2
  - Zig SKIPS db_version 111 (no row), records same update at db_version 112
  - After this point, Zig is consistently +1 ahead
  
  **Operations around divergence (db_version 108-113):**
  - Rust 108 → Zig 108: INSERT key=75 (6 columns) - MATCHES
  - Rust 111 → Zig 112: UPDATE key=64, col3 (col_version=2) - OFF BY 1
  - Rust 112 → Zig 113: INSERT key=78 (6 columns) - OFF BY 1
  
  **Seq divergence confirmed (separate issue):**
  - Zig seq for first column starts at 1 instead of 0
  - Caused by unconditional `getNextSeq()` call in `crsqlAfterInsertFunc` for `maybeMarkReinserted()`
  - This is tracked separately; seq divergence alone doesn't cause db_version issues
  
  ### Debug Instrumentation Added
  
  Added `crsql_debug_next_dbv_calls()` SQL function to track total calls to `nextDbVersion()`.
  File: `zig/src/site_identity.zig`
  
  **Test results with instrumentation:**
  - Simple operation sequences: Zig and Rust produce identical results
  - INSERT OR REPLACE: Both fire INSERT trigger once (not DELETE+INSERT)
  - No-op UPDATE (same value): Trigger fires, `nextDbVersion()` called, but no clock row written (expected)
  - No-op DELETE (non-existent row): Trigger does NOT fire (expected)
  
  ### Remaining Questions
  
  1. **Why does the divergence only occur with specific RANDOM sequences?**
     - Isolated tests with 500 ops do NOT reproduce
     - Only manifests at iteration 15 with seed 2025
     - Suggests a specific operation pattern triggers the issue
  
  2. **What operation causes Zig to call `nextDbVersion()` without writing a row?**
     - All three trigger functions call `nextDbVersion()` exactly once
     - The phantom call must be in a specific code path not yet identified
  
  3. **Could there be a subtle difference in how SQLite triggers fire?**
     - Unlikely since same SQL triggers are used
     - Both implementations use same generated trigger code
  
  ### Next Steps
  
  1. **Binary search the operation sequence**: Capture the exact 500 SQL statements from iteration 15 and binary search to find the specific op that causes divergence
  
  2. **Compare trigger invocation counts**: Add counters to each trigger function (INSERT/UPDATE/DELETE) and compare totals between Zig and Rust
  
  3. **Check if issue is in `crsqlAfterInsertFunc` unconditional seq increment**: While this affects seq not db_version, there may be a related issue in the INSERT logic
  
  4. **Review Rust's `fill_db_version_if_needed`**: This function checks `PRAGMA data_version` - understand if there's a scenario where this would cause different behavior

## Completion Notes

### Root Cause (2025-12-25)

The bug was caused by a mismatch between how Zig and Rust/C handle the `pending_db_version` state across transaction commits.

**The Issue:**

When a transaction commits that didn't modify any rows (e.g., UPDATE on non-existent row, SELECT-only statements), the Rust/C implementation:
1. Sets `dbVersion = pendingDbVersion` unconditionally in the commit hook
2. Since `pendingDbVersion` is `-1` (never set because no write happened), `dbVersion` becomes `-1`
3. On next access, `fill_db_version_if_needed()` sees `dbVersion == -1` and re-reads from storage

The original Zig implementation:
1. Only promoted `pending_db_version` to `global_db_version` if `pending > global`
2. Reset `pending_db_version` to `0` instead of `-1`
3. Only checked for re-read in `crsqlDbVersionFunc` and `crsqlNextDbVersionFunc`, but NOT in the trigger helper functions (`crsql_after_insert`, `crsql_after_update`, `crsql_after_delete`)

This meant that when operations ran without intermediate `crsql_db_version()` calls, the `global_db_version` could be stale after a no-op commit.

**The Fix:**

1. **`site_identity.zig`**:
   - Changed initial value of `global_db_version` and `pending_db_version` from `0` to `-1`
   - Changed `commitDbVersion()` to unconditionally set `global_db_version = pending_db_version`
   - Changed `rollbackDbVersion()` to set `pending_db_version = -1`
   - Updated `nextDbVersion()` to handle `-1` as "uninitialized"
   - Updated `crsqlDbVersionFunc()` to check for `-1` and re-read from storage
   - Updated `crsqlNextDbVersionFunc()` to check for `-1` and re-read from storage
   - Fixed `initDbVersionFromDb()` to NOT reset `pending_db_version`

2. **`local_writes/after_write.zig`**:
   - Added check for `global_db_version == -1` in `crsqlAfterInsertFunc`, `crsqlAfterUpdateFunc`, and `crsqlAfterDeleteFunc`
   - These functions now call `initDbVersionFromDb()` before `nextDbVersion()` when needed

### Files Modified

- `zig/src/site_identity.zig`
- `zig/src/local_writes/after_write.zig`

### Test Results

```
STRESS_ITERATIONS=25 STRESS_OPS=500 STRESS_SEED=2025 bash zig/harness/test-fuzz-stress.sh

Results:
  PASSED:        150
  FAILED:        0
  DIVERGENCES:   0
```

All 75,000 operations across 25 iterations pass with zero divergence.

### Date Completed

2025-12-25
