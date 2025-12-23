# TASK-192 — Test Against Prior Database Files (Golden Snapshots)

## Goal
Test Zig extension against real database files created by prior Rust/C versions to invalidate "Zig parity is complete".

## Status
- State: triage
- Priority: HIGH (tests real-world compatibility)
- Discovered: 2025-12-23 (hypothesis invalidation request)

## Hypothesis to Invalidate
"Zig can correctly read/write databases created by Rust/C CR-SQLite."

The prior DB files exist at `py/correctness/prior-dbs/`.

## Test Approach
1. **Load prior DB with Zig** extension
2. **Verify can read**:
   - `crsql_db_version()` returns expected value
   - `crsql_site_id()` returns stored ID
   - `SELECT * FROM crsql_changes` returns expected rows
   - Clock tables have expected structure
3. **Verify can write**:
   - INSERT new row → clock entries created
   - Sync changes to another DB → converges correctly
4. **Compare against Rust/C** doing same operations

## Prior DB Files
- `py/correctness/prior-dbs/` — examine for available versions

## Files to Create
- `zig/harness/test-prior-db-compat.sh` (new)

## Acceptance Criteria
1. Load all prior DB files without error
2. Read operations produce identical results to Rust/C
3. Write operations produce compatible changes
4. Either find divergence OR confirm backward compat

## Parent Docs / Cross-links
- Prior DBs: `py/correctness/prior-dbs/`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.

## Completion Notes
(Empty until done.)
