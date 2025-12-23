# TASK-177 — Test DEFAULT value merge semantics

## Goal
Verify Zig handles DEFAULT column values correctly during merge.

## Status
- State: triage
- Priority: high (schema evolution)

## Context
From Python `test_sync.py::test_merging_on_defaults`:
- Column with DEFAULT value vs explicit value
- Which wins during merge?
- What if DEFAULT is larger than explicit value?

This affects schema migrations where columns are added with DEFAULTs.

## Files to Modify
- `zig/harness/test-default-merge.sh` (new)

## Acceptance Criteria
1. Site A: table with column having DEFAULT 'default_val'
2. Site A: INSERT without specifying column (uses default)
3. Site B: same schema
4. Site B: INSERT same PK with explicit value 'explicit_val'
5. Sync A to B
6. Verify: which value wins? (explicit should win if higher col_version)
7. Test reverse: DEFAULT value is "larger" lexicographically
8. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Python test: `py/correctness/tests/test_sync.py`
- Related: TASK-173 (schema mismatch)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
