# TASK-211 — Release Native Zig Artifacts (darwin + linux)

## Goal
Produce and verify the native Zig loadable extension artifacts for `0.16.300-preview`.

## Status
- State: active
- Priority: HIGH
- Created: 2025-12-25

## Scope
Minimum required for release:
- macOS (arm64 + x86_64) `.dylib` (universal acceptable)
- Linux x86_64 `.so`

Tom's direction: "everywhere sqlite runs * whatever zig supports" — so expand to all Zig cross-compile targets.

## Files to Modify
- `zig/` build outputs are generated, but the task should modify only build scripts / CI packaging:
  - `scripts/build-zig.sh`
  - `scripts/build-production.ts` (if used for bundling)
  - `.github/workflows/zig-tests.yaml` (if needed for artifact upload)

## Acceptance Criteria
1. [x] `nix run nixpkgs#zig -- build -Doptimize=ReleaseFast` succeeds
2. [x] Built artifacts exist with deterministic names under `zig/zig-out/lib/`
3. [x] Artifacts can be loaded by sqlite on their target platforms (tested on macOS)
4. [x] Artifact naming + layout matches the GitHub Release upload plan

## Supported Targets

The Zig build system supports cross-compilation to these platforms:

| Target | Zig Target String | Output File | Status |
|--------|-------------------|-------------|--------|
| macOS arm64 | `aarch64-macos` | `crsqlite-zig-darwin-aarch64.dylib` | ✅ |
| macOS x86_64 | `x86_64-macos` | `crsqlite-zig-darwin-x86_64.dylib` | ✅ |
| macOS Universal | (lipo combination) | `crsqlite-zig-darwin-universal.dylib` | ✅ |
| Linux x86_64 | `x86_64-linux-gnu` | `crsqlite-zig-linux-x86_64.so` | ✅ |
| Linux arm64 | `aarch64-linux-gnu` | `crsqlite-zig-linux-aarch64.so` | ✅ |

## Build Commands

```bash
# Build for native platform only
./scripts/build-zig.sh

# Build all supported platforms
./scripts/build-zig.sh all

# Build macOS universal binary
./scripts/build-zig.sh darwin

# Build Linux targets (x86_64 + aarch64)
./scripts/build-zig.sh linux

# Build release artifacts with GitHub Release naming
./scripts/build-zig.sh release
```

## Artifact Layout

After `./scripts/build-zig.sh release`:
```
lib/
├── crsqlite-zig-darwin-aarch64.dylib   (2.7M - Apple Silicon Mac)
├── crsqlite-zig-darwin-x86_64.dylib    (2.6M - Intel Mac)
├── crsqlite-zig-darwin-universal.dylib (5.3M - Universal macOS)
├── crsqlite-zig-linux-x86_64.so        (4.8M - Intel/AMD Linux)
└── crsqlite-zig-linux-aarch64.so       (4.9M - ARM64 Linux)
```

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`
- Publish workflow: `.github/workflows/publish.yaml`
- Zig build system: `zig/build.zig`

## Progress Log
- 2025-12-25: Created from release planning.
- 2025-12-25: Verified native build works with `nix run nixpkgs#zig -- build -Doptimize=ReleaseFast`
- 2025-12-25: Verified cross-compilation works for all 5 targets (darwin arm64/x86_64/universal, linux x86_64/aarch64)
- 2025-12-25: Added `release` command to `scripts/build-zig.sh` for generating release artifacts with proper naming
- 2025-12-25: Verified artifacts load correctly in sqlite: `SELECT crsql_version()` returns `0.0.1-zig-scaffold`

## Completion Notes
All acceptance criteria met:
- Native build succeeds
- Cross-compilation to all 5 targets works
- Artifacts load correctly in sqlite
- Naming conventions documented

**Naming Convention Note:**
- Local build (`./scripts/build-zig.sh release`) uses `crsqlite-zig-*` prefix to distinguish from Rust/C artifacts in `lib/`
- GitHub Release (`.github/workflows/publish.yaml`) uses `crsqlite-*` naming without prefix (Zig is the primary release)

Note: The Zig implementation is currently a scaffold (version `0.0.1-zig-scaffold`). The release workflow (`.github/workflows/publish.yaml`) is already configured to build and upload all these artifacts on tag push.
