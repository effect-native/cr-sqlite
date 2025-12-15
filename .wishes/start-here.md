# start-here

If you’re asking “what’s left?” start here:

- Canonical status + remaining gaps: `research/zig-cr/92-gap-backlog.md`
- Task queue (what to run next): `.tasks/{backlog,active,done}/`
- Zig implementation: `zig/`
- TS specs + packages:
  - Specs: `effect-native/.specs/`
  - Packages: `effect-native/packages-native/`

## Next parallel work (curated)

- Web phase 2 (TS, spec-gated):
  - `.tasks/backlog/TASK-031-web-service-worker-fallback.md`
  - `.tasks/backlog/TASK-032-web-reactive-subscriptions.md`
- Upstream feedback capture (blocked): `.tasks/backlog/TASK-037-zig-sqlite-upstream-feedback-blocked.md`

(For what just happened in the last delegate round, start at `.tasks/DELEGATE_WORK_HANDOFF.md` and then confirm against `effect-native/.specs/` and `effect-native/packages-native/`.)

## Rules of the game (thing-golf)

Prefer fewer, sharper “Things”:
- One task card owns one named delta.
- Each task card lists a tight `Files to Modify` set.
- Each task card links to its parent doc/spec and the parent links back.
