# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

---

## Zig CR-SQLite Rewrite: Orchestration Workflow

This project is undergoing a major rewrite from C/Rust to Zig. The following workflow governs how work proceeds.

### Continuous Integration Loop

```
1. Review the evergreen end state spec
2. Compare it to the current WIP implementation
3. Identify gaps
4. Ensure each gap is captured and all status documents are updated in git
5. Brainstorm the optimal divide-and-conquer strategy to keep many subagents busy without stepping on each other's toes
6. Ensure the current subagent tasklist properly reflects that strategy
7. Assign tasks to subagents and direct them to update their task card once done
8. Ensure everything is in git
9. While not yet done, goto step 1
```

### Document Organization

```
research/zig-cr/
├── README.md                          # Index of all research + proposals
│
├── # Legacy Analysis Reports (01-11)
├── 01-extension-surface.md            # C entrypoints, init/load, exported symbols
├── 02-virtual-tables.md               # vtab inventory, x* methods, schemas
├── 03-hooks-and-triggers.md           # SQLite hooks + trigger-based capture
├── 04-schema-and-metadata.md          # internal tables, migrations, naming
├── 05-conflict-resolution-semantics.md # merge rules, winner selection, tombstones
├── 06-clock-versioning.md             # site ids, db_version/seq, causal ordering
├── 07-fractindex-rust.md              # fractional index crate analysis
├── 08-ffi-boundary.md                 # C↔Rust ABI surface
├── 09-storage-serialization.md        # packed blob wire format
├── 10-test-oracle.md                  # behavioral contract from C tests
├── 11-performance-hotspots.md         # stmt caching, union query, pragma checks
│
├── # Zig Reference Analysis (20-22)
├── 20-zig-sqlite-capabilities.md      # what .refs/zig-sqlite provides + gaps
├── 21-ghostty-best-practices.md       # build/allocator/test patterns
├── 22-bun-best-practices.md           # protocol parsing, ownership, errdefer
│
├── # Synthesis Documents (90-92)
├── 90-feature-matrix.md               # feature → impl → Zig plan → gaps
├── 91-mvp-roadmap.md                  # phased test-passing milestones
├── 92-gap-backlog.md                  # missing zig-sqlite bindings to add
│
├── # Execution Proposals (93-95)
├── 93-phased-execution-proposal.md    # RGRTDD + GAN workflow, Web-first
├── 94-long-term-solution.md           # ideal multi-platform architecture
└── 95-one-weird-tricks.md             # 80/20 shortcuts to end-to-end beta
```

### Evergreen Spec Location
- **Behavioral contract (source of truth)**: `core/src/*.test.c`
- **Wire format spec**: `research/zig-cr/09-storage-serialization.md`
- **Merge semantics spec**: `research/zig-cr/05-conflict-resolution-semantics.md`

### WIP Implementation Location
- New Zig code will live in a new `zig/` directory (to be created)
- Build artifacts: `zig-out/`
- Zig build definition: `zig/build.zig`

### Gap Tracking
- High-level gaps: `research/zig-cr/92-gap-backlog.md`
- Per-phase acceptance: `research/zig-cr/93-phased-execution-proposal.md`
- Use git commits to checkpoint status after each subagent completes a task

### Subagent Task Assignment Rules
1. **No overlapping file edits**: assign disjoint file sets to each subagent
2. **Contract-first**: each task must have explicit acceptance criteria (test name or assertion)
3. **Small scope**: prefer many small tasks over few large ones
4. **Update on completion**: subagent must update its task card (in todo list or status doc) when done
5. **Commit atomically**: each completed task = one git commit with clear message

### Methodology
- **RGRTDD**: Red (failing tests) → Green (minimal impl) → Refactor → Regression (keep green)
- **GAN Adversarial**: treat spec ambiguities as adversarial; force explicit contracts before implementing
- **Parallelism**: maximize concurrent subagent utilization by vertical slicing

### Platform Priority
1. **Web (WASM)**: highest priority — static embedding into SQLite WASM
2. **Linux**: second priority — loadable `.so` extension
3. **macOS/Windows/iOS/Android**: expand after Web + Linux are stable

---

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