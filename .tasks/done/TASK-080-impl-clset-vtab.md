# TASK-080: Implement (RGRTDD) — `clset` virtual table module in Zig

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [x] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Spec task: `.tasks/backlog/TASK-079-spec-clset-vtab.md`
- Rust reference: `core/rs/core/src/create_cl_set_vtab.rs`
- Registration point: `zig/src/ffi/init.zig`
- Zig CRR creation: `zig/src/as_crr.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Implement the `clset` module in Zig so that tests from TASK-079 pass.

Important notes from Rust behavior:
- Virtual table name must end with `_schema`.
- It creates a base storage table and upgrades it to a CRR.
- It declares a schema vtab interface with hidden columns.

## Files to Modify
- `zig/src/clset_vtab.zig` (new)
- `zig/src/ffi/init.zig`
- `zig/src/as_crr.zig` (only if needed)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [x] `zig/harness/test-clset-vtab.sh` passes.
- [x] No regression in `make -C zig test-parity`.

## Progress Log
### 2025-12-18
- Task created from Rust↔Zig gap analysis.

### 2025-12-20
- Implemented `clset_vtab.zig` with full virtual table module
- Added `createCrrInternal` function to `as_crr.zig` for savepoint-free CRR creation
- Registered clset module in `init.zig`
- All 10 tests in `test-clset-vtab.sh` pass
- No regressions in test-parity (rows_impacted, compound PK, core functions, filters, rowid-slab, alter, noops, fract tests all pass)

## Completion Notes
### Summary
Successfully implemented the `clset` virtual table module in Zig, which allows creating CRR tables via:
```sql
CREATE VIRTUAL TABLE foo_schema USING clset (a PRIMARY KEY NOT NULL, b);
```

### Key Implementation Details
1. **clset_vtab.zig** (new file): Implements the virtual table module with:
   - `xCreate`: Creates physical base table, validates _schema suffix and PRIMARY KEY requirement, converts to CRR
   - `xConnect`: Reconnects to existing clset vtab
   - `xDestroy`: Cleans up base table and CRR infrastructure
   - Minimal cursor implementation (schema-only vtab has no rows)

2. **as_crr.zig** modifications:
   - Added `createCrrInternal()` public function for savepoint-free CRR creation
   - Added `backfillExistingRowsNoTx()` for backfill without transaction wrapper
   - Critical: Savepoints cannot be used during xCreate (per Rust implementation comment)

3. **init.zig**: Added registration of clset module

### Test Results
```
clset Virtual Table Tests Summary: 10 passed, 0 failed, 0 skipped
All clset tests passed!
```

Tests verify:
1. Basic CREATE VIRTUAL TABLE succeeds
2. _schema suffix requirement enforced
3. Physical base table created
4. Clock and PKs tables created
5. CRDT triggers installed (4 triggers)
6. INSERT creates change records
7. DROP TABLE cleans up all related tables
8. PRIMARY KEY requirement enforced
9. CREATE IF NOT EXISTS is idempotent
