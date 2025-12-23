# TASK-180 — Test site_id collision handling

## Goal
Document behavior when two databases have the same site_id.

## Status
- State: triage
- Priority: medium (edge case, security)

## Context
What happens if:
1. You copy a database file (both have same site_id)
2. Both copies make changes
3. You try to sync them

This could happen accidentally (backup restored) or maliciously.

## Files to Modify
- `zig/harness/test-site-id-collision.sh` (new)

## Acceptance Criteria
1. Create database with CRR, insert data
2. Copy database file (now two DBs with same site_id)
3. Make different changes in each copy
4. Attempt to sync between them
5. Document behavior:
   - Does it detect collision?
   - Does it error or corrupt?
   - What's the recommended recovery?
6. Zig and Rust/C oracle produce identical results

## Parent Docs / Cross-links
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-22: Created from gap analysis.

## Completion Notes
(Empty until done.)
