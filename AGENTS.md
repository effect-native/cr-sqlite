# AGENTS.md

Short operating manual for AI agents working in this repo.

## Pointers

- Wishes inbox: `.wishes/`
- Task queue: `.tasks/{backlog,active,done}/`
- Zig status + gaps (canonical): `research/zig-cr/92-gap-backlog.md`
- Zig implementation: `zig/`
- TypeScript specs (source of truth): `effect-native/.specs/`
- TypeScript packages (current reality): `effect-native/packages-native/`
- Upstream reference context (read-only): `.refs/effect/`, `.refs/effect-smol/`
  - Effect SQL refs: `.refs/effect/packages/sql/`, `.refs/effect/packages/sql-sqlite-bun/`

## TypeScript Work Rule

- All TypeScript work happens in the `effect-native/` submodule.
- For any TS change:
  - Read and follow `effect-native/.specs/AGENTS.md`.
  - Treat `effect-native/.specs/*` as the single source of truth.

## Task Cards (contract)

Every `.tasks/**/TASK-*.md` must include:
- `Files to Modify` (tight scope)
- `Acceptance Criteria` (testable)
- `Parent Docs / Cross-links` (bidirectional links)
- `Progress Log` + `Completion Notes`

Rules:
- No overlapping file edits across concurrently assigned tasks.
- One task card = one owner = one atomic commit.
- Use `.tmp/` for temp files (never `/tmp/`).

## Wishes

Workflow:
1. List `.wishes/*.md` (not subdirs).
2. Pull constraints/requests into planning.
3. If satisfied, move to `.wishes/done/` and append: date, what changed, commit hash.
4. If blocked, move to `.wishes/blocked/` and append the reason.

## "Update tasks" (backlog refresh)

Meaning: reconcile intended docs/specs vs built reality, then refresh `.tasks/`.

Do this, in order:
1. Snapshot the inbox + queue:
   - `.wishes/*.md`
   - `.tasks/{active,backlog,done}/`
2. Reconcile implementation vs intent:
   - Zig: compare `zig/` to `research/zig-cr/*` (esp. `90-feature-matrix.md`, `93-phased-execution-proposal.md`).
   - TS: compare `effect-native/packages-native/` to `effect-native/.specs/`.
   - For Effect SQL integration, consult `.refs/effect/packages/sql/` and `.refs/effect/packages/sql-sqlite-bun/`.
3. Ensure every gap has exactly one owning task card:
   - Create/adjust `.tasks/backlog/TASK-*.md` as needed.
4. Make links impossible to miss:
   - `research/zig-cr/92-gap-backlog.md` unchecked items link to their task cards.
   - Task cards link back to their parent docs/specs.
5. Mark TS work correctly:
   - If TS-heavy work is not past the spec gates, mark it blocked and point at the owning `effect-native/.specs/*`.

Output:
- `research/zig-cr/92-gap-backlog.md` stays current.
- `.tasks/backlog/` is a curated, non-overlapping set of next assignments.

## "Delegate work" (parallel subagents)

Meaning: take a curated subset of `.tasks/backlog/` and run multiple subagents in parallel.

Procedure:
1. Read `research/zig-cr/92-gap-backlog.md` first (it is the task map).
2. Pick tasks with disjoint `Files to Modify`.
3. For each selected task:
   - Move `.tasks/backlog/TASK-*.md` → `.tasks/active/TASK-*.md`.
   - Launch one subagent with the task card as the entire prompt.
   - Instruct it to only touch listed files and to update the task card as it goes.
4. When complete:
   - Move `.tasks/active/` → `.tasks/done/`.
   - Ensure completion notes include date + commit hash.
   - Refresh `research/zig-cr/92-gap-backlog.md` links/status.

Note: `.tasks/active/` can be changing while you read it. Take a snapshot and proceed.

## Zig testing (quick rule)

Do not run the Zig extension inside a sqlite3 wrapper that preloads another cr-sqlite extension. Load the Zig extension explicitly into a clean sqlite process.
