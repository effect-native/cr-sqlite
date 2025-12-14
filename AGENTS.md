# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

---

## Product Owner Wishes System

Tom (Product Owner) can asynchronously express wishes by dropping markdown files into `.wishes/`.

### How It Works

```
.wishes/
├── README.md           # Instructions for Tom
├── done/               # Completed wishes (moved here with completion notes)
├── blocked/            # Blocked wishes (moved here with reason)
└── *.md                # Active wishes (inbox) - PROCESS THESE
```

### Agent Workflow for Wishes

At the start of each OODA loop iteration:

1. **Check `.wishes/` for new files** (not in subdirs)
2. **Parse priority** from filename or content (`high-`, `medium-`, `low-` prefix or `## Priority` section)
3. **Incorporate high-priority wishes** into current round planning
4. **After completing a wish**:
   - Move file to `.wishes/done/`
   - Append completion notes (date, what was done, commit hash)
5. **If wish is blocked**:
   - Move file to `.wishes/blocked/`
   - Append reason why it's blocked
6. **Update `research/zig-cr/92-gap-backlog.md`** with relevant items from wishes

### Wish File Format

```markdown
# [Title]

## Priority
high | medium | low

## Description
What to do.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

---

## TypeScript Work Rule

**All TypeScript work happens in the `effect-native/` submodule.**

When working on TypeScript code:
1. Navigate to `effect-native/` directory
2. Follow the spec-first workflow defined in `effect-native/.specs/AGENTS.md`
3. Use the patterns and conventions documented in `effect-native/AGENTS.md`

Reference submodules for Effect ecosystem:
- `.refs/effect` — Effect-TS core library
- `.refs/effect-smol` — Effect-TS smol variant

---

## Zig CR-SQLite Rewrite: Orchestration Workflow

This project is undergoing a major rewrite from C/Rust to Zig. The following workflow governs how work proceeds.

### "Update tasks" (Backlog Refresh Loop)

When Tom says **"update tasks"**, he means: re-run the same backlog-refresh process that keeps `zig/`, `research/zig-cr/*`, `.tasks/`, and `.wishes/` in sync.

**Input reality (what exists today):**
- Implementation: `zig/`
- Current gap ledger: `research/zig-cr/92-gap-backlog.md`
- Work queue: `.tasks/backlog/`, `.tasks/active/`, `.tasks/done/`
- Product-owner inbox: `.wishes/` (and `.wishes/blocked-on-tom/`)

**Procedure (do this in order):**
1. Read all inbox wishes: list `.wishes/*.md` (not subdirs) and extract constraints/requests.
2. Read task cards: list `.tasks/{active,backlog,done}/` and skim each card’s Description + Acceptance Criteria.
3. Reconcile `zig/` vs `research/zig-cr/*`:
   - Use `research/zig-cr/90-feature-matrix.md` and `research/zig-cr/93-phased-execution-proposal.md` as “what we intended”.
   - Use the current `zig/` tree and test harnesses as “what we actually built”.
4. Identify gaps as explicit backlog items:
   - If a gap is not already owned by a `.tasks/backlog/TASK-*.md`, create one.
   - Every task card must declare: Files to Modify, Acceptance Criteria, and links back to the parent docs.
5. Make relationships impossible to miss (bidirectional linking):
   - Add/refresh links in `research/zig-cr/92-gap-backlog.md` so each unchecked item points at its owning task card.
   - Ensure each task card has a “Parent Docs / Cross-links” section pointing back to `research/zig-cr/92-gap-backlog.md` and any proposal doc.
6. Mark TS-gated work clearly:
   - If a gap is TypeScript-heavy and Tom has not opted in, keep it as a task card but mark it blocked or annotate “TS-gated by `.wishes/stop-before-typescript.md`”.
7. If a wish is now satisfied, move it to `.wishes/done/` and append completion notes.

**Output of "update tasks":**
- `research/zig-cr/92-gap-backlog.md` updated with links and status notes
- New/updated cards in `.tasks/backlog/` with unambiguous ownership
- Clear list of what can be delegated concurrently next

### "Delegate work" (Concurrent Subagent Assignments)

When Tom says **"delegate work"**, he means: take a curated subset of `.tasks/backlog/` and assign them to multiple concurrent subagents without overlapping file edits.

**Rules:**
- No overlapping file edits across assigned tasks.
- Each subagent owns exactly one task card.
- Each subagent updates its own task card (checkboxes + progress log) as it works.
- Orchestrator moves cards between folders (`backlog → active → done`).

**Procedure:**
1. Pick the highest-impact set of tasks that can run in parallel (disjoint file sets).
2. For each selected task:
   - Move `./.tasks/backlog/TASK-XXX-*.md` → `./.tasks/active/TASK-XXX-*.md`.
   - Launch a subagent with the task card as the *entire* prompt context.
   - Instruct the subagent to:
     - Only touch the listed files.
     - Keep diffs small and focused.
     - Update the task card as it goes (status + progress log + completion notes).
     - If blocked, mark Blocked with a concrete reason and a proposed next step.
3. When subagents finish:
   - Review changes.
   - Move task cards to `.tasks/done/` and ensure completion notes include date + commit hash.
   - Update `research/zig-cr/92-gap-backlog.md` to reflect the completed work and keep links current.

**Tip:** `.tasks/active/` may be changing while you read it. Don’t stop; take a snapshot (current listing + quick skim), then proceed with reconciliation and update work.

### Continuous Integration Loop

```
1. Check .wishes/ for new product owner requests
2. Review the evergreen end state spec
3. Compare it to the current WIP implementation
4. Identify gaps
5. Ensure each gap is captured and all status documents are updated in git
6. Brainstorm the optimal divide-and-conquer strategy to keep many subagents busy without stepping on each other's toes
7. Ensure the current subagent tasklist properly reflects that strategy
8. Assign tasks to subagents and direct them to update their task card once done
9. Ensure everything is in git
10. While not yet done, goto step 1
```

### Subagent Task Management

Task cards live in `.tasks/` folder:

```
.tasks/
├── README.md           # Instructions for task management
├── backlog/            # Planned tasks ready for next round
│   └── TASK-XXX-*.md   # Task cards waiting to be assigned
├── active/             # Currently assigned tasks (move here when assigning)
│   └── TASK-XXX-*.md   # Tasks being worked on
└── done/               # Completed tasks archive
    └── TASK-XXX-*.md   # With completion notes
```

**Orchestrator workflow**:
1. Create task cards in `.tasks/backlog/`
2. Move to `.tasks/active/` when assigning to subagent
3. Subagent updates progress in the task card
4. Move to `.tasks/done/` when complete

**Subagent workflow**:
1. Read assigned task from `.tasks/active/`
2. Update status checkboxes and progress log
3. Commit task card updates with code changes
4. Mark complete when done (orchestrator moves file)

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
6. **Use `.tmp/` for temp files**: Never use `/tmp/`. Use `.tmp/` in the repo root instead (already in `.gitignore`)

### Methodology
- **RGRTDD**: Red (failing tests) → Green (minimal impl) → Refactor → Regression (keep green)
- **GAN Adversarial**: treat spec ambiguities as adversarial; force explicit contracts before implementing
- **Parallelism**: maximize concurrent subagent utilization by vertical slicing

### Platform Priority
1. **Web (WASM)**: highest priority — static embedding into SQLite WASM
2. **Linux**: second priority — loadable `.so` extension
3. **macOS/Windows/iOS/Android**: expand after Web + Linux are stable

### Testing the Zig Extension

**IMPORTANT**: Do NOT use `nix run github:subtleGradient/sqlite-cr` to test the Zig extension. That command runs sqlite3 with the **Rust-based** cr-sqlite extension pre-loaded. Loading a second cr-sqlite extension (the Zig one) into the same process will cause conflicts and undefined behavior.

Instead, use plain sqlite3 and load the Zig extension explicitly:
```bash
# Build the Zig extension first
cd zig && nix run nixpkgs#zig -- build

# Test with plain sqlite3 (no pre-loaded extension)
sqlite3 :memory: -cmd '.load ./zig/zig-out/lib/libcrsqlite.dylib'

# Or use nix to get sqlite3:
nix run nixpkgs#sqlite -- :memory: -cmd '.load ./zig/zig-out/lib/libcrsqlite.dylib'
```

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