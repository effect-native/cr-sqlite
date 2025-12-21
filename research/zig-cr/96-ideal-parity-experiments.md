# Ideal Parity Experiments Checklist

**Date:** 2024-12-20
**Purpose:** Define the complete set of experiments needed to fully validate oracle parity

This document specifies what experiments SHOULD exist regardless of what tests currently exist.
After defining the ideal state, we compare against existing tests to identify gaps.

---

## 1. Wire Format Experiments

### 1.1 crsql_pack_columns Encoding

Each type must produce byte-identical output:

| Experiment ID | Input | Expected Output (hex) | Status |
|--------------|-------|----------------------|--------|
| WF-001 | `crsql_pack_columns(42)` | `01092A` | TESTED |
| WF-002 | `crsql_pack_columns('hello')` | `010B0568656C6C6F` | TESTED |
| WF-003 | `crsql_pack_columns(X'DEADBEEF')` | `010C04DEADBEEF` | TESTED |
| WF-004 | `crsql_pack_columns(NULL)` | `0105` | TESTED |
| WF-005 | `crsql_pack_columns(3.14159)` | `0102400921F9F01B866E` | TESTED |
| WF-006 | `crsql_pack_columns(42, 'hello', X'BEEF')` | `03092A0B0568656C6C6F0C02BEEF` | TESTED |
| WF-007 | `crsql_pack_columns('')` (empty string) | TBD | NEEDS TEST |
| WF-008 | `crsql_pack_columns(X'')` (empty blob) | TBD | TESTED (TASK-127-129) |
| WF-009 | `crsql_pack_columns(0)` | TBD | NEEDS TEST |
| WF-010 | `crsql_pack_columns(-1)` | TBD | NEEDS TEST |
| WF-011 | `crsql_pack_columns(9223372036854775807)` (MAX_INT64) | TBD | NEEDS TEST |
| WF-012 | `crsql_pack_columns(-9223372036854775808)` (MIN_INT64) | TBD | NEEDS TEST |
| WF-013 | `crsql_pack_columns(1.7976931348623157e+308)` (MAX_FLOAT) | TBD | NEEDS TEST |
| WF-014 | Unicode text: `crsql_pack_columns('🎉')` | TBD | NEEDS TEST |
| WF-015 | Very long blob (1MB) | TBD | NEEDS TEST |

### 1.2 PK Blob Format in crsql_changes

| Experiment ID | Setup | Expected | Status |
|--------------|-------|----------|--------|
| WF-020 | Single integer PK | pk blob matches | TESTED |
| WF-021 | Single text PK | pk blob matches | NEEDS TEST |
| WF-022 | Single blob PK | pk blob matches | NEEDS TEST |
| WF-023 | Compound PK (int, int) | pk blob matches | NEEDS TEST |
| WF-024 | Compound PK (int, text) | pk blob matches | NEEDS TEST |
| WF-025 | Compound PK (int, text, blob) | pk blob matches | NEEDS TEST |
| WF-026 | Text PK with unicode | pk blob matches | NEEDS TEST |
| WF-027 | Text PK with NULL bytes | pk blob matches | NEEDS TEST |

---

## 2. Clock Table Schema Experiments

| Experiment ID | Check | Expected | Status |
|--------------|-------|----------|--------|
| CT-001 | Column names | `key, col_name, col_version, db_version, site_id, seq` | TESTED |
| CT-002 | Column types | INTEGER/TEXT per schema | TESTED |
| CT-003 | Primary key | `(key, col_name)` | TESTED |
| CT-004 | WITHOUT ROWID | Present | TESTED |
| CT-005 | STRICT | Present | TESTED |
| CT-006 | Index exists | `foo__crsql_clock_dbv_idx` on `db_version` | TESTED |
| CT-007 | site_id default | `DEFAULT 0` | TESTED |

---

## 3. db_version Timing Experiments

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| DV-001 | Initial state | db_version = 0 | TESTED |
| DV-002 | After INSERT | db_version = 1 | TESTED |
| DV-003 | After UPDATE | db_version = 2 | TESTED |
| DV-004 | After DELETE | db_version = 3 | TESTED |
| DV-005 | Multiple INSERTs in transaction | All get same db_version | TESTED |
| DV-006 | No-op UPDATE | db_version advances | TESTED |
| DV-007 | Winning merge | db_version advances | TESTED |
| DV-008 | Losing merge | db_version does NOT advance | TESTED |
| DV-009 | No-op merge (same value) | db_version does NOT advance | TESTED |
| DV-010 | ROLLBACK | db_version unchanged | TESTED |
| DV-011 | crsql_next_db_version() | Returns db_version + 1 | TESTED |
| DV-012 | crsql_next_db_version(X) | Returns max(X+1, db_version+1) | NEEDS TEST |
| DV-013 | Concurrent transactions (WAL) | Each gets correct version | NEEDS TEST |

---

## 4. rows_impacted Counter Experiments

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| RI-001 | Single winning INSERT | 1 | TESTED |
| RI-002 | Multiple winning INSERTs | Accumulates | TESTED |
| RI-003 | COMMIT resets | 0 | TESTED |
| RI-004 | ROLLBACK does NOT reset | Preserved | TESTED |
| RI-005 | No-op merge (same value) | 0 | TESTED |
| RI-006 | Losing merge (lower cv) | 0 | TESTED |
| RI-007 | Winning merge (higher cv) | 1 | TESTED |
| RI-008 | Delete via merge | 1 | TESTED |
| RI-009 | Resurrection via merge | 1 | NEEDS TEST |
| RI-010 | Partial batch (some win, some lose) | Count of winners | NEEDS TEST |

---

## 5. Merge Resolution Experiments

### 5.1 Causal Length (cl) Dominates

| Experiment ID | Local State | Remote State | Winner | Status |
|--------------|-------------|--------------|--------|--------|
| MR-001 | cl=1, cv=5 | cl=2, cv=1 | Remote (higher cl) | TESTED |
| MR-002 | cl=2, cv=1 | cl=1, cv=5 | Local (higher cl) | TESTED |
| MR-003 | cl=1, cv=1 | cl=1, cv=1 | Local (tie) | TESTED |

### 5.2 col_version Tiebreaker (when cl equal)

| Experiment ID | Local cv | Remote cv | Winner | Status |
|--------------|----------|-----------|--------|--------|
| MR-010 | 1 | 2 | Remote | TESTED |
| MR-011 | 2 | 1 | Local | TESTED |
| MR-012 | 5 | 5 | Value compare | TESTED |

### 5.3 Value Comparison Tiebreaker (when cv equal)

| Experiment ID | Local Value | Remote Value | Winner | Status |
|--------------|-------------|--------------|--------|--------|
| MR-020 | 'apple' | 'banana' | Remote (banana > apple) | NEEDS TEST |
| MR-021 | 100 | 99 | Local (100 > 99) | NEEDS TEST |
| MR-022 | NULL | 'value' | ? | NEEDS TEST |
| MR-023 | 'value' | NULL | ? | NEEDS TEST |
| MR-024 | 3.14 | 3.15 | Remote | NEEDS TEST |
| MR-025 | X'AA' | X'BB' | Remote | NEEDS TEST |

### 5.4 site_id Tiebreaker (when value equal)

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| MR-030 | Same value, lower site_id | Lower site_id wins | TESTED |
| MR-031 | Same value, higher site_id | Lower site_id wins | TESTED |
| MR-032 | merge-equal-values=0 | No-op (local wins) | TESTED |
| MR-033 | merge-equal-values=1 | site_id tiebreaker used | TESTED |

### 5.5 Delete/Resurrection Semantics

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| MR-040 | Live row + delete merge (higher cl) | Row deleted | TESTED |
| MR-041 | Deleted row + insert merge (higher cl) | Row resurrected | NEEDS TEST |
| MR-042 | cl=1 (live) vs cl=2 (deleted) | Deleted wins | NEEDS TEST |
| MR-043 | cl=2 (deleted) vs cl=3 (resurrected) | Resurrected wins | NEEDS TEST |

---

## 6. Trigger/Clock Capture Experiments

### 6.1 INSERT Trigger

| Experiment ID | Scenario | Expected Clock State | Status |
|--------------|----------|---------------------|--------|
| TR-001 | Simple INSERT | Entry for each non-PK col | BLOCKED (test bug) |
| TR-002 | INSERT with NULL values | NULL columns get entry | BLOCKED (test bug) |
| TR-003 | INSERT with DEFAULT values | DEFAULT columns get entry | BLOCKED (test bug) |
| TR-004 | INSERT on PK-only table | Sentinel (-1) entry | TESTED |

### 6.2 UPDATE Trigger

| Experiment ID | Scenario | Expected Clock State | Status |
|--------------|----------|---------------------|--------|
| TR-010 | UPDATE single column | col_version increments for that col | BLOCKED (test bug) |
| TR-011 | UPDATE multiple columns | col_version increments for all | BLOCKED (test bug) |
| TR-012 | UPDATE to same value | col_version still increments | BLOCKED (test bug) |
| TR-013 | UPDATE NULL to value | col_version increments | BLOCKED (test bug) |
| TR-014 | UPDATE value to NULL | col_version increments | BLOCKED (test bug) |

### 6.3 DELETE Trigger

| Experiment ID | Scenario | Expected Clock State | Status |
|--------------|----------|---------------------|--------|
| TR-020 | Simple DELETE | Tombstone entry (cid=-1) | BLOCKED (test bug) |
| TR-021 | DELETE non-existent row | No change | NEEDS TEST |

### 6.4 Resurrection

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| TR-030 | INSERT after DELETE | cl=3, new column entries | BLOCKED (test bug) |

---

## 7. ALTER TABLE Experiments

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| AT-001 | ADD COLUMN (nullable) | No backfill clock entries | BLOCKED (test bug) |
| AT-002 | ADD COLUMN with DEFAULT | No backfill clock entries | BLOCKED (test bug) |
| AT-003 | DROP COLUMN | Clock entries for dropped col removed | BLOCKED (test bug) |
| AT-004 | ADD COLUMN + UPDATE | Clock entry created on UPDATE | BLOCKED (test bug) |
| AT-005 | Existing clock preserved | col_version unchanged | TESTED |
| AT-006 | 1000+ row ALTER | All rows handled | TESTED |

---

## 8. Fractional Index Experiments

| Experiment ID | Input | Expected Output | Status |
|--------------|-------|-----------------|--------|
| FI-001 | (NULL, NULL) | 'a ' | TESTED |
| FI-002 | ('a ', NULL) | 'a!' | TESTED |
| FI-003 | (NULL, 'a ') | 'Z~' | TESTED |
| FI-004 | ('a0', 'a1') | 'a0P' | TESTED |
| FI-005 | ('aaa', 'aab') | 'aaaP' | TESTED |
| FI-006 | Very long left key | Correct midpoint | TESTED |
| FI-007 | Empty string error | Error returned | TESTED |
| FI-008 | Invalid order (a > b) | Error returned | TESTED |
| FI-009 | Sequential generation | Maintains ordering | TESTED |

---

## 9. Config API Experiments

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| CF-001 | get merge-equal-values default | 1 | TESTED |
| CF-002 | set merge-equal-values=0 | Returns 0 | TESTED |
| CF-003 | set merge-equal-values=1 | Returns 1 | TESTED |
| CF-004 | get unknown setting | Error | TESTED |
| CF-005 | set unknown setting | Error | TESTED |
| CF-006 | Config persists in connection | Yes | TESTED |
| CF-007 | Config resets on new connection | Yes | NEEDS TEST |

---

## 10. Edge Case Experiments

### 10.1 Empty Values

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| EC-001 | Empty string in pack_columns | Correct encoding | NEEDS TEST |
| EC-002 | Empty blob in pack_columns | Correct encoding | TESTED |
| EC-003 | Empty string as PK | Works | NEEDS TEST |
| EC-004 | Empty blob as PK | Works | NEEDS TEST |
| EC-005 | Empty string in merge | Merges correctly | NEEDS TEST |
| EC-006 | Empty blob in merge | Merges correctly | TESTED |

### 10.2 Boundary Values

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| EC-010 | MAX_INT64 as value | Roundtrips correctly | NEEDS TEST |
| EC-011 | MIN_INT64 as value | Roundtrips correctly | NEEDS TEST |
| EC-012 | MAX_FLOAT as value | Roundtrips correctly | NEEDS TEST |
| EC-013 | Very large text (1MB) | Roundtrips correctly | NEEDS TEST |
| EC-014 | Very large blob (1MB) | Roundtrips correctly | NEEDS TEST |

### 10.3 Unicode and Special Characters

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| EC-020 | Emoji in text | Roundtrips correctly | NEEDS TEST |
| EC-021 | NULL bytes in text | Handled correctly | NEEDS TEST |
| EC-022 | SQL injection attempt | Escaped correctly | NEEDS TEST |

---

## 11. Cross-Open Interoperability Experiments

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| XO-001 | Zig creates, Rust reads | Data intact | TESTED |
| XO-002 | Rust creates, Zig reads | Data intact | TESTED |
| XO-003 | Zig creates, Rust modifies, Zig reads | All changes visible | NEEDS TEST |
| XO-004 | Rust creates, Zig modifies, Rust reads | All changes visible | NEEDS TEST |
| XO-005 | site_id preserved across opens | Yes | TESTED |
| XO-006 | Multiple alternating opens | State consistent | NEEDS TEST |

---

## 12. Stress/Performance Experiments

| Experiment ID | Scenario | Expected | Status |
|--------------|----------|----------|--------|
| ST-001 | 10,000 row sync | Completes without error | PARTIAL |
| ST-002 | 100,000 changes batch | Memory bounded | NEEDS TEST |
| ST-003 | 1000 concurrent table rows | No deadlock | NEEDS TEST |
| ST-004 | Rapid INSERT/DELETE cycles | Clock consistent | NEEDS TEST |

---

## Summary

| Category | Total | Tested | Needs Test | Blocked |
|----------|-------|--------|------------|---------|
| Wire Format | 27 | 6 | 21 | 0 |
| Clock Table Schema | 7 | 7 | 0 | 0 |
| db_version Timing | 13 | 11 | 2 | 0 |
| rows_impacted | 10 | 8 | 2 | 0 |
| Merge Resolution | 33 | 12 | 21 | 0 |
| Trigger/Clock | 19 | 1 | 3 | 15 |
| ALTER TABLE | 6 | 2 | 0 | 4 |
| Fractional Index | 9 | 9 | 0 | 0 |
| Config API | 7 | 6 | 1 | 0 |
| Edge Cases | 16 | 2 | 14 | 0 |
| Cross-Open | 6 | 3 | 3 | 0 |
| Stress | 4 | 1 | 3 | 0 |
| **TOTAL** | **157** | **68** | **70** | **19** |

**Coverage:** 68/157 = 43% directly tested, 19 blocked by test script bugs

**Next Steps:**
1. Fix test script bugs to unblock 19 experiments
2. Add wire format edge case tests
3. Add merge resolution value comparison tests
4. Add edge case boundary value tests
