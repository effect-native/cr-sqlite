# TASK-XXX: Zig build fails on SQLITE_TRANSIENT alignment (Zig 0.15)

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [x] Blocked (reason: Zig build failure)
- [ ] Complete

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
- [ ] `nix run nixpkgs#zig -- build` succeeds on Zig 0.15
- [ ] `SQLITE_TRANSIENT` (and related sqlite destructor pointer constants) compile cleanly
- [ ] Harness scripts no longer need a prebuilt fallback for local builds

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite/zig
nix run nixpkgs#zig -- build
```

## Progress Log
### 2025-12-20
- Observed build failure while running `bash zig/harness/test-extdata.sh`

## Completion Notes
