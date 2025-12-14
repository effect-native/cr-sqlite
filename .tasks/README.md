# Subagent Task Cards

This folder contains task assignments for AI subagents. Each task is a markdown file that the assigned subagent updates as work progresses.

## Folder Structure

```
.tasks/
├── README.md                    # This file
├── active/                      # Currently assigned tasks
│   └── TASK-001-description.md  # Task being worked on
├── done/                        # Completed tasks
│   └── TASK-001-description.md  # Completed with notes
└── backlog/                     # Planned but not yet assigned
    └── TASK-002-description.md  # Ready for next round
```

## Task File Format

```markdown
# TASK-XXX: [Short Description]

## Status
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
high | medium | low

## Assigned To
[subagent type: general | explore | ...]

## Description
What needs to be done.

## Files to Modify
- `path/to/file1.zig`
- `path/to/file2.ts`

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Progress Log
### YYYY-MM-DD HH:MM
- [What was done]
- [What's next]

## Completion Notes
[Filled in when done: what was accomplished, commit hash, any follow-up needed]
```

## Workflow

### Orchestrator (Main Agent)
1. Creates task cards in `.tasks/backlog/`
2. Moves to `.tasks/active/` when assigning to subagent
3. Reviews completed tasks
4. Moves to `.tasks/done/` and updates gap-backlog

### Subagent
1. Reads assigned task from `.tasks/active/`
2. Updates status to "In Progress"
3. Adds progress log entries as work proceeds
4. Updates status to "Complete" with completion notes
5. Does NOT move the file (orchestrator does that)

## Rules
1. **One task per file** - keeps diffs clean
2. **Update frequently** - progress log should reflect current state
3. **Be specific** - acceptance criteria must be testable
4. **No stale tasks** - if blocked >1 round, document why
5. **Commit task updates** - task card changes are part of the commit
