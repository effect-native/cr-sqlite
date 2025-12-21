# TASK-144 — Cross-platform wire compat: remove "SKIP: Rust/C extension not found" assumption

## Goal
Ensure the cross-platform compatibility harness is a reliable invalidation tool in CI/dev environments by reducing spurious SKIPs.

Currently `zig/harness/test-cross-platform-compat.sh` can SKIP entirely when it cannot find the Rust/C extension.

## Status
- State: done
- Priority: medium

## Problem Statement
`zig/harness/test-cross-platform-compat.sh` prints:
- `SKIP: Rust/C extension not found (need lib/crsqlite.dylib or core/dist/crsqlite.dylib)`

This means a key "interop" test can silently not run, making it easier to miss real compatibility regressions.

## Files to Modify
- `zig/harness/test-cross-platform-compat.sh`
- Potentially `zig/harness/test-parity.sh` (if it is responsible for calling compat tests)

## Acceptance Criteria
1. The compat harness runs (not SKIPs) in a fresh checkout after running a small, documented build step.
2. The harness outputs an actionable failure when the oracle cannot be built, instead of silently SKIP.
3. A single documented command exists to provision the Rust/C extension (either build from source, or locate downloaded artifact).

## Parent Docs / Cross-links
- `zig/harness/test-cross-platform-compat.sh`
- `scripts/update-crsqlite-oracle.sh` (may be related)

## Progress Log
- 2025-12-21: Created from observed SKIP in `test-cross-platform-compat.sh`.
- 2025-12-20: Implemented fix.

## Completion Notes
### Changes Made
1. **Oracle resolution fixed** (lines 29-51): Updated to look for platform-specific oracle files (`lib/crsqlite-darwin-aarch64.dylib`, etc.) instead of generic `lib/crsqlite.dylib`. This matches the pattern in `test-cross-open-parity.sh`.

2. **SKIP changed to FAIL** (line 28): When oracle is missing, script now outputs:
   ```
   FAIL: Rust/C oracle not found at <path>
   Run: ./scripts/update-crsqlite-oracle.sh
   ```
   And exits with code 1 (not 2 for SKIP).

3. **Extension init function added**: Added `sqlite3_crsqlite_init` to all `nix run nixpkgs#sqlite` invocations that load the Rust/C oracle (lines 88, 283, 468, 598). This was causing silent failures when exporting changes from Rust/C.

### Test Results
- **With oracle present**: Test runs to completion (2 failures are pre-existing compatibility issues in Test G: Resurrection and Test M: text with newlines - these are Zig implementation issues, not oracle resolution issues)
- **With oracle missing**: 
  ```
  FAIL: Rust/C oracle not found at /Users/tom/Developer/effect-native/cr-sqlite/lib/crsqlite-darwin-aarch64.dylib
  Run: ./scripts/update-crsqlite-oracle.sh
  EXIT_CODE: 1
  ```

### Verified
- `ls lib/crsqlite-darwin-*.dylib` confirms oracle exists
- Test no longer SKIPs when oracle is present
- Test FAILs (not SKIPs) with actionable message when oracle is missing
