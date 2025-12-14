# TASK-026-A: Build macOS Universal Binary

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Complete

## Priority
medium

## Assigned To
general

## Description
Create a macOS universal binary (aarch64 + x86_64) for the Zig CR-SQLite extension using the lipo-based approach documented in Round 23 research.

## Files to Modify
- `zig/Makefile` - Add universal binary target

## Acceptance Criteria
- [ ] `make universal` target exists in `zig/Makefile`
- [ ] Builds both aarch64-macos and x86_64-macos
- [ ] Uses `lipo -create` to combine into single binary
- [ ] Output at `zig-out-universal/lib/libcrsqlite.dylib`
- [ ] `lipo -info` shows both architectures
- [ ] All tests pass with universal binary

## Implementation Notes
From Round 23 research:
```makefile
build-macos-universal: build-macos-arm64 build-macos-x64
	lipo -create \
		zig-out-arm64/lib/libcrsqlite.dylib \
		zig-out-x64/lib/libcrsqlite.dylib \
		-output zig-out-universal/lib/libcrsqlite.dylib
```

## Progress Log
### 2025-12-14
- Task created from Round 23 research findings

## Completion Notes
[To be filled when complete]
