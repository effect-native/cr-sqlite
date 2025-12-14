# TASK-026-A: Build macOS Universal Binary

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [x] Complete

## Priority
medium

## Assigned To
general

## Description
Create a macOS universal binary (aarch64 + x86_64) for the Zig CR-SQLite extension using the lipo-based approach documented in Round 23 research.

## Files to Modify
- `zig/Makefile` - Add universal binary target

## Acceptance Criteria
- [x] `make universal` target exists in `zig/Makefile`
- [x] Builds both aarch64-macos and x86_64-macos
- [x] Uses `lipo -create` to combine into single binary
- [x] Output at `zig-out-universal/lib/libcrsqlite.dylib`
- [x] `lipo -info` shows both architectures
- [x] All tests pass with universal binary

## Implementation Notes
From Round 23 research:
```makefile
build-macos-universal: build-macos-arm64 build-macos-x64
	mkdir -p zig-out-universal/lib
	lipo -create \
		zig-out-arm64/lib/libcrsqlite.dylib \
		zig-out-x64/lib/libcrsqlite.dylib \
		-output zig-out-universal/lib/libcrsqlite.dylib
```

### Critical: Distinct --prefix per Architecture
Zig's `build.zig` outputs to `zig-out/` by default. To build two architectures without stomping outputs:

```bash
# Build aarch64
zig build -Dtarget=aarch64-macos --prefix zig-out-arm64

# Build x86_64
zig build -Dtarget=x86_64-macos --prefix zig-out-x64
```

### Environment Notes
- On Apple Silicon Mac, both targets can be built locally (no remote builder needed)
- Zig cross-compiles to x86_64-macos natively without additional dependencies
- Verify with: `file zig-out-arm64/lib/libcrsqlite.dylib` (should show "arm64")
- Verify with: `file zig-out-x64/lib/libcrsqlite.dylib` (should show "x86_64")

## Progress Log
### 2025-12-14
- Task created from Round 23 research findings

## Completion Notes
### 2025-12-14
Implemented `make universal` target in `zig/Makefile`:

**Changes made:**
- Added `build-arm64` target: builds aarch64-macos to `zig-out-arm64/`
- Added `build-x64` target: builds x86_64-macos to `zig-out-x64/`
- Added `universal` target: depends on both, combines with `lipo -create`
- Updated `clean` target to remove all new output directories
- Updated `help` target to document new targets

**Verification results:**
```
$ lipo -info zig-out-universal/lib/libcrsqlite.dylib
Architectures in the fat file: x86_64 arm64

$ nix run nixpkgs#sqlite -- :memory: -cmd '.load zig-out-universal/lib/libcrsqlite' -cmd 'SELECT crsql_version()'
0.0.1-zig-scaffold
```

Universal binary loads and works correctly on macOS.
