# TASK-091: Oracle Parity — Fractional index algorithm

## Status
- [ ] Planned
- [ ] Assigned
- [x] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
(unassigned)

## Parent Docs / Cross-links
- Rust fract implementation: `core/rs/core/src/fractindex.rs`
- Zig fract implementation: `zig/src/fract.zig`
- Existing fract tests: `zig/harness/test-fract.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Description
Verify that `crsql_fract_key_between(a, b)` produces identical output in both Rust/C and Zig for the same inputs.

This is an **oracle test**: The fractional index algorithm must be deterministic and produce the same lexicographically-sortable string in both implementations.

## Files to Modify
- `zig/harness/test-fract-parity.sh` (new or extend `test-fract.sh`)
- `zig/harness/test-parity.sh` (wire into suite)
- `research/zig-cr/92-gap-backlog.md`

## Acceptance Criteria
- [ ] Test calls `crsql_fract_key_between(a, b)` with identical inputs on both implementations.
- [ ] Test cases include:
  - `(NULL, NULL)` — first key
  - `('a', NULL)` — key after 'a'
  - `(NULL, 'z')` — key before 'z'
  - `('a', 'b')` — key between 'a' and 'b'
  - `('aaa', 'aab')` — key between close values
  - `('', 'a')` — edge case with empty string
  - Long strings (100+ chars) to test truncation/overflow behavior
- [ ] Outputs are **byte-identical** (not just semantically equivalent).
- [ ] Test fails if any output differs.
- [ ] Results maintain lexicographic ordering: `a < result < b` when both are non-NULL.

## Progress Log
### 2025-12-18
- Task created from oracle-based parity test suite.

## Completion Notes
