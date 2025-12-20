# TASK-103: Reconcile duplicate TASK-099 card in triage

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Trigger: duplicate file name discovered while completing `.tasks/done/TASK-099-zig-multiconn-test.md`
- Existing done card: `.tasks/done/TASK-099-zig-multiconn-test.md`
- Duplicate triage card: `.tasks/triage/TASK-099-zig-multiconn-test.md`
- Task card contract: `AGENTS.md`

## Description
There are two different task cards with the same task number/name:
- `.tasks/done/TASK-099-zig-multiconn-test.md` (completed, contains real completion notes)
- `.tasks/triage/TASK-099-zig-multiconn-test.md` ("missing task card" placeholder)

This is confusing for the task queue and any automation/grep-based workflows.

## Files to Modify
- `.tasks/triage/TASK-099-zig-multiconn-test.md` (mark obsolete or remove)
- (optional) `research/zig-cr/92-gap-backlog.md` (ensure TASK-099 links to the done card, not triage)

## Acceptance Criteria
- [ ] Exactly one canonical TASK-099 card exists (either in done or backlog/active)
- [ ] The duplicate triage placeholder is moved to `.tasks/done/` as obsolete (with explanation) or deleted
- [ ] Gap backlog references (if any) resolve unambiguously to the canonical card

## Progress Log
### 2025-12-20
- Created as a triage follow-up after observing duplicate TASK-099 task cards.

## Completion Notes
