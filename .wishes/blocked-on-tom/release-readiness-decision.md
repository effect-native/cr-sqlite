# Release Readiness Decision

## Question for Tom
When are we ready for our first public release of the Zig cr-sqlite implementation?

## Current State (2025-12-25)

### What Works
- ✅ **Core sync functionality** — INSERT INTO crsql_changes works (P0 bug fixed Round 73)
- ✅ **All app simulations pass** — Todo (2/2), Chat (4/4)
- ✅ **Stress tests pass** — 60/60 iterations, 0 divergences
- ✅ **Parity suite** — 362 passed, 13 failed (pre-existing edge cases)
- ✅ **Darwin builds** — Native extension works on macOS (arm64 + x86_64)
- ✅ **Linux builds** — Native extension works on Linux (tested locally)

### Known Gaps
- ⚠️ **CI disabled** — Failing on WASM + oracle-dependent tests
- ⚠️ **seq divergence** — Zig starts at 1, Rust at 0 (doesn't affect sync)
- ⚠️ **Empty blob PK encoding** — Minor wire format difference
- ⚠️ **Schema mismatch behavior** — Zig errors, Rust ignores (design decision)

### Not Implemented
- ❌ **WASM build** — Requires Zig 0.14 compat work
- ❌ **Browser support** — Depends on WASM
- ❌ **crsql_sha function** — Not implemented
- ❌ **crsql_tracked_peers table** — Not implemented

## Decision Points

1. **What's the release scope?**
   - Native only (Darwin + Linux)?
   - Native + WASM?
   - Native + WASM + Browser?

2. **What's the versioning strategy?**
   - Alpha/Beta labels?
   - Semantic versioning?

3. **What's the distribution channel?**
   - npm package?
   - GitHub releases?
   - Both?

4. **What documentation is required?**
   - API reference?
   - Migration guide from Rust/C?
   - Getting started guide?

## Blocking
- `.tasks/backlog/TASK-207-reenable-ci-for-release.md`

## Tom's Decision
(Pending)
