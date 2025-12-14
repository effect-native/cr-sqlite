# TASK-030: Windows `.dll` Build + Loadability Recon

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md` ("Cross-platform Packaging & CI")
- Build config: `zig/build.zig`
- FFI/exports: `zig/src/ffi/init.zig`, `zig/src/ffi/root.zig`

## Description
Make the Windows packaging story crisp and testable.

Goal is not "full Windows CI" in one go; it is to either:
- produce a `.dll` artifact that exports `sqlite3_crsqlite_init` correctly, OR
- decisively document why it is blocked (missing toolchain, missing zig target support in CI, missing import lib, etc.)

## Files to Modify
- `zig/build.zig`
- `zig/README.md` (if usage/testing instructions need update)
- `research/zig-cr/92-gap-backlog.md` (status notes)
- (optional) `.github/workflows/*` (only if extremely small matrix tweak is safe)

## Acceptance Criteria
- [ ] `zig build -Dtarget=x86_64-windows-gnu` (or `-msvc` if chosen) produces `crsqlite.dll` (or documents why not).
- [ ] Exported symbol `sqlite3_crsqlite_init` present (document the command used to verify, e.g. `llvm-objdump` / `dumpbin`).
- [ ] `research/zig-cr/92-gap-backlog.md` updated with current Windows status and next concrete step.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started

## Completion Notes
[fill in when done]
