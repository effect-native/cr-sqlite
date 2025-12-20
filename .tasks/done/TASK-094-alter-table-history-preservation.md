# TASK-094: Oracle Parity — ALTER TABLE preserves clock history

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust alter logic: `core/rs/core/src/alter.rs`
- Zig alter logic: `zig/src/schema_alter.zig`
- Existing alter tests: `zig/harness/test-alter.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_begin_alter` / `crsql_commit_alter` preserves existing clock history and correctly backfills new columns.

This is an **oracle test**: Schema evolution is critical for long-lived databases. If Zig loses clock history during ALTER or fails to backfill new columns, data will be lost or sync will break.

## Files to Modify
- `zig/harness/test-alter-parity.sh` (new or extend `test-alter.sh`)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Test creates CRR table, inserts data, records clock state.
- [x] Test performs ALTER operations via `crsql_begin_alter`/`crsql_commit_alter`:
  1. ADD COLUMN (nullable)
  2. ADD COLUMN with DEFAULT
  3. DROP COLUMN
  4. ADD INDEX
  5. DROP INDEX
- [x] After each ALTER:
  - Existing clock entries are preserved (same col_version, db_version for unchanged columns)
  - New columns have clock entries backfilled (col_version = 1, current db_version)
  - Dropped columns have clock entries removed
- [ ] Clock state matches exactly between implementations. **DIVERGENCE FOUND - see notes**
- [x] Test covers edge cases:
  - ALTER on empty table
  - ALTER on table with 1000+ rows (batching behavior)
  - Multiple ALTERs in sequence
  - ALTER that adds column then immediately updates it
- [x] Test fails if clock history diverges.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

### 2025-12-20
- Implemented comprehensive test suite in `zig/harness/test-alter-parity.sh`
- Wired test into `zig/harness/test-parity.sh`
- **Key Divergence Found**: Zig backfills clock entries for new columns, Rust does NOT

## Completion Notes

### Test Results: PASSED: 16, FAILED: 3

### Files Modified
1. `zig/harness/test-alter-parity.sh` - Comprehensive ALTER TABLE parity test (rewritten)
2. `zig/harness/test-parity.sh` - Wired in test-alter-parity.sh

### Test Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite/zig/harness
bash test-alter-parity.sh
```

### Key Findings

#### Behavioral Divergences (Zig vs Rust/C Oracle)

1. **ADD COLUMN Backfill Behavior** (DIVERGENCE):
   - **Rust**: Does NOT create clock entries for new columns after ADD COLUMN
   - **Zig**: DOES backfill clock entries (col_version=1) for all existing rows
   - This is a fundamental design difference that affects sync behavior

2. **DROP COLUMN Clock Cleanup** (PASS):
   - Both implementations correctly remove clock entries for dropped columns

3. **INDEX Operations** (PASS):
   - ADD INDEX and DROP INDEX preserve clock state in both implementations

4. **Existing History Preservation** (PASS):
   - Both implementations preserve existing col_version/db_version during ALTER

5. **UPDATE After ADD COLUMN** (DIVERGENCE):
   - Rust: Creates clock entry only when column is updated (lazy)
   - Zig: Already has backfilled entry, UPDATE increments col_version

#### Clock Table Schema Difference
- Rust uses `key` column for primary key
- Zig uses `pk` column for primary key
- Tests normalize this by aliasing `key AS pk` for comparison

### Implications

The backfill divergence means:
- **Zig**: After ADD COLUMN, all rows appear "changed" in crsql_changes for the new column
- **Rust**: After ADD COLUMN, new column only appears in crsql_changes when explicitly updated

This affects sync scenarios where:
- A peer adds a column and syncs to another peer
- Zig will send backfill entries for all rows
- Rust will only send entries for rows that were explicitly updated

### Recommendation
This divergence should be documented and a decision made on which behavior is correct:
1. Zig's eager backfill ensures all peers have consistent NULL/DEFAULT values tracked
2. Rust's lazy approach reduces sync traffic but may cause version inconsistencies

### Note on Local Extension
The `lib/crsqlite.dylib` in the repo appears to have a bug with `crsql_commit_alter` ("failed compacting tables post alteration"). Tests use `nix run github:subtleGradient/sqlite-cr` which has a working cr-sqlite version.
