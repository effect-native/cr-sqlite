# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is `@effect-native/libcrsql`, a Pure-Nix package that provides pre-built CR-SQLite extensions for conflict-free replicated databases. The package builds CR-SQLite extensions using Nix and distributes them for multiple platforms (macOS x86_64/ARM64, Linux x86_64/ARM64).

### Key Architecture Components

- **Nix-based Build System**: Uses `flake.nix` for reproducible cross-platform builds of CR-SQLite extensions
- **Platform Detection**: Runtime platform/architecture detection to load correct extension (darwin/linux, x86_64/aarch64)
- **Multi-platform Support**: Targets 4 platforms: Intel Mac, Apple Silicon Mac, Intel Linux, ARM64 Linux
- **TypeScript/Effect Integration**: Uses Effect-TS for build scripts and type-safe operations
- **React Native Compatibility**: Separate entry point that throws helpful errors for RN usage

## Common Development Commands

```bash
# Build CR-SQLite extension for current platform only
npm run build
# OR: nix build .#cr-sqlite

# Build extensions for ALL platforms (requires cross-compilation support)
npm run bundle-lib
# OR: nix run .#build-all-platforms

# Run tests (basic functionality checks)
npm test
# OR: npm run check

# Test in Docker environment
npm run test:docker

# Build production package with all extensions
npm run build-production

# Get path to CR-SQLite extension
npm run get-path
# OR: nix run .#print-path

# Check Nix flake configuration
npm run check
# OR: nix flake check

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

## Important Notes

- This package is for **Node.js/Bun server environments only**, NOT React Native
- React Native users should use `@op-engineering/op-sqlite` or `expo-sqlite`
- Extension loading requires native SQLite libraries that support `loadExtension()`
- Cross-platform builds require Nix remote builders or binary cache substitution
- All build outputs go to `dist/` directory for production packaging