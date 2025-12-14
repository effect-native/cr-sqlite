# Wishes Inbox

This folder is for **Tom (Product Owner)** to asynchronously communicate wishes to AI agents.

## How to Use

1. **Drop a markdown file** in this folder with your wish
2. **Name it descriptively**: `priority-description.md` (e.g., `high-add-fuzzing-tests.md`)
3. **Agent will process** on next OODA loop iteration
4. **File moves to `.wishes/done/`** when processed

## File Format

```markdown
# [Title of Wish]

## Priority
high | medium | low

## Description
What you want to happen.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Notes (optional)
Any context, links, or constraints.
```

## Example

```markdown
# Add Performance Benchmarks

## Priority
medium

## Description
I want to see how the Zig implementation compares to the Rust/C implementation in terms of:
- Sync throughput (changes/second)
- Memory usage during large syncs
- Cold start time

## Acceptance Criteria
- [ ] Benchmark script exists at `zig/harness/bench-*.sh`
- [ ] Results documented in `research/zig-cr/`
- [ ] Can reproduce on CI

## Notes
Look at how hyperfine does benchmarking.
```

## Folder Structure

```
.wishes/
├── README.md           # This file
├── done/               # Processed wishes (moved here after completion)
├── blocked/            # Wishes that can't be done yet (with reason in file)
└── *.md                # Active wishes (inbox)
```

## For Agents

When processing wishes:
1. Read all `.md` files in `.wishes/` (not subdirs)
2. Sort by priority (high > medium > low)
3. Incorporate into current round planning
4. Move to `.wishes/done/` when complete (append completion notes)
5. Move to `.wishes/blocked/` if blocked (append reason)
6. Update `research/zig-cr/92-gap-backlog.md` with relevant items
