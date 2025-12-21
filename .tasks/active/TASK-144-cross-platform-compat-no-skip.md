# TASK-144 — Cross-platform wire compat: remove "SKIP: Rust/C extension not found" assumption

## Goal
Ensure the cross-platform compatibility harness is a reliable invalidation tool in CI/dev environments by reducing spurious SKIPs.

Currently `zig/harness/test-cross-platform-compat.sh` can SKIP entirely when it cannot find the Rust/C extension.

## Status
- State: active
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

## Completion Notes
(Empty until done.)
