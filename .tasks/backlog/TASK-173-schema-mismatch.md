# TASK-173 — Schema mismatch during sync tests

## Goal
Verify Zig handles schema mismatches gracefully during sync.

## Status
- State: backlog
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

## Completion Notes
(Empty until done.)
