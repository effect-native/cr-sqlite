# TASK-072: Zig correctness — Make `crsql_internal_sync_bit` per-connection

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust integration test that implies behavior: `core/rs/integration_check/src/t/sync_bit_honored.rs`
- Zig implementation: `zig/src/sync_bit.zig`
- Zig trigger gating references:
  - `zig/src/as_crr.zig`
  - `zig/src/schema_alter.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Real systems will have multiple SQLite connections in-process (connection pools, background writers, migrations, etc.).

`crsql_internal_sync_bit()` is used to gate triggers during merges. If this bit is global (process-wide) instead of per-connection, then one connection performing a merge can accidentally suppress change-capture in another connection.

The current Zig implementation uses a global `sync_bit` variable, which is a high-risk correctness bug that existing tests do not explicitly invalidate.

This task:
1. Defines and tests the required per-connection behavior.
2. Refactors the Zig implementation so the sync-bit state is stored per SQLite connection (likely in extension data associated with `sqlite3*`).

## Files to Modify
- `zig/src/sync_bit.zig`
- `zig/src/ffi/init.zig` (if UDF needs per-conn context wiring)
- `zig/harness/test-sync-bit-isolation.sh` (new)
- `zig/src/**` (only if needed for ext-data plumbing)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] New test reproduces the multi-connection hazard:
  - Connection A sets merge sync-bit on
  - Connection B continues to capture local writes
- [ ] Test fails on current Zig implementation and passes after fix.
- [ ] `make -C zig test-parity` (and/or `make -C zig test-unit`) runs this test.

## Progress Log
### 2025-12-18
- Task created during "update tasks" to invalidate "zig is done".

## Completion Notes
