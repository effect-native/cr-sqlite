# TASK-190 — Fuzz Invalidation Round 2: Stress the sync protocol

## Goal
Invalidate "Zig parity is complete" hypothesis via extended fuzzing with focus on sync edge cases.

## Status
- State: triage
- Priority: HIGH (hypothesis validation)
- Discovered: 2025-12-23 (Round 69 follow-up)

## Hypothesis to Invalidate
"Zig CR-SQLite is functionally identical to Rust/C CR-SQLite for all sync scenarios."

## Test Approach
Extend `test-fuzz-parity.sh` with:

1. **Higher iteration count** (1000+ instead of 100)
2. **More aggressive schema generation**:
   - Tables with 10+ columns
   - Deep compound PKs (3-4 columns)
   - Mixed type PKs (int + text + blob)
3. **Chaotic operation sequences**:
   - Rapid insert/delete/resurrect cycles
   - Concurrent column updates on same row
   - Interleaved multi-table operations
4. **Sync stress patterns**:
   - 3+ node sync topologies
   - Out-of-order change application
   - Partial sync followed by full sync
5. **Value edge cases**:
   - Very long strings (>64KB)
   - Binary data with all byte values
   - Unicode normalization forms

## Files to Modify
- `zig/harness/test-fuzz-parity.sh` (extend)
- Or create new `zig/harness/test-fuzz-stress.sh`

## Acceptance Criteria
1. Either find a divergence (invalidate hypothesis) OR
2. Complete 10,000 operations without divergence (increase confidence)

## Parent Docs / Cross-links
- Prior fuzz work: `.tasks/done/TASK-127-experimental-parity-invalidation.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.

## Completion Notes
(Empty until done.)
