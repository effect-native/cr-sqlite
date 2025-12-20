# TASK-124: Fix site_id preservation on cross-implementation DB open

## Status
- [ ] Planned

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Divergence documented in: `.tasks/done/TASK-074-cross-impl-compat-expanded.md`
- Test: `zig/harness/test-oracle-parity.sh` (Test 4b, 4c)
- Zig site_id handling: `zig/src/site_identity.zig`
- Zig init handling: `zig/src/ffi/init.zig`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
When Rust/C opens a database created by Zig, the site_id is not preserved correctly.

**Current behavior:**
- Zig creates DB with site_id: A6C2BD7D1EF644D4B72C5C97D0B50B78
- Rust/C opens same DB and reads site_id: (empty or different)

**Expected behavior:**
Both implementations should read the same site_id from an existing database.

**Investigation Notes:**
The issue might be due to missing version information in `crsql_master`. Rust/C implementation checks for a minimum version before accepting a database.

## Files to Modify
- `zig/src/ffi/init.zig` - initialization (version writing)
- `zig/src/site_identity.zig` - site_id storage/retrieval

## Acceptance Criteria
- [ ] When Rust/C opens a Zig-created DB, site_id is preserved
- [ ] When Zig opens a Rust/C-created DB, site_id is preserved
- [ ] `zig/harness/test-oracle-parity.sh` Test 4b and 4c pass
