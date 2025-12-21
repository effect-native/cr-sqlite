# TASK-143 — Cross-open modification compatibility (trigger schema interoperability)

## Goal
Enable a database created by one CR-SQLite implementation (Zig vs Rust/C) to be **modified** by the other implementation without errors, and with correct change tracking.

This gap is currently explicitly marked as "known limitation" in `zig/harness/test-cross-open-parity.sh` (XO-003, XO-004, XO-006).

## Status
- State: done (superseded by TASK-147)
- Priority: high

## Problem Statement
Cross-open **read-only** works, but cross-open **modification** fails due to trigger schema incompatibility.

Evidence:
- `bash zig/harness/test-cross-open-parity.sh` reports:
  - 17 passed
  - 0 failed
  - 3 known-fail
- Known-fail tests:
  - XO-003: Zig creates → Rust modifies → Zig reads
  - XO-004: Rust creates → Zig modifies → Rust reads
  - XO-006: alternating modification between implementations

Root cause (as described in `zig/harness/test-cross-open-parity.sh`):
- Zig triggers embed `crsql_pack_columns()` directly in SQL.
- Rust/C triggers call helper functions `crsql_after_insert/update/delete()`.

When an implementation opens a DB created by the other and attempts INSERT/UPDATE/DELETE, the triggers call functions that are missing / rejected:
- Rust on Zig DB: "unsafe use of crsql_pack_columns" (or equivalent failure)
- Zig on Rust DB: "no such function: crsql_after_*"

## Files to Modify
(Exact scope to confirm during implementation planning; keep tight.)
- `zig/harness/test-cross-open-parity.sh` (convert known-fail → real assertions once fixed)
- One of:
  - `zig/src/as_crr.zig`
  - `zig/src/ffi/init.zig`
  - `zig/src/*.zig` trigger helper wiring (as needed)
- Potentially (if required): `core/src/*.c` trigger schema / init (only if we decide to unify the schema on the Rust/C side)

## Acceptance Criteria
1. `bash zig/harness/test-cross-open-parity.sh` reports:
   - XO-003 PASS
   - XO-004 PASS
   - XO-006 PASS
   - `KNOWN_FAIL: 0`
2. Cross-implementation modification succeeds without relying on sqlite-cr wrapper (must follow `AGENTS.md` rule: Zig tested via clean `nix run nixpkgs#sqlite` + explicit `.load $ZIG_EXT`).
3. Modifications performed by the "other" implementation are correctly reflected in:
   - base table data
   - `crsql_db_version()`
   - `__crsql_clock` / `crsql_changes` outputs, as asserted by the harness

## Parent Docs / Cross-links
- `zig/harness/test-cross-open-parity.sh` (XO-003/004/006 known limitation)
- `AGENTS.md` (Zig testing policy; sqlite-cr wrapper restrictions)

## Progress Log
- 2025-12-21: Created task from known-fail cross-open modification tests.

## Completion Notes
- 2025-12-21: Superseded by TASK-147 which has a more specific implementation plan (unify on Rust/C trigger schema).
