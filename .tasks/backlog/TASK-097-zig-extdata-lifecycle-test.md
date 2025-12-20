# TASK-097: Zig ExtData lifecycle parity test

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
- C reference: `core/src/ext-data.test.c`
- Rust reference: `core/rs/integration_check/src/t/tableinfo.rs` (test_leak_condition)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
The C test suite (`ext-data.test.c`) tests ExtData lifecycle management:

1. `crsql_newExtData` - initial state (dbVersion=-1, pragmaSchemaVersion=-1)
2. `crsql_fetchPragmaSchemaVersion` - detects schema changes
3. `crsql_fetchPragmaDataVersion` - detects data changes from OTHER connections
4. `crsql_recreate_db_version_stmt` - rebuilds after schema change
5. `crsql_finalize` - cleans up statements
6. `crsql_freeExtData` - no leaks

The Zig implementation has internal ExtData management but no external tests verifying behavior matches C.

## Files to Modify
- `zig/harness/test-extdata.sh` (new file)
- `zig/harness/test-parity.sh` (add test runner call)

## Acceptance Criteria
- [ ] New test script `zig/harness/test-extdata.sh` exists
- [ ] Tests cover (via observable behavior, not internal state):
  - Schema changes trigger table info refresh
  - db_version correctly computed after schema changes
  - Multiple CRR tables tracked correctly
  - Dropping tables removes from tracked set
- [ ] Oracle parity: same operations produce same observable results in Zig and Rust/C
- [ ] Reproducible command: `bash zig/harness/test-extdata.sh`

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-extdata.sh
```

## Progress Log
### 2025-12-18
- Task created from TASK-073 coverage analysis

## Completion Notes
