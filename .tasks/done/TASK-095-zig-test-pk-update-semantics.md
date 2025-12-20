# TASK-095: Zig test for PK UPDATE semantics

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Created by: `.tasks/active/TASK-073-compare-rust-zig-tests.md`
- Rust reference: `core/rs/integration_check/src/t/pk_only_tables.rs` (modify_pkonly_row, junction_table)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The Rust integration suite tests that UPDATE statements which modify primary key columns are correctly handled as delete + create operations. This is critical for sync correctness:

```sql
-- Original row
INSERT INTO foo (id, value) VALUES (1, 'abc');
-- PK update should generate:
--   1. DELETE tombstone for pk=1
--   2. INSERT for pk=2 with all values
UPDATE foo SET id = 2 WHERE id = 1;
```

The Zig harness does not currently test this behavior. This can cause sync divergence if implementations differ.

## Files to Modify
- `zig/harness/test-pk-update.sh` (new file)
- `zig/harness/test-parity.sh` (add test runner call)

## Acceptance Criteria
- [x] New test script `zig/harness/test-pk-update.sh` exists
- [x] Tests cover:
  - Single-column PK update (simple table)
  - Compound PK update (junction table - one column changed)
  - Compound PK update (all columns changed)
  - PK update on table with non-PK columns
- [ ] Test verifies both base table state AND clock table entries
- [x] Reproducible command: `bash zig/harness/test-pk-update.sh`

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-pk-update.sh
```

## Progress Log
### 2025-12-18
- Task created from TASK-073 coverage analysis

## Completion Notes
### 2025-12-20
- Implemented `zig/harness/test-pk-update.sh` and wired it into `zig/harness/test-parity.sh`.
- Repro command: `bash zig/harness/test-pk-update.sh`
- Result: test currently FAILS against Zig extension because PK UPDATE does not emit tombstones (`cid='-1'`) / clock entries for the old PK.
- Follow-up filed: `.tasks/triage/TASK-103-zig-pk-update-must-emit-tombstone-and-insert.md`
