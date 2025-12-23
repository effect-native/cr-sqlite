# TASK-173 — Schema mismatch during sync tests

## Goal
Verify Zig handles schema mismatches gracefully during sync.

## Status
- State: active → done
- Priority: medium (production scenario)
- Parallelizable: YES (no file conflicts with other backlog tasks)

## Context
Different sites may have different schemas due to staggered migrations. Need to document and test behavior.

## Files to Modify
- `zig/harness/test-schema-mismatch.sh` (new, ~200 lines)
- `zig/harness/test-parity.sh` (wire in new test)

## Acceptance Criteria
1. Test: source has column destination doesn't
2. Test: destination has column source doesn't
3. Document behavior for each case (error? ignored? partial?)
4. Zig and Rust/C produce identical behavior
5. No data corruption in any case

## Test Skeleton
```bash
#!/usr/bin/env bash
# test-schema-mismatch.sh - Schema mismatch handling

test_source_has_extra_column() {
    # Site A: table with columns (id, name, extra)
    # Site B: table with columns (id, name) - no 'extra'
    # Site A: INSERT with extra='value'
    # Sync A changes to B
    # Document: what happens to 'extra' column data?
}

test_dest_has_extra_column() {
    # Site A: table with columns (id, name)
    # Site B: table with columns (id, name, extra)
    # Site A: INSERT
    # Sync A changes to B
    # Verify: row created, extra column is NULL/default
}

test_type_mismatch() {
    # Site A: column 'val' is INTEGER
    # Site B: column 'val' is TEXT
    # Site A: INSERT val=42
    # Sync A to B
    # Document: type coercion or error?
}
```

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.
- 2025-12-22: Implemented test-schema-mismatch.sh (~450 lines)
- 2025-12-22: Wired into test-parity.sh
- 2025-12-22: Ran tests against both Zig and Rust/C oracle

## Completion Notes

### Test Results: 11 PASSED, 1 DIVERGENCE

### Test 1: Source has extra column (destination doesn't)
- **Scenario**: Site A has (id, name, extra), Site B has (id, name)
- **Zig behavior**: ERROR - Returns error when applying changeset for non-existent column
- **Rust/C behavior**: IGNORED - Gracefully ignores the changeset
- **DIVERGENCE FOUND**: Zig errors, Rust ignores
- **Data integrity**: Both successfully sync known columns (name='Alice')
- **Schema integrity**: Both preserve destination schema (2 columns)

### Test 2: Destination has extra column (source doesn't)
- **Scenario**: Site A has (id, name), Site B has (id, name, extra)
- **Zig behavior**: PASS - Row synced, extra column gets default value
- **Rust/C behavior**: PASS - Identical behavior
- **PARITY VERIFIED**

### Test 3: Type mismatch (INTEGER vs TEXT)
- **Scenario**: Site A has val INTEGER, Site B has val TEXT
- **Zig behavior**: 42~text - Value synced, stored as text type
- **Rust/C behavior**: 42~text - Identical behavior
- **PARITY VERIFIED**
- **Reverse (TEXT→INTEGER)**: Both store 'hello' as text (SQLite flexible typing)

### Files Created/Modified
- `zig/harness/test-schema-mismatch.sh` (new, ~450 lines)
- `zig/harness/test-parity.sh` (added schema mismatch test runner)

### Commands to Reproduce
```bash
cd zig/harness
bash test-schema-mismatch.sh
```

### Known Divergence (needs follow-up)
The Zig implementation returns an error when trying to apply a changeset for a column
that doesn't exist on the destination table. The Rust/C oracle gracefully ignores such
changesets. This is a behavioral difference that may need to be addressed if Zig aims
for full parity with Rust/C behavior.

Recommendation: File follow-up task for graceful ignore behavior in Zig.
