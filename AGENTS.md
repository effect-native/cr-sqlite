# AGENTS.md

Short operating manual for AI agents working in this repo.

## Pointers

- Wishes inbox: `.wishes/`
- Task queue: `.tasks/{backlog,active,done}/`
- Gap backlog (canonical map: update→delegate): `research/zig-cr/92-gap-backlog.md`
- Delegate handoff log (canonical claims: delegate→update): `.tasks/DELEGATE_WORK_HANDOFF.md`
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

"Delegate work" and "Update tasks" are an adversarial collaboration loop:
- Delegate phase writes **claims + evidence** into `.tasks/DELEGATE_WORK_HANDOFF.md`.
- Update phase tries to **invalidate** those claims by reconciling specs vs implementation.
- Gap backlog (`research/zig-cr/92-gap-backlog.md`) is the opposite evergreen handoff (update→delegate).

Do this, in order:
0. Read the delegate evidence first:
   - `.tasks/DELEGATE_WORK_HANDOFF.md`
   - Treat it as *claims to falsify*.
   - Prefer using the captured test output + coverage notes to avoid rerunning expensive tests.
   - If evidence is missing (no commands, no output, no repro steps), assume the claim is unproven.
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

This workflow must produce an evergreen handoff for the adversarial "Update tasks" phase:
- **Gap backlog** (`research/zig-cr/92-gap-backlog.md`) is update→delegate.
- **Delegate handoff log** (`.tasks/DELEGATE_WORK_HANDOFF.md`) is delegate→update.

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
5. **Commit all changes before handoff** (mandatory):
   - Commit in `effect-native/` submodule first (if changes exist there).
   - Then commit in the root repo (including the submodule pointer update).
   - Use descriptive commit messages referencing the task card(s).
   - Record the commit hashes in the task cards' Completion Notes.
6. Write the round outcome to the evergreen handoff log:
   - Append a new "Round" section to `.tasks/DELEGATE_WORK_HANDOFF.md`.
   - Include (at minimum):
     - which task cards were executed
     - commit hashes produced (if any)
     - exact commands used to run tests / typecheck / lint
     - the captured outputs (paste) for those commands
     - coverage outputs/paths (if applicable)
     - steps to reproduce the results from a clean checkout
   - If no tests were run, explicitly say so (this is a red flag).

Note: `.tasks/active/` can be changing while you read it. Take a snapshot and proceed.

## Zig testing (quick rule)

Do not run the Zig extension inside a sqlite3 wrapper that preloads another cr-sqlite extension. Load the Zig extension explicitly into a clean sqlite process.
