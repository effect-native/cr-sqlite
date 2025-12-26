# TASK-222 — Investigate Browser Test Failure (transient)

## Goal
Investigate and fix the browser test failure observed during Round 79 delegation.

## Status
- State: triage
- Priority: HIGH (browser tests are release-gating)
- Created: 2025-12-26
- Triggered by: `zig/browser-test/test-results/.last-run.json` showing failure during Round 79

## Context
During the TASK-221 subagent run, a browser test failed:
- Test ID: `2279ab4a47bc4d429986-9b18d77856fcd287b4dd`
- Status: `failed`

The committed version of `.last-run.json` shows `"status": "passed"`, so this may be:
1. A transient failure (network, timing)
2. A regression introduced by test changes (unlikely - TASK-221 only touched `test-merge-atomicity.sh`)
3. A pre-existing flaky test

## Reproduction
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
cd zig/browser-test && pnpm test
```

## Files to Investigate
- `zig/browser-test/tests/crsql-wasm.spec.ts`
- `zig/browser-test/tests/multitab-basic.spec.ts`
- `zig/browser-test/playwright.config.ts`

## Acceptance Criteria
1. [ ] Identify which test failed
2. [ ] Reproduce the failure locally
3. [ ] Fix or mark as known-flaky
4. [ ] Browser tests pass consistently (3 consecutive runs)

## Parent Docs / Cross-links
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`
- Browser provider: `.tasks/done/TASK-213-browser-provider-loads-crsqlite-wasm.md`

## Progress Log
- 2025-12-26: Created from Round 79 observation; transient failure during subagent run.

## Completion Notes
(Empty until done.)
