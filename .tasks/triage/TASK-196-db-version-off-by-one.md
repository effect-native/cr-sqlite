# TASK-196 — db_version off-by-one divergence

## Goal
Fix the db_version tracking divergence where Zig produces db_version values 1 higher than Rust/C after certain operation sequences.

## Status
- State: triage
- Priority: HIGH (sync correctness)
- Discovered: 2025-12-23 (TASK-190 fuzz testing)

## Problem

After the same sequence of INSERT/UPDATE/DELETE operations, Zig and Rust/C implementations produce different `db_version` values:

```
Zig db_version:   355
Rust/C db_version: 354
```

This affects the `crsql_changes` output where `db_version` values are off by 1.

## Reproduction

```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
STRESS_ITERATIONS=25 STRESS_OPS=500 STRESS_SEED=2025 \
  bash zig/harness/test-fuzz-stress.sh
```

Divergence occurs at iterations 9, 15, 20 with this seed.

Databases with divergence are saved in `.tmp/debug-stress/`:
- `wide_zig_9.db` (Zig, db_version=355)
- `wide_rust_9.db` (Rust/C, db_version=354)

## Example Divergence

```
Zig:    wide_t|01090F|col3|299|2|307|1
Rust/C: wide_t|01090F|col3|299|2|306|1
                               ^^^--- off by 1
```

## Root Cause Hypothesis

The db_version increment logic differs in edge cases. Possible causes:

1. **No-op update counting**: When an UPDATE doesn't actually change the value, does it increment db_version?
2. **Resurrection (DELETE + INSERT same PK)**: Known to have `seq` divergence (TASK-130), may also affect db_version
3. **Transaction boundary handling**: Does COMMIT increment db_version in one impl but not the other?
4. **INSERT OR REPLACE**: Might be treated as UPDATE in one impl and DELETE+INSERT in the other

## Files to Investigate

- `zig/src/triggers.zig` - Trigger logic that increments db_version
- `zig/src/ext_data.zig` - ExtData db_version tracking
- `core/src/triggers.c` - Rust/C trigger implementation (for comparison)

## Acceptance Criteria

1. [ ] Identify exact operation sequence causing divergence
2. [ ] Determine which implementation is "correct" (likely Rust/C as reference)
3. [ ] Fix Zig implementation to match
4. [ ] Verify `test-fuzz-stress.sh` passes with all seeds

## Parent Docs / Cross-links

- Discovery: `.tasks/triage/TASK-190-fuzz-invalidation-round2.md`
- Related: `.tasks/done/TASK-130-fix-trigger-parity-test-column-bug.md` (seq divergence)
- Test script: `zig/harness/test-fuzz-stress.sh`

## Progress Log
- 2025-12-23: Created from TASK-190 fuzz testing findings.

## Completion Notes
(Empty until done.)
