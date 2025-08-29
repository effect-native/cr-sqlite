# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is `@effect-native/libcrsql`, a Pure-Nix package that provides pre-built CR-SQLite extensions for conflict-free replicated databases. The package builds CR-SQLite extensions using Nix and distributes them for multiple platforms (macOS x86_64/ARM64, Linux x86_64/ARM64).

## Project Structure & Module Organization

- **Core C/Rust**: `core/` (CR-SQLite sources, Makefile, tests). Builds shared library into `core/dist/`
- **Node package entry**: `index.js`, types `index.d.ts`, CLI `bin/`, helper macro `build-macros.ts`
- **Prebuilt artifacts**: `lib/` (platform-specific `crsqlite-<platform>-<arch>.(dylib|so)` and fallbacks)
- **Nix flake**: `flake.nix` (packages, dev shell, apps like `print-path`, `build-all-platforms`)
- **Scripts**: `scripts/` (production bundling, version sync, VPS verification)
- **Tests**: C tests under `core/src/*.test.c`; integration in `py/correctness/`; packaging sanity `dist.test.ts`

### Key Architecture Components

- **Nix-based Build System**: Uses `flake.nix` for reproducible cross-platform builds of CR-SQLite extensions
- **Platform Detection**: Runtime platform/architecture detection to load correct extension (darwin/linux, x86_64/aarch64)
- **Multi-platform Support**: Targets 4 platforms: Intel Mac, Apple Silicon Mac, Intel Linux, ARM64 Linux
- **TypeScript/Effect Integration**: Uses Effect-TS for build scripts and type-safe operations
- **React Native Compatibility**: Separate entry point that throws helpful errors for RN usage

## Build, Test, and Development Commands

```bash
# Build (current platform via Nix)
npm run build                    # nix build .#cr-sqlite

# Bundle local lib (writes to lib/ with platform naming)
npm run bundle-lib              # nix run .#build-all-platforms

# Production bundle (multi-platform)
npm run build-production

# Validate flake
npm run check                   # nix flake check

# Tests
npm test                        # flake check
npm run test:docker             # if Docker running
npm run test:vps               # VPS verification

# Manual core build
make -C core loadable          # outputs core/dist/crsqlite.(dylib|so)

# Dev shell (enter environment with Rust/C toolchains)
nix develop

# Get path to CR-SQLite extension
npm run get-path               # nix run .#print-path

# Version synchronization
npm run sync-version
```

## Build System Architecture

### Nix Flake Structure
- `flake.nix`: Defines cross-platform builds using rust-overlay for nightly Rust
- Builds native CR-SQLite extension from `core/` subdirectory (git submodule)
- Uses upstream CR-SQLite Makefile with `make loadable` target
- Produces platform-specific extensions: `.dylib` (macOS), `.so` (Linux)

### Build Scripts (TypeScript/Effect)
- `scripts/build-production.ts`: Universal package builder for all platforms
- `scripts/sync-version.ts`: Version synchronization across package files
- `build-macros.ts`: Build-time macro for extension path resolution

### Runtime Extension Loading
- `index.js`: Main entry point with platform detection and fallback logic
- Tries platform-specific extensions first (`crsqlite-darwin-aarch64.dylib`)
- Falls back to generic extensions for development/backward compatibility
- Provides helpful error messages with available platforms

## Testing Strategy

- `dist.test.ts`: Basic functionality tests using Effect-TS and Bun SQLite
- Tests file existence, Nix flake validity, TypeScript compilation
- Docker testing via `test:docker` script
- VPS testing via `scripts/verify-vps.sh`

## Platform Targets

The package supports these platforms:
1. **aarch64-darwin**: Apple Silicon Mac (M1/M2/M3)
2. **x86_64-darwin**: Intel Mac
3. **aarch64-linux**: ARM64 Linux (Raspberry Pi 4+, AWS Graviton)
4. **x86_64-linux**: Intel/AMD Linux (Docker, most servers)

Extensions are named: `crsqlite-{platform}-{arch}.{ext}`

## CR-SQLite Integration

- Loads CR-SQLite extension which provides CRDT functionality to SQLite
- Key functions: `crsql_as_crr()`, `crsql_changes` virtual table, `crsql_version()`
- Works with any SQLite library that supports `loadExtension()` (better-sqlite3, sqlite3, Bun SQLite)
- Path exported as `pathToCRSQLiteExtension` constant and `getExtensionPath()` function

## Development Environment

- **Primary Runtime**: Bun (used for TypeScript execution and SQLite testing)
- **Package Manager**: npm (with bun.lock for deterministic installs)
- **Build System**: Pure Nix (no Homebrew dependencies)
- **Language**: TypeScript with Effect-TS for type-safe operations
- **Testing**: Custom Effect-based test runner

## Coding Style & Naming Conventions

- **JS/TS**: ESM modules, Node ≥16. Prettier enforced: 2-space indent, trailing commas (es5), double quotes
- **C**: Follow upstream style; `core/.clang-format` available; keep changes minimal and upstream-friendly
- **Artifacts**: Name as `crsqlite-<platform>-<arch>.(dylib|so)` and keep generic fallbacks (`crsqlite.dylib|so`)

## Testing Guidelines

- **Wrapper/package changes**: Run `npm run check` and `npm run test:vps`; if packaging logic changes, also run `npx tsx dist.test.ts`
- **Core changes**: `make -C core test` (optionally `valgrind`), and run CI-mirroring commands in `.github/workflows/*` when possible
- **Python correctness** (optional): `cd py/correctness && ./install-and-test.sh`

## Commit & Pull Request Guidelines

- **Messages**: Concise, imperative ("Fix build on Linux", "Add extension path CLI")
- **Scope**: Separate functional changes from formatting. Reference issues when relevant
- **PRs**: Include description, affected platforms, test results (commands run + output snippets), and any `lib/` artifacts touched. Screenshots/logs for `npx libcrsql-extension-path` helpful

## Security & Configuration Tips

- **Prefer Nix builds** for reproducibility. Avoid committing built binaries outside `lib/`
- **For cross-compiles**, use `npm run build-production`; avoid ad-hoc renames—let scripts place files correctly
- **Do not modify vendored upstream** lightly (`core/`); propose upstream when possible
- **Reproducibility**: Use Nix builders or binary cache; avoid manual renames

## Important Notes

- This package is for **Node.js/Bun server environments only**, NOT React Native
- React Native users should use `@op-engineering/op-sqlite` or `expo-sqlite`
- Extension loading requires native SQLite libraries that support `loadExtension()`
- Cross-platform builds require Nix remote builders or binary cache substitution
- All build outputs go to `dist/` directory for production packaging
- **When changing packaging/loading**, test: `npm run bundle-lib`, `npx libcrsql-extension-path`, `npm run test:docker`, `npm run test:vps`