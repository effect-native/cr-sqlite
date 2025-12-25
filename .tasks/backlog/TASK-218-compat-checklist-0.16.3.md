# TASK-218 — Backwards-Compat Checklist (Upstream 0.16.3)

## Goal
Define what “backwards compatible with upstream cr-sqlite v0.16.3” means for `0.16.300-preview`, and verify it.

## Status
- State: backlog
- Priority: HIGH
- Created: 2025-12-25

## Checklist Areas
- SQL function surface (presence + basic behavior)
- Table / vtab surface (`crsql_changes`, `crsql_master`, `crsql_site_id`, `crsql_tracked_peers` semantics)
- Wire format / sync invariants (cross-open, multinode, resurrection, sentinel, etc.)
- Browser bundle expectations (WASM availability, multitab components present)

## Files to Modify
- `research/zig-cr/01-extension-surface.md` (if used as the canonical surface list)
- `zig/harness/test-api-surface.sh` (or add a new checklist test)
- This task card

## Acceptance Criteria
1. [ ] Compatibility checklist is explicit and reviewable
2. [ ] Each checklist item has a verification command or test
3. [ ] Any intentional incompatibility is documented and explicitly accepted for preview

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-25: Created from release planning.

## Completion Notes
(Empty until done.)
