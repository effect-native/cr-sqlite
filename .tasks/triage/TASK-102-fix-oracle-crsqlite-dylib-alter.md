# TASK-102: Fix/replace local `lib/crsqlite.dylib` oracle for ALTER TABLE tests

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

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
- [ ] Oracle test scripts do not depend on a broken local dylib.
- [ ] One of the following is true:
  - [ ] `lib/crsqlite.dylib` passes a minimal `crsql_begin_alter`/`crsql_commit_alter` smoke test, OR
  - [ ] All oracle parity tests use `sqlite-cr` and document it explicitly.
- [ ] A clear reproduction snippet exists in Completion Notes.

## Progress Log
### 2025-12-20
- Repro (fails):
  - `timeout 30s nix run nixpkgs#sqlite -- /tmp/test.db -cmd ".load lib/crsqlite.dylib" "... crsql_commit_alter ..."`
- Repro (works):
  - `timeout 30s nix run github:subtleGradient/sqlite-cr -- /tmp/test.db "... crsql_commit_alter ..."`

## Completion Notes
