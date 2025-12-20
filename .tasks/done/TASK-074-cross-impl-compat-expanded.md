# TASK-074: Cross-implementation wire compatibility — Expand beyond happy path

## Status
- [ ] Planned
- [ ] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Existing script: `zig/harness/test-cross-platform-compat.sh`
- C sync helper reference: `core/src/crsqlite.test.c` (syncLeftToRight)
- Feature matrix: `research/zig-cr/90-feature-matrix.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Pack columns reference: `core/rs/core/src/pack_columns.rs`

## Description
A real system will often have heterogeneous peers (mobile, server, browser) and long-lived on-disk databases.

We already have a Zig↔Rust/C compatibility script, but it's easy for it to be effectively "green" because:
- it can SKIP if the Rust/C extension isn't built
- it may not cover important edge cases (deletes, PK updates, schema evolution, numeric/text encoding edge cases)

This task strengthens the compatibility proof by expanding the scenario set and making sure CI/local runs cannot silently skip the Rust/C side.

**Oracle-based testing strategy**: Treat Rust/C as the "Golden Master" oracle. For each test, perform identical operations on both implementations and assert outputs are bit-identical or semantically equivalent.

## Files to Modify
- `zig/harness/test-cross-platform-compat.sh`
- `zig/harness/test-oracle-parity.sh` (new — oracle-based parity tests)
- `core/Makefile` (only if needed to provide a reproducible build target for the Rust/C loadable extension)
- `.github/workflows/zig-tests.yaml` (optional: ensure Rust/C artifact exists for compat test)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Script reliably finds/builds the Rust/C extension (no silent SKIP in CI).
- [x] New compatibility assertions added for at least:
  - [x] deletes + resurrection behavior
  - [x] primary key updates
  - [x] compound primary keys
  - [x] float edge cases (sci notation), blobs, NULLs
  - [x] schema evolution (add/remove columns with `crsql_commit_alter`/equivalent)
  - [x] text edge cases (Unicode, special characters)
- [x] Both directions tested: Zig→Rust/C and Rust/C→Zig.
- [x] **Oracle parity tests** (Rust/C as golden master):
  - [x] `test_wire_format_pack_columns_compatibility`: `crsql_pack_columns(...)` output is bit-identical between Zig and Rust/C for same inputs (integers, floats, text, blobs, NULLs, compound PKs).
  - [x] `test_clock_table_schema_compatibility`: `__crsql_clock` and `__crsql_pks` table schemas match exactly (column names, types, constraints).
  - [x] `test_merge_resolution_value_parity`: Given identical conflict scenarios (same col_version, db_version, site_id tie-breakers), both implementations select the same winner.
  - [x] `test_site_id_storage_format_parity`: Site IDs are stored as 16-byte blobs; cross-opening a DB created by Rust/C in Zig (and vice versa) preserves the site_id value.

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".
- Updated to include oracle-based parity tests (wire format, schema, merge resolution, site_id).

### 2025-12-20
- **Expanded `test-cross-platform-compat.sh`** with 7 new test sections (G-M):
  - Test G: Delete + Resurrection
  - Test H: Primary Key Updates (Tombstone + New Row)
  - Test I: Compound Primary Keys
  - Test J: Float Edge Cases
  - Test K: Blob and Empty Blob Handling
  - Test L: Schema Evolution (ADD COLUMN)
  - Test M: Text Edge Cases (Unicode, Special Characters)

- **Created `test-oracle-parity.sh`** with 6 test sections and 18+ individual tests:
  - Test 1: pack_columns Wire Format Parity (6 subtests)
  - Test 2: Clock Table Schema Parity (2 subtests)
  - Test 3: Merge Resolution Value Parity (2 subtests)
  - Test 4: Site ID Storage Format Parity (3 subtests)
  - Test 5: Changes Virtual Table Output Format (3 subtests)
  - Test 6: db_version Behavior Parity (2 subtests)

## Test Results

### Oracle Parity Tests (`test-oracle-parity.sh`)
- **15 passed, 3 failed, 0 skipped**
- Failures found:
  1. `__crsql_clock` table uses `pk` column in Zig vs `key` in Rust/C
  2. `__crsql_clock` index count differs (Zig=0, Rust=1)
  3. Cross-opening Zig DB with Rust/C doesn't preserve site_id

### Cross-Platform Compat Tests (`test-cross-platform-compat.sh`)
- **Tests A-F (original)**: All PASS
- **Tests G-M (new edge cases)**: 3 failures found:
  1. Resurrection sync from Rust/C to Zig not working
  2. Empty blob (X'') handling differs
  3. Multi-line text handling differs

## Discovered Issues (for follow-up)
These failures represent real compatibility gaps that need separate task cards:
- Clock table column naming mismatch (`pk` vs `key`)
- Missing index on clock table in Zig
- Site ID not preserved when Rust/C opens Zig-created DB
- Resurrection changes not syncing correctly
- Empty blob vs NULL distinction

## Completion Notes
