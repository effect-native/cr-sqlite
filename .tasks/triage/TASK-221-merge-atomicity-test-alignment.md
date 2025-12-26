# TASK-221 — Merge Atomicity Test Alignment (Unknown Column Policy)

## Goal
Reconcile `zig/harness/test-merge-atomicity.sh` expectations with the current “unknown columns are ignored” sync policy, and ensure CI gating reflects the intended contract.

## Status
- State: triage
- Priority: HIGH (blocks CI release-gate if required)
- Created: 2025-12-26
- Triggered by: running `bash zig/harness/test-merge-atomicity.sh` during “Update tasks”

## Context
We decided/implemented lenient schema mismatch behavior (unknown columns ignored) to support rolling upgrades.

`zig/harness/test-merge-atomicity.sh` currently injects an “error” by using `cid = 'NONEXISTENT_COLUMN'` in a multi-row `INSERT INTO crsql_changes ... VALUES (...), (...);`.

With unknown-column rows now ignored by policy, the statement can legitimately succeed while applying the valid subset. This makes Test 2 and Test 7 fail.

Observed current output:
- `bash zig/harness/test-merge-atomicity.sh`: **6 passed, 2 failed**
  - Fails: Test 2, Test 7

## Files to Modify
- `zig/harness/test-merge-atomicity.sh`
- `zig/harness/test-parity.sh` (only if needed)
- `.github/workflows/zig-tests.yaml` (if CI gating needs adjustment)

## Acceptance Criteria
1. [ ] Choose and document the intended contract:
   - (A) “Best-effort apply” within a statement when some rows are ignorable by policy, OR
   - (B) “Strict all-or-nothing” even for unknown columns
2. [ ] Update `zig/harness/test-merge-atomicity.sh` so its error injection remains a hard error under the chosen policy.
   - Examples of “hard error” injectors:
     - invalid table name
     - invalid pk encoding / malformed pk blob
     - invalid site_id length (if strict validation is enforced)
3. [ ] `bash zig/harness/test-merge-atomicity.sh` passes.
4. [ ] CI required jobs stay green (or `test-merge-atomicity.sh` is removed from required set until fixed, explicitly documented).

## Parent Docs / Cross-links
- Policy wish: `.wishes/blocked-on-tom/zig-merge-atomicity-vs-lenient-schema-mismatch.md`
- Lenient schema mismatch implementation: `.tasks/done/TASK-186-schema-mismatch-unknown-column-behavior.md`
- CI test grouping: `.tasks/done/TASK-214-ci-oracle-strategy.md`
- Release tracker: `.tasks/backlog/TASK-209-release-0.16.300-preview.md`

## Progress Log
- 2025-12-26: Confirmed test failures locally; filed as triage.

## Completion Notes
(Empty until done.)
