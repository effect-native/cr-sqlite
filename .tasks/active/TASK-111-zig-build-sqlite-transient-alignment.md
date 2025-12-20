# TASK-111: Zig build fails on SQLITE_TRANSIENT alignment (Zig 0.15)

## Status
- [x] Planned
- [x] Assigned
- [ ] In Progress
- [ ] Blocked (reason: Zig 0.15 build failure)
- [x] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Triggered by: `.tasks/done/TASK-097-zig-extdata-lifecycle-test.md`
- Related file: `zig/src/ffi/api.zig`

## Description
Running `nix run nixpkgs#zig -- build` intermittently fails (or fails on some machines/configs) on Zig 0.15 with an alignment error for the `SQLITE_TRANSIENT` constant:

```
src/ffi/api.zig:68:56: error: pointer type '?*const fn (?*anyopaque) callconv(.c) void' requires aligned address
pub const SQLITE_TRANSIENT: DestructorFn = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
```

This blocks relying on a fresh Zig build inside harness scripts (though prebuilt `lib/crsqlite-zig-*` can be used as a fallback).

## Files to Modify
- `zig/src/ffi/api.zig`
- (maybe) `zig/build.zig` (if a version-gated workaround is required)

## Acceptance Criteria
- [x] `nix run nixpkgs#zig -- build` succeeds on Zig 0.15
- [x] `SQLITE_TRANSIENT` (and related sqlite destructor pointer constants) compile cleanly
- [ ] Harness scripts no longer need a prebuilt fallback for local builds

## Reproducible Command
```bash
cd zig
nix run nixpkgs#zig -- build
```

## Progress Log
### 2025-12-20
- Observed build failure while running `bash zig/harness/test-extdata.sh`
- Verified Zig version: `nix run nixpkgs#zig -- version` → `0.15.2`
- Updated `zig/src/ffi/api.zig` to define `SQLITE_TRANSIENT` via `@bitCast` to avoid Zig 0.15 function-pointer alignment checks for `@ptrFromInt`

## Completion Notes
- 2025-12-20: Fixed Zig 0.15 compile by avoiding `@ptrFromInt` for `SQLITE_TRANSIENT`.
- Verified: `cd zig && nix run nixpkgs#zig -- build` (Zig 0.15.2) succeeds.
