# TASK-166 — Sentinel emission parity test suite (consolidated)

## Goal
Create comprehensive sentinel tests verifying Zig matches Rust/C oracle for sentinel (cid='-1') emission rules.

## Status
- State: active
- Priority: high (wire format parity)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
Consolidates TASK-166 through TASK-169 into a single test file. These scenarios from Python `test_sentinel_omission.py` are not covered in Zig harness:

1. **No sentinel on INSERT**: Normal INSERT should NOT create cid='-1'
2. **Sentinel on DELETE**: DELETE MUST create cid='-1' with CL
3. **No sentinel on REPLACE**: INSERT OR REPLACE should NOT create sentinel
4. **No sentinel on merge**: Applying remote changes should NOT create new sentinels

## Files to Modify
- `zig/harness/test-sentinel-parity.sh` (new, ~300 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Each of 4 scenarios implemented as separate test function
2. Each test runs against both Zig and Rust/C oracle
3. Each test queries clock table for cid='-1' presence
4. All tests PASS with identical behavior
5. Sentinel propagation during sync verified (not created, just passed through)

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-sentinel-parity.sh - Sentinel emission rules

test_no_sentinel_on_insert() {
    # INSERT row
    # Query: SELECT * FROM t__crsql_clock WHERE cid = '-1'
    # Verify: no rows (sentinel not created)
}

test_sentinel_on_delete() {
    # INSERT then DELETE
    # Query: SELECT * FROM t__crsql_clock WHERE cid = '-1'
    # Verify: 1 row with correct CL
}

test_no_sentinel_on_replace() {
    # INSERT then INSERT OR REPLACE
    # Verify: no sentinel created
}

test_no_sentinel_on_merge() {
    # Site A: INSERT
    # Sync to Site B
    # Verify: Site B has data but NO sentinel in clock
    # Site A: DELETE (creates sentinel)
    # Sync to Site B
    # Verify: Site B has sentinel (propagated, not new)
}
```

## Parent Docs / Cross-links
- Python tests: `py/correctness/tests/test_sentinel_omission.py`
- Supersedes: TASK-167, TASK-168, TASK-169
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Consolidated from 4 individual tasks for efficient parallel execution.
- 2025-12-22: Implemented `zig/harness/test-sentinel-parity.sh` (300+ lines) with 6 test scenarios.
- 2025-12-22: Wired test into `zig/harness/test-parity.sh`.
- 2025-12-22: Test results: **5 passed, 1 failed**
  - PASS: Test 1 - No sentinel on INSERT (both = 0)
  - PASS: Test 2 - Sentinel on DELETE (both = 800)
  - PASS: Test 3 - No sentinel on INSERT OR REPLACE (both = 0)
  - FAIL: Test 4 - No sentinel on merge (Zig creates spurious sentinels)
  - PASS: Test 5 - Sentinel propagation on sync (both = 3)
  - PASS: Test 6 - Sentinel structure parity (counts match)

## Divergence Found
**Test 4 failure reveals a Zig implementation bug:**

When syncing INSERT changes to a site that doesn't have the row, the Zig 
implementation incorrectly creates a sentinel entry (`cid='-1'`) alongside 
the column changes. The Rust/C oracle correctly omits sentinels since no 
DELETE operation occurred.

**Root cause:** The `changesUpdate` path in the Zig changes vtab creates 
sentinels when inserting new rows during merge, but it should only create 
sentinels on actual DELETE operations.

**Evidence:**
```
Zig Site B after sync: sentinel_count=1 (WRONG)
Rust Site B after sync: sentinel_count=0 (CORRECT)
```

## Completion Notes
Test suite implementation complete. Files created/modified:
- `zig/harness/test-sentinel-parity.sh` (new, 568 lines)
- `zig/harness/test-parity.sh` (added test runner entry)

The test successfully validates 5/6 scenarios and detected a real divergence 
in scenario 4 (no sentinel on merge). A follow-up task should be created to 
fix the Zig implementation bug in the changesUpdate merge path.
