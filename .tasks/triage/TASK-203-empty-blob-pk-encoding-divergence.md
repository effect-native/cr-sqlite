# TASK-203 — Empty Blob PK Encoding Divergence

## Goal
Fix the PK blob encoding for empty blob primary keys to match Rust/C oracle.

## Status
- State: triage
- Priority: LOW (edge case, not blocking sync)
- Discovered: 2025-12-20 (TASK-133)

## Problem

When a table has an empty blob (`X''`) as its primary key value, the encoded PK in `crsql_changes` differs:

```
Zig:    0105
Rust/C: 0104
```

## Reproduction

```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-pk-blob-parity.sh
```

Look for test WF-028.

## Impact

This only affects tables with:
1. BLOB primary keys
2. That contain empty blob values

This is a rare edge case and doesn't affect sync correctness (the blob value itself syncs correctly, just the encoding differs).

## Files to Investigate

- `zig/src/pack_columns.zig` — PK blob encoding logic
- `core/rs/core/src/pack_columns.rs` — Rust reference

## Acceptance Criteria

1. [ ] Empty blob PK encoded as `0104` (matching Rust/C)
2. [ ] `bash zig/harness/test-pk-blob-parity.sh` passes 9/9

## Parent Docs / Cross-links

- Test: `zig/harness/test-pk-blob-parity.sh` (WF-028)
- Related: `.tasks/done/TASK-133-pk-blob-format-edge-case-parity.md`

## Progress Log
- 2025-12-25: Created from Round 73 test results.

## Completion Notes
(Empty until done.)
