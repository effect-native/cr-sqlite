# TASK-107: Clarify sqlite-cr wrapper usage for Zig harness tests

## Status
- [ ] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Triggered by: `.tasks/done/TASK-098-zig-ondisk-db-tests.md`
- Repo guidance: `AGENTS.md` “Zig testing (quick rule)”

## Description
TASK-098 context says to use `nix run github:subtleGradient/sqlite-cr` instead of `sqlite3` when testing against CR-SQLite.

However, `AGENTS.md` also says:

- “Do not run the Zig extension inside a sqlite3 wrapper that preloads another cr-sqlite extension. Load the Zig extension explicitly into a clean sqlite process.”

This creates ambiguity for Zig harness tests:
- When validating *Zig extension behavior*, the wrapper may preload a different CR-SQLite extension (C/Rust), potentially invalidating results.
- When validating *baseline CR-SQLite* behavior, the wrapper is convenient.

We need a clear policy for harness scripts:
- Which tests must use clean `sqlite` + explicit `.load $EXT`
- Which tests can use the sqlite-cr wrapper
- How to ensure we never accidentally have two extensions loaded

## Files to Modify
- `AGENTS.md` (if policy needs codifying)
- `zig/harness/test-parity.sh` (potential helper function / enforcement)
- `zig/harness/test-*.sh` (only if adjustments are required)

## Acceptance Criteria
- [ ] Decision documented (where it belongs)
- [ ] Zig harness tests consistently follow the decision
- [ ] No Zig test loads a wrapper that preloads another CR-SQLite extension
- [ ] CI/local repro instructions updated accordingly

## Reproducible Command
```bash
cd /Users/tom/Developer/effect-native/cr-sqlite
bash zig/harness/test-parity.sh
```

## Progress Log
### 2025-12-20
- Drafted after noticing conflicting guidance between TASK-098 context and `AGENTS.md`

## Completion Notes
