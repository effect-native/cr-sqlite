# TASK-194 — Real-World Application Simulation Tests

## Goal
Simulate realistic application patterns to invalidate "Zig parity is complete".

## Status
- State: triage  
- Priority: HIGH (tests real usage, not contrived scenarios)
- Discovered: 2025-12-23 (hypothesis invalidation request)

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

## Completion Notes
(Empty until done.)
