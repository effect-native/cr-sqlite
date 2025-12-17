# TASK-069: Wire scratchpads for realistic demos

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
low

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Wish: `.wishes/scratchpad.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md` (add a new section under Gaps)

## Description
Wire up the existing scratchpad projects so they are runnable and demonstrate realistic scenarios:

- `scratch/browser-scratchpad`: minimal bun+react app demonstrating browser multi-tab DB.
- `scratch/bun-scratchpad`: minimal bun script using bun sqlite.
- `scratch/effect-bun-scratchpad`: minimal Effect+SQL bun project using effect-native packages.

This task is likely to be blocked by TypeScript spec-gates for the Effect TS scratchpad; if so, split and mark blocked accordingly.

## Files to Modify
- `scratch/browser-scratchpad/*`
- `scratch/bun-scratchpad/*`
- `scratch/effect-bun-scratchpad/*` (if present; otherwise create)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Each scratchpad has a single documented command to run.
- [ ] Browser scratchpad demonstrates cross-tab read/write visibility.
- [ ] No TypeScript spec-gate violations (if blocked, document and split).

## Progress Log
### 2025-12-17
- Task created from `.wishes/scratchpad.md` during "update tasks".

## Completion Notes
[fill in when done]
