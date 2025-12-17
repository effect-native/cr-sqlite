# TASK-037: zig-sqlite Upstream Feedback Capture (blocked)

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked
- [x] Complete (cancelled per Tom)

## Priority
low

## Assigned To
subagent (explore)

## Parent Docs / Cross-links
- Wish: `.wishes/gather-upstream-feedback.md`
- Zig reference analysis: `research/zig-cr/20-zig-sqlite-capabilities.md`
- Candidate touchpoints in our code: `zig/src/sqlite/value.zig`, `zig/src/sqlite/vtab.zig`

## Description
Capture specific, actionable upstream feedback ideas for `.refs/zig-sqlite`.

Per `.wishes/gather-upstream-feedback.md`, these ideas should be recorded as individual markdown cards under `.wishes/blocked-on-tom/` so Tom can later choose what (if anything) to contribute upstream.

This task is blocked because it requires Tom to confirm the intended scope (how many cards, and whether we’re allowed to touch `.refs/` at all).

Decision-capture task:
- `.tasks/backlog/TASK-055-tom-scope-upstream-feedback.md`

## Files to Modify
- `.wishes/blocked-on-tom/*.md` (new idea cards)
- `research/zig-cr/92-gap-backlog.md` (optional link section)

## Acceptance Criteria
- [ ] At least 5 concrete upstream idea cards created.
- [ ] Each card links to the exact file/line area in our repo motivating it.
- [ ] Each card includes a "why it matters" section.

## Progress Log
### 2025-12-14
- Task card created; blocked pending Tom direction

## Completion Notes
**2025-12-17**: Cancelled per Tom — "skip all zig-sqlite stuff"
