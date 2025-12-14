# TASK-030: Windows `.dll` Build + Loadability Recon

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

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
- [x] `zig build -Dtarget=x86_64-windows-gnu` (or `-msvc` if chosen) produces `crsqlite.dll` (or documents why not).
- [x] Exported symbol `sqlite3_crsqlite_init` present (document the command used to verify, e.g. `llvm-objdump` / `dumpbin`).
- [x] `research/zig-cr/92-gap-backlog.md` updated with current Windows status and next concrete step.

## Progress Log
### 2025-12-14
- Task created during gap review; not yet started
- Started work on Windows DLL build

### 2025-12-14 (completion)
- Attempted `zig build -Dtarget=x86_64-windows-gnu` — **SUCCESS**
- Attempted `zig build -Dtarget=x86_64-windows-msvc` — **SUCCESS**
- Both targets produce valid PE32+ DLL at `zig-out/bin/crsqlite.dll`

## Completion Notes
### Date: 2025-12-14

**Result: SUCCESS** — Windows DLL builds work out of the box with no changes needed.

### Build Commands
```bash
# GNU target (MinGW ABI) - builds successfully
cd zig && nix run nixpkgs#zig -- build -Dtarget=x86_64-windows-gnu

# MSVC target (Windows SDK ABI) - builds successfully  
cd zig && nix run nixpkgs#zig -- build -Dtarget=x86_64-windows-msvc
```

### Output
- `zig-out/bin/crsqlite.dll` (1.4MB for GNU, 1.4MB for MSVC)
- `zig-out/bin/crsqlite.pdb` (debug symbols)
- `zig-out/lib/crsqlite.lib` (import library)

### Symbol Verification
Command used:
```bash
nix-shell -p llvmPackages.bintools --run "llvm-objdump --private-headers zig-out/bin/crsqlite.dll" | grep -A 15 "Export Table:"
```

Output (both targets):
```
Export Table:
 DLL name: crsqlite.dll
 Ordinal base: 1
 Ordinal      RVA  Name
       ...
       8   0x1030  sqlite3_crsqlite_init    <-- PRESENT ✅
```

### Why It Works
Zig's cross-compilation handles Windows targets natively. The build system:
1. Already excluded WASM-specific paths for non-WASM targets
2. Links against Windows kernel32/ntdll/advapi32 automatically
3. No platform-specific code changes were needed

### Next Steps
- CI integration: Add Windows matrix entry to `.github/workflows/zig-tests.yaml` (optional, low priority)
- Runtime testing: Validate DLL loads in actual Windows SQLite (requires Windows environment)
