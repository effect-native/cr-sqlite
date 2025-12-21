# Test Gap Analysis: Existing Tests vs Ideal Experiments

**Date:** 2024-12-20
**Reference:** `96-ideal-parity-experiments.md`

This document maps the 157 ideal experiments to existing test infrastructure and
identifies gaps that need new tests.

---

## Gap Summary

| Category | Gap Type | Count | Priority |
|----------|----------|-------|----------|
| Test Script Bugs | Fix existing tests | 3 | P0 (BLOCKING) |
| Wire Format | Missing edge case tests | 21 | P1 |
| Merge Resolution | Missing value comparison tests | 9 | P1 |
| Edge Cases | Missing boundary tests | 14 | P2 |
| Cross-Open | Missing interop tests | 3 | P2 |
| Stress | Missing performance tests | 3 | P3 |

---

## P0: Test Script Bugs (BLOCKING)

These bugs prevent accurate parity assessment. Fix first.

### GAP-001: test-trigger-parity.sh uses wrong column name

**File:** `zig/harness/test-trigger-parity.sh:97-98`
**Bug:** Queries `pk` column but Zig uses `key`
**Fix:** Change `pk` to `key` in dump_clock_zig function
**Impact:** 15 tests showing false failures
**Experiments Blocked:** TR-001 through TR-030

### GAP-002: test-alter-parity.sh uses wrong column name

**File:** `zig/harness/test-alter-parity.sh`
**Bug:** Same issue - queries `pk` instead of `key`
**Fix:** Change `pk` to `key` 
**Impact:** 10 tests showing false failures
**Experiments Blocked:** AT-001 through AT-004

### GAP-003: test-api-surface.sh wrong extension path

**File:** `zig/harness/test-api-surface.sh`
**Bug:** Looks for `lib/crsqlite.dylib` instead of platform-specific path
**Fix:** Use same platform detection as other tests
**Impact:** Entire test skipped
**Experiments Blocked:** None (API surface, not parity)

---

## P1: Missing Critical Parity Tests

### GAP-010: Wire Format Edge Cases

**Missing experiments:** WF-007 through WF-015

**What's needed:**
```bash
# test-wire-format-edge-cases.sh
# Add to test-oracle-parity.sh or create new file

# WF-007: Empty string
run_both "SELECT hex(crsql_pack_columns(''));"

# WF-009: Zero
run_both "SELECT hex(crsql_pack_columns(0));"

# WF-010: Negative one
run_both "SELECT hex(crsql_pack_columns(-1));"

# WF-011: MAX_INT64
run_both "SELECT hex(crsql_pack_columns(9223372036854775807));"

# WF-012: MIN_INT64
run_both "SELECT hex(crsql_pack_columns(-9223372036854775808));"

# WF-013: MAX_FLOAT
run_both "SELECT hex(crsql_pack_columns(1.7976931348623157e+308));"

# WF-014: Unicode/emoji
run_both "SELECT hex(crsql_pack_columns('🎉'));"
```

**Existing coverage:** test-oracle-parity.sh covers basic types but not edge cases
**Priority:** P1 - Wire format mismatch breaks sync

### GAP-011: PK Blob Format Edge Cases

**Missing experiments:** WF-021 through WF-027

**What's needed:**
```bash
# Test non-integer primary keys
# WF-021: Text PK
CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL);
INSERT INTO t VALUES('hello');
SELECT hex(pk) FROM crsql_changes;

# WF-022: Blob PK
CREATE TABLE t(id BLOB PRIMARY KEY NOT NULL);
INSERT INTO t VALUES(X'DEADBEEF');
SELECT hex(pk) FROM crsql_changes;

# WF-026: Unicode text PK
CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL);
INSERT INTO t VALUES('🎉');
SELECT hex(pk) FROM crsql_changes;
```

**Existing coverage:** test-oracle-parity.sh tests integer PK only
**Priority:** P1 - Non-integer PKs are common

### GAP-012: Merge Resolution Value Comparison

**Missing experiments:** MR-020 through MR-025

**What's needed:**
```bash
# When cv is equal, value comparison determines winner
# Need to test all type combinations

# MR-020: String comparison
# Insert 'apple' locally, merge 'banana' remotely with same cv
# Expected: 'banana' wins (lexicographic)

# MR-021: Integer comparison
# Insert 100 locally, merge 99 remotely with same cv
# Expected: 100 wins (larger value)

# MR-022: NULL vs value
# What happens when local is NULL, remote is 'value'?

# MR-024: Float comparison
# Insert 3.14 locally, merge 3.15 remotely with same cv
# Expected: 3.15 wins

# MR-025: Blob comparison
# Insert X'AA' locally, merge X'BB' remotely with same cv
# Expected: X'BB' wins (lexicographic)
```

**Existing coverage:** test-merge.sh tests cv/cl but not value tiebreaker
**Priority:** P1 - Affects CRDT convergence correctness

### GAP-013: Delete/Resurrection Edge Cases

**Missing experiments:** MR-041 through MR-043

**What's needed:**
```bash
# Test full lifecycle: insert -> delete -> resurrect
# Verify cl increments correctly through each phase

# MR-042: Explicit cl behavior
# Local: cl=1 (live), cv=5
# Remote: cl=2 (deleted), cv=1
# Expected: Deleted wins (cl=2 > cl=1)

# MR-043: Resurrection
# Local: cl=2 (deleted)
# Remote: cl=3 (resurrected), cv=1
# Expected: Resurrected wins (cl=3 > cl=2)
```

**Existing coverage:** test-resurrection.sh exists but may not test oracle parity
**Priority:** P1 - Affects conflict resolution correctness

---

## P2: Missing Secondary Tests

### GAP-020: Cross-Open Interoperability

**Missing experiments:** XO-003 through XO-006

**What's needed:**
```bash
# XO-003: Zig creates, Rust modifies, Zig reads
# 1. Create DB with Zig, INSERT row
# 2. Open with Rust, UPDATE row
# 3. Open with Zig, verify UPDATE visible

# XO-004: Rust creates, Zig modifies, Rust reads
# Reverse of above

# XO-006: Multiple alternating opens
# Zig INSERT -> Rust UPDATE -> Zig DELETE -> Rust INSERT
# Verify final state is consistent
```

**Existing coverage:** test-oracle-parity.sh tests read-only cross-open
**Priority:** P2 - Important for real-world usage

### GAP-021: Edge Case Boundary Values

**Missing experiments:** EC-010 through EC-014, EC-020 through EC-022

**What's needed:**
```bash
# Boundary values
# EC-010: MAX_INT64 roundtrip through sync
# EC-011: MIN_INT64 roundtrip through sync
# EC-012: MAX_FLOAT roundtrip through sync
# EC-013: 1MB text roundtrip
# EC-014: 1MB blob roundtrip

# Special characters
# EC-020: Emoji in synced data
# EC-021: NULL bytes in text columns
# EC-022: SQL injection attempts
```

**Existing coverage:** test-large-data.sh tests volume, not boundary values
**Priority:** P2 - Edge cases that could cause production issues

### GAP-022: Config Isolation

**Missing experiment:** CF-007

**What's needed:**
```bash
# CF-007: Config resets on new connection
# Set merge-equal-values=0
# Close connection
# Open new connection
# Verify merge-equal-values is back to default (1)
```

**Existing coverage:** test-config.sh tests persistence within connection
**Priority:** P2 - Affects multi-connection behavior

---

## P3: Nice to Have

### GAP-030: Stress/Performance Tests

**Missing experiments:** ST-002 through ST-004

**What's needed:**
```bash
# ST-002: 100k changes batch
# Verify memory stays bounded, no OOM

# ST-003: 1000 concurrent row operations
# Verify no deadlock in WAL mode

# ST-004: Rapid INSERT/DELETE cycles
# 1000 rapid insert/delete on same PK
# Verify clock stays consistent
```

**Existing coverage:** test-large-data.sh tests 10k rows
**Priority:** P3 - Performance edge cases

---

## Task Card Mapping

Based on this analysis, the following task cards should be created:

| Task ID | Description | Priority | Experiments |
|---------|-------------|----------|-------------|
| TASK-130 | Fix test-trigger-parity.sh column name bug | P0 | TR-001-030 |
| TASK-131 | Fix test-alter-parity.sh column name bug | P0 | AT-001-004 |
| TASK-132 | Add wire format edge case parity tests | P1 | WF-007-015 |
| TASK-133 | Add PK blob format edge case tests | P1 | WF-021-027 |
| TASK-134 | Add merge value comparison tests | P1 | MR-020-025 |
| TASK-135 | Add delete/resurrection parity tests | P1 | MR-041-043 |
| TASK-136 | Add cross-open modification tests | P2 | XO-003-006 |
| TASK-137 | Add boundary value edge case tests | P2 | EC-010-022 |
| TASK-138 | Add config isolation test | P2 | CF-007 |
| TASK-139 | Add stress/performance tests | P3 | ST-002-004 |

---

## Recommended Execution Order

1. **Phase 1 (P0 - Unblock Tests):** TASK-130, TASK-131
   - Required to get accurate parity assessment
   - Minimal code changes, test script fixes only

2. **Phase 2 (P1 - Critical Parity):** TASK-132, TASK-133, TASK-134, TASK-135
   - Validates sync correctness
   - Any failures here indicate real bugs

3. **Phase 3 (P2 - Secondary Coverage):** TASK-136, TASK-137, TASK-138
   - Validates production readiness
   - Important for edge cases

4. **Phase 4 (P3 - Performance):** TASK-139
   - Nice to have
   - Can be deferred
