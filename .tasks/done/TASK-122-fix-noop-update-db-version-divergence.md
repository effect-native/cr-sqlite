# TASK-122: Fix no-op UPDATE db_version divergence

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
- Divergence documented in: `.tasks/done/TASK-092-db-version-advancement-parity.md`
- Zig implementation: `zig/src/triggers.zig` (UPDATE trigger)
- Test: `zig/harness/test-db-version-parity.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
When a user performs an UPDATE that sets a column to its existing value (no-op UPDATE),
the Rust/C oracle advances db_version but Zig does not.

**Current behavior:**
- Rust/C: `UPDATE t SET col = 'same' WHERE col = 'same'` → db_version advances
- Zig: Same UPDATE → db_version does NOT advance

**Decision needed:** Is this a bug in Zig (should match Rust) or an intentional optimization in Zig?

If it's a bug, the UPDATE trigger in Zig needs to advance db_version even when the value doesn't change.
If it's intentional, the test should be updated to document this as acceptable divergence.

## Files to Modify
- `zig/src/triggers.zig` (if fixing to match oracle)
- `zig/harness/test-db-version-parity.sh` (if documenting as acceptable)

## Acceptance Criteria
- [x] Either:
  - A) Zig matches Rust/C behavior (db_version advances on no-op UPDATE) ✓
  - B) Divergence is documented as intentional with rationale
- [x] `zig/harness/test-db-version-parity.sh` passes (either via fix or test update)

## Progress Log
### 2025-12-20
- Task created from documented divergence in TASK-092
- Need to investigate: Is Zig's behavior (not advancing) more correct semantically?
  - Pro Zig: No actual data changed, so no version bump makes sense
  - Pro Rust: Sync clients may expect version bump to know "something was attempted"

### 2025-12-20 (completion)
**Investigation findings:**
1. Rust/C UPDATE trigger fires unconditionally with `WHEN crsql_internal_sync_bit() = 0` and calls `crsql_after_update()` function
2. Zig UPDATE trigger had `WHEN` clause that included `OLD.col IS NOT NEW.col` checks, preventing it from firing on no-op updates
3. The Rust/C oracle DOES advance db_version on no-op updates (1 → 2) even though no clock entries are modified
4. This is intentional oracle behavior - the trigger fires and touches `crsql_next_db_version()` regardless of value changes

**Decision:** Fix Zig to match Rust/C oracle behavior (Option A)

**Changes made:**
1. `zig/src/as_crr.zig`: Modified `createUpdateTrigger()` to:
   - Remove non-PK column change checks from WHEN clause
   - Keep only PK unchanged check (to avoid conflict with pk_utrig)
   - Add unconditional `SELECT crsql_next_db_version()` at start of trigger body
   - Keep per-column `WHERE OLD.col IS NOT NEW.col` to avoid writing unchanged clock entries

2. `zig/src/schema_alter.zig`: Applied same fix to `createUpdateTrigger()` for consistency after schema changes

3. `zig/harness/test-db-version-parity.sh`: Updated Test 6 comments to reflect actual oracle behavior (db_version DOES advance on no-op UPDATE)

**Test output:**
```
All db_version parity tests PASSED
PASSED: 14
FAILED: 0
DIVERGENCES: 0
```

## Completion Notes
- Fixed by making Zig UPDATE trigger fire on ALL updates (matching Rust/C oracle)
- Clock entries remain unchanged for no-op updates (only db_version advances)
- Both `as_crr.zig` and `schema_alter.zig` trigger creation updated for consistency

