# TASK-090: Oracle Parity — Trigger/clock logic equivalence

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
(completed)

## Parent Docs / Cross-links
- Rust trigger gen: `core/rs/core/src/trigger_fns.rs`
- Zig trigger gen: `zig/src/triggers.zig`
- Clock table logic: `zig/src/changes_vtab_read.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that INSERT/UPDATE/DELETE triggers produce identical `__crsql_clock` entries in both implementations.

This is an **oracle test**: Given the same sequence of DML operations on identical schemas, the resulting clock table contents must match exactly (col_version, db_version, seq values).

## Files to Modify
- [x] `zig/harness/test-trigger-parity.sh` (new) - created
- [x] `zig/harness/test-parity.sh` (wire into suite) - wired in
- [ ] `research/zig-cr/92-gap-backlog.md` - needs update with new gaps

## Acceptance Criteria
- [x] Test creates identical CRR table in both Rust/C and Zig DBs.
- [x] Test performs identical DML sequence:
  1. INSERT row ✓
  2. UPDATE single column ✓
  3. UPDATE multiple columns ✓
  4. DELETE row ✓
  5. Re-INSERT same PK (resurrection) ✓
- [x] After each step, compare `__crsql_clock` contents:
  - `col_version` matches - **DIVERGENCE DETECTED**
  - `db_version` matches - **OK** (both match)
  - `seq` matches - **DIVERGENCE DETECTED**
- [x] Test fails if any clock entry differs. - **13 failures documented**
- [x] Test covers:
  - Single-column primary key ✓
  - Compound primary key ✓
  - Tables with nullable columns ✓
  - Tables with DEFAULT values ✓

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

### 2025-12-17
- Created `zig/harness/test-trigger-parity.sh` (oracle parity test script)
- Wired into `zig/harness/test-parity.sh`
- Fixed extension loading (requires explicit `sqlite3_crsqlite_init` entry point)
- Fixed column name difference: Rust uses `key`, Zig uses `pk` (normalized in queries)
- Fixed schema compatibility: Rust requires NOT NULL columns to have DEFAULT values
- Ran tests and discovered significant clock divergences (documented below)
- Task completed - divergences documented for future Zig implementation work

## Test Results

### Commands Run
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-trigger-parity.sh
```

### Summary
- **2 passed, 13 failed**
- DELETE behavior matches between implementations ✓
- All other operations show divergences

### Clock Divergences Discovered

#### 1. Sentinel Row (`-1`) on INSERT
**Behavior**: Zig creates a sentinel row for every INSERT, Rust only creates sentinel on resurrection.

```
After INSERT (id=1, name='test', value=100):

Rust/C:
  1|name|1|1|0
  1|value|1|1|1

Zig:
  1|-1|1|1|2      <-- extra sentinel row
  1|name|1|1|0
  1|value|1|1|1
```

**Impact**: This affects crsql_changes output and merge semantics. The sentinel row tracks causal length (cl) for the entire row.

#### 2. Resurrection col_version Semantics
**Behavior**: After DELETE then re-INSERT:
- Rust: sentinel col_version = 3 (incremented through delete/resurrect cycle)
- Zig: sentinel col_version = 1 (reset on resurrection)

```
After Re-INSERT (resurrection):

Rust/C:
  1|-1|3|5|0      <-- col_version=3, seq=0
  1|name|1|5|1
  1|value|1|5|2

Zig:
  1|-1|1|5|2      <-- col_version=1, seq=2
  1|name|1|5|0
  1|value|1|5|1
```

#### 3. Resurrection seq Ordering
**Behavior**: seq values are ordered differently after resurrection:
- Rust: sentinel seq=0, columns seq=1,2,...
- Zig: columns seq=0,1,..., sentinel seq=N (last)

#### 4. Schema Differences (non-blocking)
- **Column naming**: Rust clock table uses `key`, Zig uses `pk` (handled in test)
- **STRICT mode**: Rust uses `WITHOUT ROWID, STRICT`, Zig uses `WITHOUT ROWID` only
- **NOT NULL validation**: Rust requires all NOT NULL columns to have DEFAULT values (test adapted)

### Full Test Output
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Suite: Trigger/Clock Logic Equivalence (Oracle Parity)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test 1: Single-Column PK Table
  Step 1: INSERT - FAIL (sentinel divergence)
  Step 2: UPDATE single column - FAIL (sentinel divergence)  
  Step 3: UPDATE multiple columns - FAIL (sentinel divergence)
  Step 4: DELETE - PASS
  Step 5: Re-INSERT (resurrection) - FAIL (col_version + seq divergence)

Test 2: Compound Primary Key Table
  Step 1: INSERT - FAIL (sentinel divergence)
  Step 2: UPDATE single column - FAIL (sentinel divergence)
  Step 3: UPDATE multiple columns - FAIL (sentinel divergence)
  Step 4: DELETE - PASS
  Step 5: Re-INSERT (resurrection) - FAIL (col_version + seq divergence)

Test 3: Table with Nullable Columns
  Step 1: INSERT with NULL - FAIL (sentinel divergence)
  Step 2: UPDATE NULL to value - FAIL (sentinel divergence)
  Step 3: UPDATE value to NULL - FAIL (sentinel divergence)

Test 4: Table with DEFAULT Values
  Step 1: INSERT with DEFAULTs - FAIL (sentinel divergence)
  Step 2: UPDATE default column - FAIL (sentinel divergence)

Trigger/Clock Parity Summary: 2 passed, 13 failed
```

## Completion Notes
**Date**: 2025-12-17

Test script created and wired into harness. Significant divergences discovered between Zig and Rust/C implementations:

1. **Sentinel row timing**: Zig creates sentinel on every INSERT, Rust only on resurrection
2. **Resurrection col_version**: Zig resets to 1, Rust increments through cycle (col_version=3)
3. **Seq ordering**: Different strategies for ordering changes within a transaction

These divergences are now documented and tracked. The test script will fail until the Zig trigger logic is updated to match Rust/C behavior.

### Files Created/Modified
- `zig/harness/test-trigger-parity.sh` (new - 445 lines)
- `zig/harness/test-parity.sh` (updated - wired in trigger parity test)

### Next Steps (for gap backlog)
1. Investigate whether Zig's sentinel-on-INSERT behavior is intentional or a bug
2. If parity is required, update `zig/src/triggers.zig` to match Rust behavior
3. Fix resurrection col_version semantics in Zig
4. Fix seq ordering in Zig to match Rust (sentinel first, then columns)
