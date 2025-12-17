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
- `scratch/bun-scratchpad`: minimal bun script using `bun:sqlite`.

The original wish also asked for an Effect+SQL Bun scratchpad. That is **TypeScript-heavy** and (per repo rules) must live in the `effect-native/` submodule and be spec-gated.

Track that separately as a Tom-blocked wish:
- `.wishes/blocked-on-tom/effect-bun-scratchpad.md`

## Files to Modify
- `scratch/browser-scratchpad/*`
- `scratch/bun-scratchpad/*`
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Each scratchpad has a single documented command to run.
- [ ] Browser scratchpad demonstrates cross-tab read/write visibility.
- [ ] Bun scratchpad demonstrates CR-SQLite usage with `bun:sqlite`.
- [ ] No TypeScript spec-gate violations (Effect scratchpad tracked separately as blocked).

## Progress Log
### 2025-12-17
- Task created from `.wishes/scratchpad.md` during "update tasks".

## Completion Notes
[fill in when done]
