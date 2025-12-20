# TASK-097: Zig ExtData lifecycle parity test

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(completed)

## Parent Docs / Cross-links
- Created by: `.tasks/active/TASK-073-compare-rust-zig-tests.md`
- C reference: `core/src/ext-data.test.c`
- Rust reference: `core/rs/integration_check/src/t/tableinfo.rs` (test_leak_condition)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The C test suite (`ext-data.test.c`) tests ExtData lifecycle management:

1. `crsql_newExtData` - initial state (dbVersion=-1, pragmaSchemaVersion=-1)
2. `crsql_fetchPragmaSchemaVersion` - detects schema changes
3. `crsql_fetchPragmaDataVersion` - detects data changes from OTHER connections
4. `crsql_recreate_db_version_stmt` - rebuilds after schema change
5. `crsql_finalize` - cleans up statements
6. `crsql_freeExtData` - no leaks

The Zig implementation has internal ExtData management but no external tests verifying behavior matches C.

## Files to Modify
- `zig/harness/test-extdata.sh` (new file)
- `zig/harness/test-parity.sh` (add test runner call)

## Acceptance Criteria
- [x] New test script `zig/harness/test-extdata.sh` exists
- [x] Tests cover (via observable behavior, not internal state):
  - Schema changes trigger table info refresh
  - db_version correctly computed after schema changes
  - Multiple CRR tables tracked correctly
  - Dropping tables removes from tracked set
- [x] Oracle parity: same operations produce same observable results in Zig and Rust/C
- [x] Reproducible command: `bash zig/harness/test-extdata.sh`

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-extdata.sh
```

## Progress Log
### 2025-12-18
- Task created from TASK-073 coverage analysis

### 2025-12-20
- Created `zig/harness/test-extdata.sh` with 15 tests covering:
  - Test 1a-1b: Schema changes trigger table info refresh (2 tests)
  - Test 2a-2d: db_version correctly computed after schema changes (4 tests)
  - Test 3a-3b: Multiple CRR tables tracked correctly (2 tests)
  - Test 4a-4b: Dropping tables removes from tracked set (2 tests)
  - Test 5: Multi-connection data version detection (1 test)
  - Test 6a-6c: Oracle parity Zig vs Rust/C (3 tests)
  - Test 7: Leak condition / schema churn stability (1 test)
- Wired test into `zig/harness/test-parity.sh`
- All 15 tests PASS

## Completion Notes
**Date:** 2025-12-20

**Test count:** 15 tests (15 passed, 0 failed, 0 skipped)

**Files created/modified:**
- `zig/harness/test-extdata.sh` (new, 290 lines)
- `zig/harness/test-parity.sh` (updated to include test-extdata.sh runner)

**Test coverage mapping to C reference (ext-data.test.c):**
| C Test | Observable Behavior Test |
|--------|-------------------------|
| `textNewExtData` | Test 2a (db_version starts at 0) |
| `testFetchPragmaSchemaVersion` | Test 1a, 1b (schema changes update tracking) |
| `testRecreateDbVersionStmt` | Test 2b, 2c, 2d (db_version computed correctly) |
| `testFetchPragmaDataVersion` | Test 5 (multi-connection detection) |
| `test_leak_condition` (Rust) | Test 7 (schema churn stability) |

**Oracle parity confirmed:** Zig and Rust/C produce identical db_version values for INSERT/UPDATE sequences (Test 6a-6c all pass).

**No divergences found** between Zig and Rust/C implementations.
