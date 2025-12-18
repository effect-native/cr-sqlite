# TASK-089: Oracle Parity — API surface completeness

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
Claude (completed 2025-12-17)

## Parent Docs / Cross-links
- Rust extension entry: `core/rs/core/src/lib.rs`
- Zig extension entry: `zig/src/crsqlite.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that Zig exposes the same SQL API surface as Rust/C. Use `pragma_function_list` and `pragma_module_list` to enumerate all registered functions and virtual table modules, then compare.

This is an **oracle test**: Rust/C is the golden master. Any function or module present in Rust/C but missing from Zig is a gap.

## Files to Modify
- `zig/harness/test-api-surface.sh` (new)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Test extracts function list from Rust/C extension: `SELECT name FROM pragma_function_list WHERE name LIKE 'crsql%' ORDER BY name`
- [x] Test extracts function list from Zig extension using same query.
- [x] Test extracts module list from both: `SELECT name FROM pragma_module_list WHERE name LIKE 'crsql%' OR name = 'clset' ORDER BY name`
- [x] Test fails if Rust/C has functions/modules not present in Zig.
- [x] Test documents which functions are intentionally excluded (if any) with rationale.
- [x] Functions to verify include (at minimum):
  - `crsql_as_crr`, `crsql_as_table` ✓ (both present in Zig)
  - `crsql_begin_alter`, `crsql_commit_alter` ✓ (both present in Zig)
  - `crsql_changes`, `crsql_tracked_peers` ✓ (crsql_changes present; crsql_tracked_peers not in Rust/C either - it's a different concept)
  - `crsql_db_version`, `crsql_next_db_version` ✓ (both present in Zig)
  - `crsql_site_id`, `crsql_siteid` (alias) ✓ (crsql_site_id present; alias not found in Rust/C pragma_function_list)
  - `crsql_finalize` ✓ (present in Zig)
  - `crsql_fract_key_between` ✓ (present in Zig)
  - `crsql_pack_columns`, `crsql_rows_impacted` ✓ (both present in Zig)
  - `crsql_automigrate` (if implemented) ✗ MISSING - in Rust/C, not in Zig
  - `crsql_config_get`, `crsql_config_set` (if implemented) ✗ MISSING - in Rust/C, not in Zig

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

### 2025-12-17 (execution)
- Created `zig/harness/test-api-surface.sh` - oracle parity test comparing Rust/C vs Zig
- Wired into `zig/harness/test-parity.sh`
- Ran `bash zig/harness/test-parity.sh` - API surface test integrated successfully
- Documented all gaps discovered

## Commands Run
```bash
# Standalone API surface test
bash /Users/tom/Developer/effect-native/cr-sqlite/zig/harness/test-api-surface.sh

# Full parity suite
bash /Users/tom/Developer/effect-native/cr-sqlite/zig/harness/test-parity.sh
```

## Full Test Output
```
╔═══════════════════════════════════════════════════════════════════════╗
║           API Surface Parity Test (Oracle: Rust/C)                    ║
╚═══════════════════════════════════════════════════════════════════════╝

Rust/C extension: /Users/tom/Developer/effect-native/cr-sqlite/lib/crsqlite.dylib
Zig extension:    /Users/tom/Developer/effect-native/cr-sqlite/lib/crsqlite-zig-darwin-aarch64.dylib

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Extracting function lists...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Rust/C functions (23):
  crsql_after_delete
  crsql_after_insert
  crsql_after_update
  crsql_as_crr
  crsql_as_table
  crsql_automigrate
  crsql_begin_alter
  crsql_commit_alter
  crsql_config_get
  crsql_config_set
  crsql_db_version
  crsql_finalize
  crsql_fract_as_ordered
  crsql_fract_fix_conflict_return_old_key
  crsql_fract_key_between
  crsql_get_seq
  crsql_increment_and_get_seq
  crsql_internal_sync_bit
  crsql_next_db_version
  crsql_pack_columns
  crsql_rows_impacted
  crsql_sha
  crsql_site_id

Zig functions (18):
  crsql_as_crr
  crsql_as_table
  crsql_begin_alter
  crsql_commit_alter
  crsql_db_version
  crsql_finalize
  crsql_fract_as_ordered
  crsql_fract_fix_conflict_return_old_key
  crsql_fract_key_between
  crsql_increment_and_get_seq
  crsql_internal_sync_bit
  crsql_is_crr
  crsql_next_db_version
  crsql_pack_columns
  crsql_rows_impacted
  crsql_site_id
  crsql_version
  crsql_zig_version

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Extracting module lists...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Rust/C modules (3):
  clset
  crsql_changes
  crsql_unpack_columns

Zig modules (1):
  crsql_changes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Comparing API surfaces...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FAIL: 8 functions in Rust/C but missing from Zig:
  - crsql_after_delete
  - crsql_after_insert
  - crsql_after_update
  - crsql_automigrate
  - crsql_config_get
  - crsql_config_set
  - crsql_get_seq
  - crsql_sha

INFO: 3 functions in Zig but not in Rust/C (Zig-specific):
  + crsql_is_crr
  + crsql_version
  + crsql_zig_version

FAIL: 2 modules in Rust/C but missing from Zig:
  - clset
  - crsql_unpack_columns

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Intentional Exclusions (documented rationale):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  crsql_after_delete, crsql_after_insert, crsql_after_update:
    Internal trigger functions - not part of public API.
    These are registered for use by auto-generated triggers only.

  crsql_sha:
    Debug/utility function - not essential for CRDT operations.

  crsql_siteid (alias):
    Legacy alias - crsql_site_id is the canonical function.


╔═══════════════════════════════════════════════════════════════════════╗
║                         API SURFACE SUMMARY                          ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Rust/C Functions: 23                                                 ║
║  Zig Functions:    18                                                 ║
║  Rust/C Modules:   3                                                  ║
║  Zig Modules:      1                                                  ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Missing from Zig: 10                                                 ║
╚═══════════════════════════════════════════════════════════════════════╝

✗ API surface parity: FAIL (10 gaps found)
```

## Gaps Discovered

### Functions Missing from Zig (require implementation)
| Function | Priority | Notes |
|----------|----------|-------|
| `crsql_automigrate` | Medium | Schema migration support |
| `crsql_config_get` | Medium | Configuration API |
| `crsql_config_set` | Medium | Configuration API |
| `crsql_get_seq` | Low | Sequence getter (crsql_increment_and_get_seq exists) |

### Functions Intentionally Excluded (internal/debug)
| Function | Rationale |
|----------|-----------|
| `crsql_after_delete` | Internal trigger function |
| `crsql_after_insert` | Internal trigger function |
| `crsql_after_update` | Internal trigger function |
| `crsql_sha` | Debug/utility function |

### Modules Missing from Zig
| Module | Priority | Notes |
|--------|----------|-------|
| `clset` | Medium | Changeset virtual table |
| `crsql_unpack_columns` | Low | Column unpacking vtab |

### Zig-Specific Additions (not in Rust/C)
| Function | Notes |
|----------|-------|
| `crsql_is_crr` | Utility to check if table is a CRR |
| `crsql_version` | Version string |
| `crsql_zig_version` | Zig implementation version |

## Completion Notes
Task completed. Created `zig/harness/test-api-surface.sh` that:
1. Loads both extensions into clean sqlite3 processes
2. Extracts function and module lists via pragma queries
3. Compares using `comm` to find gaps
4. Reports missing items with clear categorization
5. Documents intentional exclusions with rationale

The test is wired into `test-parity.sh` and runs as part of `make -C zig test-parity`.

**10 total gaps identified** (8 functions + 2 modules), of which 4 functions are intentionally excluded (internal trigger functions + debug utility).
