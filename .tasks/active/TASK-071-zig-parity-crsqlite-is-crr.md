# TASK-071: Zig parity — Cover remaining C suites (crsqlite + is-crr)

## Status
- [x] Complete

## Priority
high

## Assigned To
(completed)

## Parent Docs / Cross-links
- C test runner: `core/src/tests.c`
- Suites to cover:
  - `core/src/crsqlite.test.c`
  - `core/src/is-crr.test.c`
- Zig parity runner: `zig/harness/test-parity.sh`
- Existing Zig harness scripts: `zig/harness/test-is-crr.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The C reference test runner (`core/src/tests.c`) includes suites for base extension behaviors (`crsqlite`) and CRR detection (`is-crr`).

Some of this may already be covered by existing Zig harness scripts, but the parity runner must make this explicit and non-optional.

This task ensures:
- We have Zig-side tests that correspond to the C suite assertions.
- `zig/harness/test-parity.sh` actually runs them (so we're not "green" due to missing coverage).

## Files to Modify
- `zig/harness/test-parity.sh`
- `zig/harness/test-crsqlite.sh` (new, if needed)
- `zig/harness/test-is-crr.sh` (if wiring/assertions need adjustments)

## Acceptance Criteria
- [x] `make -C zig test-parity` exercises `crsqlite` and `is_crr` equivalently to the C runner.
- [x] No parity suite remains uncovered from the set in `core/src/*.test.c`.
- [x] Evidence captured in this card: commands + outputs.

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".

### 2025-12-20
- Analyzed C test suites in `core/src/crsqlite.test.c` and `core/src/is-crr.test.c`
- Found `test-is-crr.sh` already exists but was NOT wired into `test-parity.sh`
- Existing coverage analysis:
  - `is-crr.test.c`: All 3 tests covered by `test-is-crr.sh`
  - `crsqlite.test.c`:
    - `teste2e()`: Covered by `test-e2e-sync.sh`
    - `testSelectChangesAfterChangingColumnName()`: Covered by `test-alter.sh`
    - `testLamportCondition()`: Covered by `test-e2e-sync.sh`
    - `noopsDoNotMoveClocks()`: Covered by `test-noops.sh`
    - `testPullingOnlyLocalChanges()`: **NOT covered** - needed new test
- Created `zig/harness/test-crsqlite.sh` with:
  - `testPullingOnlyLocalChanges` tests (site_id filtering)
  - Data type preservation tests (float, blob, text)
- Updated `zig/harness/test-parity.sh` to explicitly run:
  - `test-is-crr.sh` (3 tests)
  - `test-crsqlite.sh` (6 tests)
- All tests pass

## Completion Notes
### 2025-12-20

**C Suite → Zig Harness Mapping:**

| C Test Function | Zig Harness Script | Status |
|-----------------|-------------------|--------|
| `crsqlIsCrrTestSuite()` | `test-is-crr.sh` | ✅ All 3 tests pass |
| `testTableIsNotCrr()` | `test-is-crr.sh:tableIsNotCrr` | ✅ Pass |
| `testCrrIsCrr()` | `test-is-crr.sh:crrIsCrr` | ✅ Pass |
| `testDestroyedCrrIsNotCrr()` | `test-is-crr.sh:destroyedCrrIsNotCrr` | ✅ Pass |
| `crsqlTestSuite()` | Multiple scripts | ✅ All covered |
| `teste2e()` | `test-e2e-sync.sh` | ✅ Pass |
| `testSelectChangesAfterChangingColumnName()` | `test-alter.sh` | ✅ Pass |
| `testLamportCondition()` | `test-e2e-sync.sh` | ✅ Pass |
| `noopsDoNotMoveClocks()` | `test-noops.sh` | ✅ Pass |
| `testPullingOnlyLocalChanges()` | `test-crsqlite.sh` (NEW) | ✅ Pass |

**Commands + Outputs:**

```bash
$ bash zig/harness/test-is-crr.sh
Testing tableIsNotCrr... PASS
Testing crrIsCrr... PASS
Testing destroyedCrrIsNotCrr... PASS
All is_crr tests passed!

$ bash zig/harness/test-crsqlite.sh
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Suite: crsqlite (core/src/crsqlite.test.c)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test: PullingOnlyLocalChanges - local changes have matching site_id
  PASS: count(*) = 2 for local changes (site_id matches)
Test: PullingOnlyLocalChanges - no remote changes in fresh DB
  PASS: count(*) = 0 for remote changes (no synced data)
Test: PullingOnlyLocalChanges - synced changes have remote site_id
  PASS: count(DISTINCT pk) = 1 for remote changes after sync
Test: Data types - float (scientific notation) preserved
  PASS: Float 2.0e2 stored correctly as real|200.0
Test: Data types - blob preserved
  PASS: Blob X'1232' preserved correctly
Test: Data types - text preserved
  PASS: Text 'hello world' preserved correctly

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
crsqlite Tests Summary: 6 passed, 0 failed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
All crsqlite tests passed!
```

**Files Modified:**
- `zig/harness/test-crsqlite.sh` (NEW - 149 lines)
- `zig/harness/test-parity.sh` (added wiring for test-is-crr.sh and test-crsqlite.sh)

**Files NOT Modified (already correct):**
- `zig/harness/test-is-crr.sh` - existing tests were complete and correct
