# TASK-079: Spec (RGRTDD) — `clset` virtual table module

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust reference: `core/rs/core/src/create_cl_set_vtab.rs`
- Rust integration tests: `core/rs/integration_check/src/t/test_cl_set_vtab.rs`
- Zig: (missing)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Define behavior for the `clset` module ("Causal Length Set" virtual table).

This task creates failing tests that define:
- Required naming conventions (`*_schema`).
- Which physical tables are created.
- That the base table is converted to CRR.

This is a **spec/tests-only** task.

## Files to Modify
- `zig/harness/test-clset-vtab.sh` (new) ✓ created
- `zig/harness/test-parity.sh` (wire into suite) — deferred to TASK-080
- `research/zig-cr/92-gap-backlog.md` — deferred to update phase

## Acceptance Criteria
- [x] Test fails on current Zig (module missing).
- [x] At minimum, tests cover:
  1. `CREATE VIRTUAL TABLE something_schema USING clset(...)` succeeds. ✓ Test 1
  2. Creating a virtual table without `_schema` suffix fails with a clear error. ✓ Test 2
  3. After create, physical tables exist:
     - `<base>` (storage) ✓ Test 3
     - `<base>__crsql_clock` ✓ Test 4
     - `<base>__crsql_pks` ✓ Test 5
  4. The base table is a CRR (e.g. `SELECT crsql_is_crr('<base>')` returns true). ✓ Test 6 (via trigger check)

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Created `zig/harness/test-clset-vtab.sh` with 10 tests covering all requirements.
- Tests verified against Rust/C extension (10/10 pass).
- Tests correctly fail on Zig extension (1 fail + 9 skip due to missing module).

## Completion Notes
Created comprehensive test suite at `zig/harness/test-clset-vtab.sh` covering:

**10 Tests Total:**
1. Virtual table creation with `_schema` suffix succeeds
2. Virtual table without `_schema` suffix fails with clear error
3. Physical base table exists after create
4. Clock table (`__crsql_clock`) exists after create
5. PKs table (`__crsql_pks`) exists after create
6. Base table is a CRR (verified via trigger presence)
7. INSERT into base table creates change records
8. DROP TABLE cleans up all related tables
9. CREATE without PRIMARY KEY fails with clear error
10. CREATE IF NOT EXISTS is idempotent

**Test Results:**
- Rust/C extension: 10 passed, 0 failed (GREEN baseline)
- Zig extension: 0 passed, 1 failed, 9 skipped (RED as expected)

**References used:**
- `core/rs/core/src/create_cl_set_vtab.rs` (module implementation)
- `core/rs/integration_check/src/t/test_cl_set_vtab.rs` (Rust tests)
- Existing harness patterns in `zig/harness/test-*.sh`

**Note:** Test 6 uses trigger presence check instead of `crsql_is_crr()` because that function is Zig-specific. This approach works cross-extension.
