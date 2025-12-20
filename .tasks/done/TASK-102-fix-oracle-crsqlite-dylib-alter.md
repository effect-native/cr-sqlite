# TASK-102: Fix/replace local `lib/crsqlite.dylib` oracle for ALTER TABLE tests

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
Zig Implementation Agent

## Parent Docs / Cross-links
- Oracle parity test: `zig/harness/test-alter-parity.sh`
- Root repo dylib (broken for ALTER): `lib/crsqlite.dylib`
- sqlite-cr wrapper (working oracle): `nix run github:subtleGradient/sqlite-cr`
- Rust alter implementation (reference): `core/rs/core/src/alter.rs`
- Origin task: `.tasks/active/TASK-094-alter-table-history-preservation.md`

## Description
TASK-094 uncovered that the repo-local oracle dylib (`lib/crsqlite.dylib`) fails during `crsql_commit_alter` with:

- `Error: stepping, failed compacting tables post alteration`
- `Error: sqlite3_close() returns 5: unable to close due to unfinalized statements or unfinished backups`

Meanwhile, `sqlite-cr` (nix wrapper) succeeds.

This task makes oracle tests reproducible and stable by either:
- fixing the local build artifact so it behaves like sqlite-cr, OR
- removing/renaming the misleading artifact and standardizing all oracle tests on sqlite-cr.

## Files to Modify
- `Makefile` and/or build scripts that produce `lib/crsqlite.dylib` (root or `core/Makefile`)
- `zig/harness/test-*-parity.sh` scripts (standardize oracle invocation)
- `README.md` (only if there is user-facing guidance about which dylib is authoritative)

## Acceptance Criteria
- [x] Oracle test scripts do not depend on a broken local dylib.
- [x] One of the following is true:
  - [ ] `lib/crsqlite.dylib` passes a minimal `crsql_begin_alter`/`crsql_commit_alter` smoke test, OR
  - [x] All oracle parity tests use `sqlite-cr` and document it explicitly.
- [x] A clear reproduction snippet exists in Completion Notes.

## Progress Log
### 2025-12-20
- Repro (fails):
  - `timeout 30s nix run nixpkgs#sqlite -- /tmp/test.db -cmd ".load lib/crsqlite.dylib" "... crsql_commit_alter ..."`
- Repro (works):
  - `timeout 30s nix run github:subtleGradient/sqlite-cr -- /tmp/test.db "... crsql_commit_alter ..."`

### 2025-12-20 (completion)
- **Decision**: Standardize all oracle parity tests on `sqlite-cr` instead of fixing local dylib
- **Rationale**: sqlite-cr is the authoritative, known-working oracle; local dylib has undiagnosed issues
- **Files modified**:
  - `zig/harness/test-oracle-parity.sh` - switched from local dylib to sqlite-cr
  - `zig/harness/test-fract-parity.sh` - switched from local dylib to sqlite-cr  
  - `zig/harness/test-rows-impacted-parity.sh` - switched from local dylib to sqlite-cr
  - `zig/harness/test-db-version-parity.sh` - switched from local dylib to sqlite-cr
  - `zig/harness/test-trigger-parity.sh` - switched from local dylib to sqlite-cr
  - `zig/harness/test-alter-parity.sh` - already using sqlite-cr (no changes needed)

## Completion Notes

### Root Cause
The local `lib/crsqlite.dylib` has an issue with the ALTER workflow where `crsql_commit_alter` fails with "stepping, failed compacting tables post alteration" and leaves unfinalized statements. The exact cause is unclear but may be related to a version mismatch or build configuration issue.

### Solution Chosen
**Standardize on sqlite-cr** - All oracle parity tests now use `nix run github:subtleGradient/sqlite-cr` as the Rust/C oracle instead of local dylib files. This approach:
1. Ensures reproducible tests across environments
2. Uses a known-working, well-maintained oracle
3. Documents the sqlite-cr dependency explicitly in each script

### Reproduction Snippets

**Local dylib (FAILS)**:
```bash
rm -f /tmp/test.db && timeout 30s nix run nixpkgs#sqlite -- /tmp/test.db -cmd ".load lib/crsqlite.dylib" "
SELECT crsql_begin_alter('test');
CREATE TABLE test(id PRIMARY KEY);
SELECT crsql_commit_alter('test');
"
# Output:
# Error: stepping, failed compacting tables post alteration
# Error: sqlite3_close() returns 5: unable to close due to unfinalized statements or unfinished backups
```

**sqlite-cr (SUCCEEDS)**:
```bash
rm -f /tmp/test.db && timeout 30s nix run github:subtleGradient/sqlite-cr -- /tmp/test.db "
SELECT crsql_begin_alter('test');
CREATE TABLE test(id PRIMARY KEY);
SELECT crsql_commit_alter('test');
"
# Output: OK
```

### Scripts Updated
All parity test scripts now document the sqlite-cr usage with this comment:
```bash
# Use sqlite-cr for Rust/C oracle (nix wrapper with cr-sqlite preloaded)
# NOTE: We use sqlite-cr instead of local dylib because the local dylib
# has known issues with crsql_commit_alter. sqlite-cr is the authoritative oracle.
# See: .tasks/active/TASK-102-fix-oracle-crsqlite-dylib-alter.md
```

### Test Commands
```bash
# Verify all scripts have valid syntax:
bash -n zig/harness/test-*-parity.sh

# Run individual parity tests (requires Zig extension built):
./zig/harness/test-alter-parity.sh
./zig/harness/test-oracle-parity.sh
./zig/harness/test-fract-parity.sh
./zig/harness/test-trigger-parity.sh
./zig/harness/test-db-version-parity.sh
./zig/harness/test-rows-impacted-parity.sh
```
