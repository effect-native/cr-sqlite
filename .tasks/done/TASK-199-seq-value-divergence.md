# TASK-199 — seq Value Divergence (Zig=1, Rust=0)

## Goal
Investigate and fix the `seq` column value divergence between Zig and Rust/C implementations.

## Status
- State: **DONE**
- Priority: MEDIUM (affects sync ordering in edge cases)
- Discovered: 2025-12-23 (TASK-192 prior DB parity testing)
- Fixed: 2025-12-25 (Round 76)

## Problem

When performing single operations, the `seq` column in `crsql_changes` differs:
- **Rust/C**: `seq=0`
- **Zig (before fix)**: `seq=1`

## Root Cause

In `crsqlAfterInsertFunc`, Zig called `getNextSeq()` unconditionally for `maybeMarkReinserted()`, even when no sentinel row existed to update. This consumed `seq=0` without effect, causing the first column's seq to start at 1.

**Rust/C behavior:**
```rust
// Only bump seq IF create_record_existed (resurrection case)
} else if create_record_existed {
    let seq = bump_seq(ext_data);
    update_create_record(...);
}
// Then bump seq for each column
for col in tbl_info.non_pks.iter() {
    let seq = bump_seq(ext_data);  // First call returns 0
    ...
}
```

**Zig (before fix):**
```zig
// Always called, even for fresh inserts
const seq_reinsert = site_identity.getNextSeq();  // Returns 0, wasted
_ = maybeMarkReinserted(...);  // Does nothing if no sentinel

// Then for each column
const seq2 = site_identity.getNextSeq();  // Returns 1, should be 0
```

## Fix

Modified `getOrCreatePkKey()` to return a struct with both `key` and `existed` flag, matching Rust/C's approach. Then only call `maybeMarkReinserted()` when `existed=true`.

**Files modified:**
- `zig/src/local_writes/after_write.zig`
  - Added `GetOrCreateKeyResult` struct
  - Modified `getOrCreatePkKey()` to return `{key, existed}` 
  - Modified `crsqlAfterInsertFunc` to only bump seq for reinsert if existed
  - Updated `crsqlAfterUpdateFunc` and `crsqlAfterDeleteFunc` callers

## Verification

```bash
# Before fix:
Zig:   t|^A	^A|x|1   # seq=1
Rust:  t|^A	^A|x|0   # seq=0

# After fix:
Zig:   t|^A	^A|x|0   # seq=0
Rust:  t|^A	^A|x|0   # seq=0
```

Test results:
- `test-clock-internals.sh`: 27 PASSED, 0 seq divergences
- `test-app-todo.sh`: 2 parity confirmed
- `test-parity.sh`: 367 PASSED

## Acceptance Criteria

1. [x] Document the intended semantics of `seq`
2. [x] Determine if divergence affects sync correctness (yes, ordering)
3. [x] Fix Zig to match Rust (done)

## Parent Docs / Cross-links

- Discovery: `.tasks/done/TASK-192-prior-db-oracle-parity.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from TASK-192 findings.
- 2025-12-25: Fixed in Round 76. Root cause: unconditional `getNextSeq()` for reinsert.

## Completion Notes
- Date: 2025-12-25
- Commit: 211de13e
