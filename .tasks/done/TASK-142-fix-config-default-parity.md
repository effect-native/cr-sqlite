# TASK-142: Fix merge-equal-values default to match oracle (0, not 1)

## Summary

The Zig implementation defaults `merge-equal-values` config to 1, but the Rust/C oracle defaults to 0. This causes parity divergence on fresh databases.

## Evidence

From `zig/harness/test-config.sh`:
```
Parity comparison (fresh database default):
  Zig   - Fresh db default: 1
  Rust  - Fresh db default: 0
  (Reference: core/src/ext-data.c:72 sets default = 0)
FAIL: Parity divergence in default - Zig: '1', Rust: '0'
```

## Root Cause

The Rust/C reference implementation sets the default in `core/src/ext-data.c:72`:
```c
pExtData->mergeEqualVals = 0;  // default is 0 (don't merge equal values)
```

The Zig implementation likely has a different default value.

## Files to Modify

- `zig/src/config.zig` — change `DEFAULT_MERGE_EQUAL_VALUES` from `1` to `0` on line 21

## Acceptance Criteria

1. `bash zig/harness/test-config.sh` passes all 16 tests (currently 15 pass, 1 fail)
2. Fresh database `SELECT crsql_config_get('merge-equal-values')` returns 0
3. Parity with Rust/C oracle on default value

## Reproduction Steps

```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-config.sh
# Test CF-007c fails on default parity
```

Minimal reproduction:
```bash
# Zig
ZIG_EXT="zig/zig-out/lib/libcrsqlite.dylib"
nix run nixpkgs#sqlite --quiet -- :memory: -cmd ".load $ZIG_EXT" \
  "SELECT crsql_config_get('merge-equal-values');"
# Returns: 1 (should be 0)

# Rust/C oracle
nix run github:subtleGradient/sqlite-cr --quiet -- :memory: <<< \
  "SELECT crsql_config_get('merge-equal-values');"
# Returns: 0
```

## Parent Docs / Cross-links

- Discovered in: `.tasks/done/TASK-138-config-isolation-test.md`
- Test file: `zig/harness/test-config.sh`
- Rust/C reference: `core/src/ext-data.c:72`

## Progress Log

- [x] Created task card
- [x] Read `zig/src/config.zig` to confirm the default value location
- [x] Changed `DEFAULT_MERGE_EQUAL_VALUES` from `1` to `0` on line 21
- [x] Updated comment on lines 8-10 to reflect correct default
- [x] Updated unit test on line 285 to expect `0` instead of `1`
- [x] Built extension and verified parity with oracle

## Completion Notes

**Fixed:** Changed `DEFAULT_MERGE_EQUAL_VALUES` from `1` to `0` in `zig/src/config.zig` to match the Rust/C oracle default (per `core/src/ext-data.c:72`).

**Changes made to `zig/src/config.zig`:**
1. Line 9-10: Updated doc comment to show `0` as default, `1` as alternate
2. Line 20-21: Changed constant from `1` to `0` with updated comment
3. Line 285-286: Updated unit test to expect `0` (renamed test to clarify oracle parity)

**Test Results:**
- CF-007c (parity test): PASS - Both Zig and Rust/C return `0` as default
- 15 of 16 tests pass

**Note:** Test CF-007b still fails because it has a hardcoded expectation of `1` for fresh database default. This test expectation is incorrect (oracle returns `0`). Per task instructions, only `zig/src/config.zig` was modified - test harness fix should be a separate task.

**Verification:**
```
$ nix run github:subtleGradient/sqlite-cr -- :memory: <<< "SELECT crsql_config_get('merge-equal-values');"
0

$ nix run nixpkgs#sqlite -- :memory: -cmd ".load $ZIG_EXT" "SELECT crsql_config_get('merge-equal-values');"
0
```

Date: 2025-12-20
