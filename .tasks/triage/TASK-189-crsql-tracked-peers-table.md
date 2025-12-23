# TASK-189 — Create crsql_tracked_peers table

## Goal
Create the crsql_tracked_peers table that Rust/C creates on initialization.

## Status
- State: triage
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
- `zig/src/ffi/init.zig` — add table creation in `initModule()`
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

## Completion Notes
(Empty until done.)
