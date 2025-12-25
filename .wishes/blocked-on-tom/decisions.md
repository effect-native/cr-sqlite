Blocked On Tom (Decisions Needed Now)

1. Public release readiness (.wishes/blocked-on-tom/release-readiness-decision.md)
- This blocks: .tasks/backlog/TASK-207-reenable-ci-for-release.md
- Decisions:
  - Release scope: Native + WASM + Browser
  - Versioning: 0.16.300-preview
    because the original cr-sqlite was abandoned at v0.16.3; and our goal with this first version is to be fully backwards compatible with it. But a preview tag since I can't guarantee that it's super legit until I personally verify it in a bunch of real products and stuff.

  - Distribution:
    - OIDC npm via the effect-native repo
    - native via github releases
    - nix via github tags
  
  - Docs requirement for release: no docs needed for the first preview release

2. Implementation-agnostic spec suite (.wishes/blocked-on-tom/implementation-agnostic-spec-suite.md)
- Decisions: we shall think about this after our first Public release v0.16.300-preview

3. Effect Bun scratchpad (TS spec-gated) (.wishes/blocked-on-tom/effect-bun-scratchpad.md)
- Decisions:
  - Location:
    - A) effect-native/scratch/effect-bun-scratchpad/
    - B) a package under effect-native/packages-native/
  - Spec-first?
    - A) Yes: add minimal spec under effect-native/.specs/ first
    - B) No: prototype directly (but this violates current “spec gate” norm—confirm override)
  - Must-use deps?
    - A) @effect/platform(-bun), @effect/sql, @effect/sql-sqlite-bun only
    - B) also language-service/vitest/eslint-plugin set

4. Scope upstream feedback capture (.wishes/blocked-on-tom/tom-scope-upstream-feedback.md)
- Note: prior tasks indicate you previously said “skip all zig-sqlite stuff”; this card still exists, so confirm the current stance.
- Decisions (if not skipping):
  - How many idea cards: 3 / 5 / 10
  - Allowed to reference .refs/ directly: yes/no
  - Allowed to patch .refs/ locally for experiments (no upstream PR): yes/no
  - Any must-include topics?

5. Browser runtime spec naming / package boundary (.wishes/blocked-on-tom/tom-browser-spec-naming.md)
- Note: .tasks/done/TASK-056-tom-browser-spec-naming.md says you already picked crsqlite-web-multitab and wanted to defer package boundaries until blocked. If that’s still true, this blocker can be considered resolved.
- Decision: confirm one
  - A) Confirm: spec dir is crsqlite-web-multitab and boundaries deferred (proceed without final npm package split)
  - B) Update: provide new spec dir + package name(s) + 1-sentence boundary each


Reply format (so I can act immediately)
- Release: scope = ?, versioning = ?, distribution = ?, docs = ?
- Spec suite: implementations = ?, asserts = ?
- Scratchpad: location = ?, spec-first = ?, deps = ?
- Upstream feedback: skip = yes/no; if no → count=?, refs=?, patch=?, topics=?
- Browser: confirm A or pick B (and details)
