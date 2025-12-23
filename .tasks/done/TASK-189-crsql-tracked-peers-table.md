# TASK-189 — Create crsql_tracked_peers table

## Goal
Create the crsql_tracked_peers table that Rust/C creates on initialization.

## Status
- State: done
- Priority: high (sync infrastructure)
- Discovered: Round 64 update tasks

## Problem
Rust/C creates a `crsql_tracked_peers` table on init, Zig doesn't:
```sql
-- Rust/C oracle:
.tables
-- crsql_master  crsql_site_id  crsql_tracked_peers

-- Zig:
.tables
-- crsql_master  crsql_site_id
```

## Context
This table is used for tracking peer sync state. Schema from bootstrap.rs:
```sql
CREATE TABLE IF NOT EXISTS crsql_tracked_peers (
  "site_id" BLOB NOT NULL,
  "version" INTEGER NOT NULL,
  "seq" INTEGER DEFAULT 0,
  "tag" INTEGER,
  "event" INTEGER,
  PRIMARY KEY ("site_id", "tag", "event")
) STRICT;
```

Purpose:
- Track which version/seq has been synced to/from each peer
- Allows resumable sync (don't re-send already-synced changes)
- Used by sync clients to maintain sync cursors

## Files to Modify
- `zig/src/ffi/init.zig` — add table creation in `sqlite3_crsqlite_init()`
- `zig/harness/test-tracked-peers.sh` (new) — test the table

## Acceptance Criteria
1. Table `crsql_tracked_peers` exists after extension loads
2. Schema matches Rust/C oracle exactly
3. Table is STRICT
4. Primary key constraint works
5. Can INSERT/UPDATE/DELETE rows
6. Table survives db close/reopen

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Rust impl: `core/rs/core/src/bootstrap.rs:52`

## Progress Log
- 2025-12-22: Created from gap analysis.
- 2025-12-22: Implemented table creation in `zig/src/ffi/init.zig:220-242`.

## Completion Notes
- **Date**: 2025-12-22
- **Files Modified**:
  - `zig/src/ffi/init.zig` - Added CREATE TABLE for `crsql_tracked_peers` after `writeVersionToMaster()` call
  - `zig/harness/test-tracked-peers.sh` (new) - Test suite with 9 tests
- **All Acceptance Criteria Met**:
  1. Table exists after extension loads
  2. Schema matches Rust/C oracle exactly (verified with parity test)
  3. Table is STRICT (type enforcement test passes)
  4. Primary key constraint works (duplicate key rejected)
  5. INSERT/UPDATE/DELETE all work
  6. Table persists across close/reopen
- **Test Output**:
  ```
  PASSED:  9
  FAILED:  0
  ```
- **Oracle Parity**: Both Zig and Rust/C now create the same crsql_ tables:
  - crsql_master
  - crsql_site_id
  - crsql_tracked_peers
