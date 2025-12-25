# TASK-194 — Real-World Application Simulation Tests

## Goal
Simulate realistic application patterns to invalidate "Zig parity is complete".

## Status
- State: **DONE**
- Priority: HIGH (tests real usage, not contrived scenarios)
- Discovered: 2025-12-23 (hypothesis invalidation request)
- Completed: 2025-12-25

## Hypothesis to Invalidate
"Zig behaves correctly under realistic application workloads."

## Test Scenarios

### 1. Todo App Sync
- Create tasks with nested subtasks
- Mark complete/incomplete in different order on two devices
- Sync and verify convergence

### 2. Chat/Notes App
- Long-running conversation with edits
- Offline edits on multiple devices
- Reconnect and merge

### 3. Shopping Cart
- Add/remove items rapidly
- Update quantities concurrently
- Apply discount codes (triggers)

### 4. Collaborative Document
- Multiple users editing same "document" (row with text blob)
- Concurrent field updates
- History/versioning queries

### 5. Inventory Management
- Stock count adjustments
- Transfer between locations
- Audit trail preservation

## Test Approach
1. **Script realistic operation sequences**
2. **Simulate multi-device with separate DBs**
3. **Sync via crsql_changes protocol**
4. **Verify final state matches on all "devices"**
5. **Compare Zig vs Rust/C behavior**

## Files to Create
- `zig/harness/test-app-todo.sh` (new)
- `zig/harness/test-app-chat.sh` (new)
- `zig/harness/test-app-inventory.sh` (new)

## Acceptance Criteria
1. Each app simulation runs without error
2. All "devices" converge to same state
3. Zig and Rust/C produce identical final state
4. Either find divergence OR confirm real-world readiness

## Parent Docs / Cross-links
- Existing realistic tests: `test-realistic-sync.sh`, `test-realistic-offline.sh`, `test-realistic-collab.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.
- 2025-12-25: Created 3 app simulation test scripts.
- 2025-12-25: Fixed schema issue (NOT NULL columns need DEFAULT values for cr-sqlite).
- 2025-12-25: Discovered **critical Zig bug**: INSERT INTO crsql_changes fails with "SQL logic error".

## Completion Notes

### Scripts Created
1. `zig/harness/test-app-todo.sh` - Todo app with subtasks and concurrent edits
2. `zig/harness/test-app-chat.sh` - Chat app with offline edits and message conflicts
3. `zig/harness/test-app-inventory.sh` - Inventory system with multi-location sync

### Test Results

#### Rust/C Oracle: ALL PASS
- Todo app: 2/2 tests pass
- Chat app: 4/4 tests pass
- Inventory: 4/4 tests pass

#### Zig Implementation: CRITICAL FAILURE
- **Root Cause**: `INSERT INTO crsql_changes` fails with "SQL logic error"
- Debug output shows: `insertOrUpdateColumn failed`
- This breaks ALL sync operations (changes from one device cannot be applied to another)

### Specific Divergence Found

```
=== Rust/C INSERT INTO crsql_changes ===
Todo count: 1  (row created successfully)

=== Zig INSERT INTO crsql_changes ===
debug(changes_vtab): changesUpdate INSERT: table=todos, cid=title...
debug(changes_vtab): changesUpdate: no local row, inserting new row
debug(changes_vtab): changesUpdate: insertOrUpdateColumn failed
Error: stepping, SQL logic error
Todo count: 0  (FAILED - no row created)
```

### Hypothesis Result

**INVALIDATED**: "Zig behaves correctly under realistic application workloads."

The Zig implementation has a fundamental bug that prevents cross-device sync from working. When Device A creates data and sends changes to Device B, Device B cannot apply them via `INSERT INTO crsql_changes`.

### Recommended Follow-up

Create a new task to fix the `insertOrUpdateColumn` function in the Zig changes vtab implementation. The bug appears to be in `zig/src/changes-vtab.zig` in the `changesUpdate` path when handling new rows.
