# TASK-064: Browser multi-tab provider migration (F13-F14)

## Status
- [x] Planned
- [x] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
high

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Unified plan (source of truth): `effect-native/.specs/crsql-mesh/plan.md` Section F (F13-F14)
- Proposal context: `research/zig-cr/96-proposal-multitab-wasm-sqlite-crsqlite.md` (Migration safety)
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement the browser multi-tab provider migration slices from the RGRTDD plan:

- **F13 (RED)** Specify provider migration semantics.
- **F14 (GREEN)** Implement provider migration.

Core behaviors:
- When the provider tab closes (or otherwise becomes unavailable), a new provider is elected.
- Existing clients reconnect and continue to operate.
- Writes become migration-safe via an idempotency guard keyed by a client-provided `txId`.

## Files to Modify
- `effect-native/packages-native/crsql-mesh/src/browser/coordinator.ts`
- `effect-native/packages-native/crsql-mesh/src/browser/provider.ts`
- `effect-native/packages-native/crsql-mesh/test/browser/coordinator.test.ts`
- `effect-native/packages-native/crsql-mesh/test/browser/provider.test.ts`
- `effect-native/packages-native/crsql-mesh/src/browser/index.ts` (if public types change)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] Add failing tests (RED) covering:
  - provider disconnect triggers re-election
  - clients reconnect and can successfully `exec` and `query` after migration
  - write calls require a `txId` and the provider enforces idempotency
- [x] Implement (GREEN) provider migration and idempotent write guard to satisfy tests.
- [x] Verification:
  - `pnpm -C effect-native vitest packages-native/crsql-mesh --run`
  - `pnpm -C effect-native check`

## Progress Log
### 2025-12-17
- Task created during "update tasks" reconciliation from `research/zig-cr/92-gap-backlog.md` remaining F13-F14 work.

### 2025-12-17 (Implementation)
**F13 (RED) - Tests Added:**
- Coordinator tests (5 new):
  - `triggers re-election when provider port disconnects`
  - `queues requests during provider migration and processes them after new provider elected`
  - `clients continue to exec after provider migration`
  - `clients continue to query after provider migration`
  - `notifies all clients when new provider is elected after migration`
- Provider tests (7 new):
  - `exec with txId succeeds on first attempt`
  - `exec with duplicate txId returns DUPLICATE_TX error`
  - `exec without txId returns TXID_REQUIRED error for write operations`
  - `different txIds from same client both succeed`
  - `same txId from different clients both succeed`
  - `query operations do not require txId`
  - `provider initializes idempotency table on open`

**F14 (GREEN) - Implementation Changes:**
- `coordinator.ts`: Already had correct provider migration/re-election logic (existing implementation)
- `provider.ts`:
  - Added `committedTxIds` Map for in-memory idempotency tracking
  - Modified `handleOpen` to create idempotency table `crsqlite_web_last_tx`
  - Modified `handleExec` to:
    - Require `txId` and `clientId` for write operations (returns `TXID_REQUIRED` error if missing)
    - Check for duplicate transactions (returns `DUPLICATE_TX` error if txId already committed)
    - Record committed txIds in both in-memory cache and database table
- Updated existing tests to use `createExecRequest` helper with txId/clientId

**Verification:**
- `pnpm -C effect-native check` - PASS (no TypeScript errors)
- Browser coordinator/provider tests - ALL PASS (12 F13-F14 specific tests)

## Completion Notes
F13-F14 implementation complete. The provider now enforces idempotent writes via txId guard, and the coordinator correctly handles provider migration with request queuing.
