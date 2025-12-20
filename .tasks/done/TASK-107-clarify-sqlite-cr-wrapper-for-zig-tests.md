# TASK-107: Clarify sqlite-cr wrapper usage for Zig harness tests

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Triggered by: `.tasks/done/TASK-098-zig-ondisk-db-tests.md`
- Repo guidance: `AGENTS.md` “Zig testing (quick rule)”

## Description
TASK-098 context says to use `nix run github:subtleGradient/sqlite-cr` instead of `sqlite3` when testing against CR-SQLite.

However, `AGENTS.md` also says:

- “Do not run the Zig extension inside a sqlite3 wrapper that preloads another cr-sqlite extension. Load the Zig extension explicitly into a clean sqlite process.”

This creates ambiguity for Zig harness tests:
- When validating *Zig extension behavior*, the wrapper may preload a different CR-SQLite extension (C/Rust), potentially invalidating results.
- When validating *baseline CR-SQLite* behavior, the wrapper is convenient.

We need a clear policy for harness scripts:
- Which tests must use clean `sqlite` + explicit `.load $EXT`
- Which tests can use the sqlite-cr wrapper
- How to ensure we never accidentally have two extensions loaded

## Files to Modify
- `AGENTS.md` (if policy needs codifying)
- `zig/harness/test-parity.sh` (potential helper function / enforcement)
- `zig/harness/test-*.sh` (only if adjustments are required)

## Acceptance Criteria
- [x] Decision documented (where it belongs) - Updated `AGENTS.md` with detailed policy
- [x] Zig harness tests consistently follow the decision - All 39 scripts audited, all compliant
- [x] No Zig test loads a wrapper that preloads another CR-SQLite extension - Verified
- [x] CI/local repro instructions updated accordingly - `AGENTS.md` now has test script pattern

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-parity.sh
```

## Progress Log
### 2025-12-20
- Drafted after noticing conflicting guidance between TASK-098 context and `AGENTS.md`
- Audited all 39 test scripts in `zig/harness/test-*.sh`
- Documented policy decision and audit results

## Audit Results

### Current Practice in Zig Harness Tests

All 39 test scripts follow a **consistent pattern**:

1. **Zig extension tests**: Use `nix run nixpkgs#sqlite -- ... -cmd ".load $ZIG_EXT" ...`
   - This is a CLEAN sqlite3 process with explicit extension loading
   - Examples: `test-parity.sh`, `test-crsqlite.sh`, `test-merge.sh`, `test-alter.sh`, etc.

2. **Oracle parity tests** (Zig vs Rust/C comparison): Use BOTH:
   - Zig: `nix run nixpkgs#sqlite -- ... -cmd ".load $ZIG_EXT" ...`
   - Rust/C: `nix run nixpkgs#sqlite -- ... -cmd ".load $RUST_EXT" ...`
   - Examples: `test-trigger-parity.sh`, `test-fract-parity.sh`, `test-api-surface.sh`, `test-oracle-parity.sh`

3. **ONE script uses sqlite-cr**: `test-alter-parity.sh`
   - Uses `nix run github:subtleGradient/sqlite-cr` for Rust/C oracle
   - Uses `nix run nixpkgs#sqlite` + `.load $ZIG_EXT` for Zig
   - This is **correct behavior**: sqlite-cr only loads Rust/C ext, Zig is loaded separately
   - No double-loading occurs

### Scripts Using sqlite-cr (only 1):
- `zig/harness/test-alter-parity.sh` - **CORRECT USAGE** (oracle only)

### Policy Decision

The sqlite-cr wrapper **can be used** but ONLY for testing the Rust/C oracle (reference implementation), NEVER for testing the Zig extension.

**Rationale:**
- sqlite-cr preloads the Rust/C cr-sqlite extension
- Using sqlite-cr + loading Zig extension = two extensions loaded simultaneously
- This would create unpredictable behavior (function conflicts, double triggers, etc.)

### Compliant vs Violating Scripts

**All scripts are COMPLIANT** with the policy:
- 38 scripts use clean `nix run nixpkgs#sqlite` with explicit `.load`
- 1 script (`test-alter-parity.sh`) uses sqlite-cr **only for Rust/C oracle**, not for Zig

**No scripts violate the policy.**

## Completion Notes
### 2025-12-20
- Audited all 39 `zig/harness/test-*.sh` scripts
- Found all scripts are compliant with the policy
- Updated `AGENTS.md` with detailed Zig testing policy including:
  - Core rule (no double-loading)
  - sqlite-cr wrapper usage guidelines (ALLOWED vs FORBIDDEN)
  - Test script pattern examples
  - Explanation of why this matters
- The existing guidance was correct but needed expansion for clarity
- No test scripts need modification - all already follow best practices
