# TASK-092: Oracle Parity — db_version advancement timing

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust db_version logic: `core/rs/core/src/db_version.rs`
- Zig db_version logic: `zig/src/crsqlite.zig` (crsql_db_version, crsql_next_db_version)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_db_version()` and `crsql_next_db_version()` increment at exactly the same moments in both implementations.

This is an **oracle test**: The db_version is critical for sync protocols. If Zig and Rust/C increment it at different times (e.g., per-statement vs per-transaction), sync will break.

## Files to Modify
- `zig/harness/test-db-version-parity.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Test performs identical operations in both implementations and records db_version after each.
- [x] Operations tested:
  1. Initial state (should be 0 or 1)
  2. Single INSERT → record db_version
  3. Single UPDATE → record db_version
  4. Multiple INSERTs in one transaction → record db_version at COMMIT
  5. DELETE → record db_version
  6. No-op UPDATE (same value) → db_version should NOT change
  7. Merge from remote (crsql_changes INSERT) → record db_version
  8. No-op merge (lower col_version) → record db_version
- [ ] All db_version values match exactly between implementations. **DIVERGENCE FOUND - see below**
- [x] `crsql_next_db_version()` returns `db_version + 1` in both.
- [x] Test fails if any db_version diverges.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

### 2025-12-18 (work session)
- Created `zig/harness/test-db-version-parity.sh` with 8 test cases
- Wired into `zig/harness/test-parity.sh`
- Ran tests via `make -C zig test-parity`

#### Commands Run
```bash
bash /Users/tom/Developer/effect-native/cr-sqlite/zig/harness/test-db-version-parity.sh
make -C zig test-parity
```

#### Test Results Summary
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
db_version Parity Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PASSED:     12
  FAILED:     1
  DIVERGENCES: 1 (critical - will break sync)
```

#### Full Test Output (db_version values at each step)
```
Test 1: Initial db_version state
  Rust/C: DB_VERSION=0 NEXT_DB_VERSION=1 
  Zig:    DB_VERSION=0 NEXT_DB_VERSION=1 
  PASS: Initial db_version matches
  PASS: next_db_version = db_version + 1 (Rust/C)
  PASS: next_db_version = db_version + 1 (Zig)

Test 2: Single INSERT -> db_version
  Rust/C: BEFORE_INSERT_VERSION=0 AFTER_INSERT_VERSION=1 NEXT_DB_VERSION=2 
  Zig:    BEFORE_INSERT_VERSION=0 AFTER_INSERT_VERSION=1 NEXT_DB_VERSION=2 
  PASS: Single INSERT db_version matches

Test 3: Single UPDATE -> db_version
  Rust/C: BEFORE_UPDATE_VERSION=1 AFTER_UPDATE_VERSION=2 
  Zig:    BEFORE_UPDATE_VERSION=1 AFTER_UPDATE_VERSION=2 
  PASS: Single UPDATE db_version matches

Test 4: Multiple INSERTs in transaction -> db_version at COMMIT
  Rust/C: BEFORE_TX_VERSION=0 AFTER_INSERT_1_VERSION=0 AFTER_INSERT_2_VERSION=0 AFTER_INSERT_3_VERSION=0 AFTER_COMMIT_VERSION=1 
  Zig:    BEFORE_TX_VERSION=0 AFTER_INSERT_1_VERSION=0 AFTER_INSERT_2_VERSION=0 AFTER_INSERT_3_VERSION=0 AFTER_COMMIT_VERSION=1 
  PASS: Multiple INSERTs in TX db_version matches

Test 5: DELETE -> db_version
  Rust/C: BEFORE_DELETE_VERSION=1 AFTER_DELETE_VERSION=2 
  Zig:    BEFORE_DELETE_VERSION=1 AFTER_DELETE_VERSION=2 
  PASS: DELETE db_version matches

Test 6: No-op UPDATE (same value) -> db_version should NOT change
  Rust/C: BEFORE_NOOP_VERSION=1 AFTER_NOOP_VERSION=2 
  Zig:    BEFORE_NOOP_VERSION=1 AFTER_NOOP_VERSION=1 
  DIVERGENCE DETECTED:
  Rust/C (oracle):
    BEFORE_NOOP_VERSION=1
    AFTER_NOOP_VERSION=2
  Zig (candidate):
    BEFORE_NOOP_VERSION=1
    AFTER_NOOP_VERSION=1
  FAIL: No-op UPDATE db_version diverges

Test 7: Merge from remote (crsql_changes INSERT) -> db_version
  Rust/C: BEFORE_MERGE_VERSION=1 AFTER_MERGE_VERSION=2 
  Zig:    BEFORE_MERGE_VERSION=1 AFTER_MERGE_VERSION=2 
  PASS: Merge from remote db_version matches
  PASS: Merge correctly advanced db_version (Rust/C: 1 -> 2)
  PASS: Merge correctly advanced db_version (Zig: 1 -> 2)

Test 8: No-op merge (lower col_version) -> db_version should NOT change
  Rust/C: BEFORE_NOOP_MERGE_VERSION=3 AFTER_NOOP_MERGE_VERSION=3 
  Zig:    BEFORE_NOOP_MERGE_VERSION=3 AFTER_NOOP_MERGE_VERSION=3 
  PASS: No-op merge db_version matches
  PASS: No-op merge correctly did not advance db_version
```

## Divergence Discovered

**Test 6: No-op UPDATE (same value)**

| Implementation | Before | After |
|---------------|--------|-------|
| Rust/C (oracle) | 1 | 2 (advances) |
| Zig (candidate) | 1 | 1 (no change) |

**Analysis:**
- Rust/C implementation advances db_version even when UPDATE sets a column to its existing value
- Zig implementation correctly detects no change occurred and does NOT advance db_version
- This is a semantic divergence that could affect sync protocols expecting version advancement

**Sync Impact:**
- If sync protocol uses db_version to detect "any change happened", Zig may not signal no-op updates
- However, since the data hasn't actually changed, this might be intentionally more efficient in Zig
- Need clarification: Is this a bug in Zig (should match Rust) or an intentional optimization?

## Completion Notes
- Test script created and wired into suite
- Critical divergence discovered in no-op UPDATE handling
- Filed for follow-up: Determine if Zig behavior should match Rust/C or if Rust/C has a bug
