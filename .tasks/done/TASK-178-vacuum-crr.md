# TASK-178 — Test VACUUM on database with CRR tables

## Goal
Verify VACUUM doesn't corrupt CRR metadata.

## Status
- State: done
- Priority: low (maintenance operation)

## Context
VACUUM rebuilds the entire database file. Questions:
1. Are clock tables preserved correctly?
2. Are internal rowid mappings preserved?
3. Is crsql_master preserved?
4. Can you sync after VACUUM?

## Files to Modify
- `zig/harness/test-vacuum-crr.sh` (new)

## Acceptance Criteria
1. Create CRR table with data
2. Generate some clock entries
3. Run VACUUM
4. Verify: data intact
5. Verify: clock tables intact
6. Verify: can still INSERT/UPDATE/DELETE
7. Verify: can still sync via crsql_changes
8. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.
- 2025-12-23: Implemented test suite, all tests pass.

## Completion Notes
- **Date**: 2025-12-23
- **Test file**: `zig/harness/test-vacuum-crr.sh`
- **Results**: 17 passed, 0 failed, 0 skipped, 0 divergences

### Tests implemented:
1. **Basic VACUUM preserves data and clock entries** - PASS
2. **VACUUM preserves CRR metadata tables** - PASS (crsql_master, clock tables, crsql_site_id)
3. **VACUUM preserves site_id** - PASS
4. **VACUUM preserves db_version** - PASS
5. **INSERT/UPDATE/DELETE work after VACUUM** - PASS
6. **crsql_changes works after VACUUM (can sync)** - PASS
7. **Sync round-trip after VACUUM (A->B sync)** - PASS
8. **VACUUM INTO (copy to new file) preserves CRR state** - PASS
9. **Zig vs Rust/C parity on VACUUM behavior** - PASS

### Key findings:
- VACUUM correctly preserves all CRR metadata (clock tables, site_id, db_version)
- CRUD operations continue to work after VACUUM
- Sync operations (crsql_changes read/write) work correctly post-VACUUM
- VACUUM INTO creates a valid copy with all CRR state intact
- Zig and Rust/C implementations behave identically

### Note on crsql_master:
The `crsql_master` table stores key-value pairs (primarily `crsqlite_version`), not table registrations. CRR table registration is tracked via the existence of `<table>__crsql_clock` shadow tables.
