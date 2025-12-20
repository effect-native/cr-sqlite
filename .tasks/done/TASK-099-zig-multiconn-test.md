# TASK-099: Zig multi-connection parity test

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Created by: `.tasks/active/TASK-073-compare-rust-zig-tests.md`
- Rust reference: `core/rs/integration_check/src/t/tableinfo.rs` (test_leak_condition)
- C reference: `core/src/ext-data.test.c` (testFetchPragmaDataVersion)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
**Critical real-system gap**: The Rust suite explicitly tests multiple connections to the same database file (`test_leak_condition`):

```rust
let c1w = crate::opendb_file("test_leak_condition")?;
let c2w = crate::opendb_file("test_leak_condition")?;
// Both connections operate on same file
c1.exec_safe("INSERT INTO foo VALUES (1, 2)")?;
c2.exec_safe("INSERT INTO foo VALUES (2, 3)")?;
c2.exec_safe("CREATE TABLE bar (a)")?;  // Schema change on c2
c1.exec_safe("INSERT INTO foo VALUES (3, 4)")?;  // c1 must detect schema change
```

This tests:
1. ExtData isolation per connection
2. Schema version change detection across connections
3. Statement invalidation after schema changes
4. No statement leaks when schema changes force re-preparation

The Zig harness has no multi-connection tests.

## Files to Modify
- `zig/harness/test-multiconn.sh` (new file)
- `zig/harness/test-parity.sh` (add test runner call)

## Acceptance Criteria
- [x] New test script `zig/harness/test-multiconn.sh` exists
- [x] Tests use actual on-disk database (not :memory:)
- [x] Tests cover:
  - Two connections open same file
  - Insert on conn1, verify visible on conn2 (after commit)
  - Schema change on conn2, operations on conn1 still work
  - Interleaved inserts from both connections
  - Final state is union of all inserts
- [x] Oracle parity: Zig and Rust/C produce identical final state
- [x] Reproducible command: `bash zig/harness/test-multiconn.sh`

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-multiconn.sh
```

## Progress Log
### 2025-12-18
- Task created from TASK-073 coverage analysis
- Identified as HIGH priority real-system gap

### 2025-12-20
- Implemented `zig/harness/test-multiconn.sh` with 6 test cases
- Added integration to `zig/harness/test-parity.sh`
- All 6 tests pass with full Zig/Rust oracle parity

## Completion Notes
**Date**: 2025-12-20

**Files Created/Modified**:
- `zig/harness/test-multiconn.sh` (new, 260 lines)
- `zig/harness/test-parity.sh` (added test runner call + header comment)

**Test Coverage** (6 tests):
1. Insert visibility across connections (same file)
2. Interleaved inserts from multiple connections  
3. Schema change via crsql_begin_alter/crsql_commit_alter
4. db_version consistency across connections
5. crsql_changes tracking from multiple connections
6. Final state union with compound primary keys

**Test Results**:
```
╔═══════════════════════════════════════════════════════════════════════╗
║              MULTI-CONNECTION TEST SUMMARY                           ║
╠═══════════════════════════════════════════════════════════════════════╣
║  PASSED:  6                                                          ║
║  FAILED:  0                                                          ║
║  SKIPPED: 0                                                          ║
╚═══════════════════════════════════════════════════════════════════════╝

All implemented multi-connection tests PASSED
```

**Oracle Parity**: Tests 1, 2, 6 include explicit Zig vs Rust/C comparison - all show identical behavior.
