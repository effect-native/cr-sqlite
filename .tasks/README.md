# Subagent Task Cards (`.tasks/`)

## Contract

Every `.tasks/**/TASK-*.md` must include:
- `Files to Modify` (tight scope)
- `Acceptance Criteria` (testable)
- `Parent Docs / Cross-links` (bidirectional)
- `Progress Log` + `Completion Notes`

Rules:
- One task = one owner = one atomic commit.
- Parallel tasks must not overlap file edits.

## Workflow

- Orchestrator:
  - Create cards in `.tasks/backlog/`
  - Move to `.tasks/active/` when assigning
  - Move to `.tasks/done/` when complete
  - Keep `research/zig-cr/92-gap-backlog.md` in sync

- Subagent:
  - Only touch `Files to Modify`
  - Update the task card as you work
  - If blocked, write the reason + next step
  - Do not move task files (orchestrator does)
