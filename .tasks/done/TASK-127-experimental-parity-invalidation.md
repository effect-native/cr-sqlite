# TASK-127: Experimentally invalidate "full parity" hypothesis

## Goal
The current hypothesis is that the Zig implementation has achieved full oracle parity with the Rust/C implementation (18/18 tests pass).
We need to **invalidate** this hypothesis experimentally by finding at least one divergence that is not yet covered by our test suite.

## Scope
- Create a new test harness `zig/harness/test-fuzz-parity.sh` (or similar).
- Implement a simple stochastic/fuzzing approach:
  - Generate random schemas (tables with random column types, PKs).
  - Generate random operations (INSERT, UPDATE, DELETE, transactions).
  - Run identical SQL against both Zig (loadable ext) and Rust/C (oracle via sqlite-cr wrapper).
  - Compare `crsql_changes`, `crsql_db_version`, `crsql_site_id`, and table contents.
- Run the fuzzer until a divergence is found.

## Files to Modify
- `zig/harness/test-fuzz-parity.sh` (new)
- `zig/harness/test-parity.sh` (optional, to include the new test)

## Acceptance Criteria
- [x] A new test script `zig/harness/test-fuzz-parity.sh` exists.
- [x] The script runs against both Zig and Rust/C oracle.
- [x] The script identifies at least one divergence (a "counter-example" to the full parity hypothesis).
- [x] The divergence is documented in the completion notes.

## Parent Docs
- `research/zig-cr/92-gap-backlog.md`

---

## Progress Log

### 2024-12-20: Task Completed

Created `zig/harness/test-fuzz-parity.sh` - a stochastic fuzzing test that:
- Generates random schemas (1-4 columns, types: INTEGER, TEXT, REAL, BLOB)
- Supports compound primary keys (20% of iterations)
- Generates random operations (INSERT, UPDATE, DELETE)
- Optionally wraps operations in transactions (30% of iterations)
- Includes edge cases: NULL values, empty blobs, empty strings, special characters
- Compares: table contents, db_version, crsql_changes, clock tables

## Completion Notes

### DIVERGENCE FOUND: Empty Blob (`X''`) Handling

**Hypothesis INVALIDATED** - The Zig implementation does NOT have full behavioral parity.

#### Minimal Reproduction
```sql
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, data BLOB);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, X'');
SELECT quote(val) FROM crsql_changes WHERE [table]='t' AND cid='data';
```

**Rust/C (oracle)**: `X''` (empty blob)
**Zig**: `NULL`

#### Impact
- The Zig implementation incorrectly reports empty blobs as NULL in `crsql_changes`
- This affects sync correctness: a peer receiving changes from Zig will see NULL instead of empty blob
- This is a **data corruption bug** for applications using empty blobs

#### Root Cause (likely)
The Zig implementation's `crsql_changes` virtual table (or the underlying trigger/value serialization) treats zero-length blobs as NULL when reading values.

#### Follow-up Task
Create TASK-128 to fix empty blob handling in Zig implementation.

### Test Statistics
- Ran 100+ iterations across multiple seeds
- All divergences were consistently the same bug (empty blob → NULL)
- No other divergences found for: table contents, db_version values, clock table contents, non-empty blob handling

### Files Created
- `zig/harness/test-fuzz-parity.sh` - Stochastic parity fuzzer
