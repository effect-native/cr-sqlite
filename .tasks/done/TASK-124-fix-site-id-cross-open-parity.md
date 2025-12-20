# TASK-124: Fix site_id preservation on cross-implementation DB open

## Status
- [x] Completed

## Priority
medium

## Assigned To
(completed)

## Parent Docs / Cross-links
- Divergence documented in: `.tasks/done/TASK-074-cross-impl-compat-expanded.md`
- Test: `zig/harness/test-oracle-parity.sh` (Test 4b, 4c)
- Zig site_id handling: `zig/src/site_identity.zig`
- Zig init handling: `zig/src/ffi/init.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
When Rust/C opens a database created by Zig, the site_id is not preserved correctly.

**Current behavior:**
- Zig creates DB with site_id: A6C2BD7D1EF644D4B72C5C97D0B50B78
- Rust/C opens same DB and reads site_id: (empty or different)

**Expected behavior:**
Both implementations should read the same site_id from an existing database.

**Investigation Notes:**
The issue might be due to missing version information in `crsql_master`. Rust/C implementation checks for a minimum version before accepting a database.

## Files to Modify
- `zig/src/ffi/init.zig` - initialization (version writing)
- `zig/src/site_identity.zig` - site_id storage/retrieval

## Acceptance Criteria
- [x] When Rust/C opens a Zig-created DB, site_id is preserved
- [x] When Zig opens a Rust/C-created DB, site_id is preserved
- [x] `zig/harness/test-oracle-parity.sh` Test 4b and 4c pass

## Completion Notes

**Date:** 2025-12-20

**Root Cause:**
When Rust/C opens a database, it checks for `crsqlite_version` in `crsql_master`. If this key is missing, Rust/C treats the database as uninitialized and generates a new site_id, overwriting the Zig-created site_id.

**Fix:**
Modified `zig/src/ffi/init.zig` to write `crsqlite_version|160300` to `crsql_master` during extension initialization. This matches what Rust/C expects to see in a properly initialized cr-sqlite database.

**Changes Made:**
1. Added `CRSQLITE_VERSION_INT = 160300` constant to match Rust/C version format
2. Added `writeVersionToMaster()` function to insert version on init
3. Called this function after creating `crsql_master` table

**Test Output (oracle parity test):**
```
Test 4b: Cross-open Zig DB with Rust/C preserves site_id
  PASS: Rust/C reads Zig's site_id correctly: 2CF88A20CF754064ABA66224BF453B1A
Test 4c: Cross-open Rust/C DB with Zig preserves site_id
  PASS: Zig reads Rust/C's site_id correctly: 45CBAA5355F24CEC9060A758300B8261
```

**No Regressions:**
The full parity test suite was run and no new failures were introduced. Existing failures are pre-existing issues unrelated to this change.
