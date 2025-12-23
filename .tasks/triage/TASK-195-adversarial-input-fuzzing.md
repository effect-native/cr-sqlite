# TASK-195 — Adversarial Input Fuzzing (Malformed crsql_changes)

## Goal
Feed malformed/adversarial inputs to crsql_changes to find divergent error handling.

## Status
- State: triage
- Priority: HIGH (security + robustness)
- Discovered: 2025-12-23 (hypothesis invalidation request)

## Hypothesis to Invalidate
"Zig and Rust/C handle all malformed inputs identically."

## Test Approach

### Malformed Inputs to Generate
1. **Invalid pk blobs**:
   - Truncated encoding
   - Wrong column count prefix
   - Invalid type tags
   - Zero-length
   - Extremely long

2. **Invalid column values**:
   - Wrong type for column
   - Oversized blobs
   - Invalid UTF-8 in text
   - NaN/Inf floats

3. **Invalid metadata**:
   - Negative col_version
   - Negative db_version  
   - Negative cl (causal length)
   - Invalid site_id (wrong length)
   - site_id = all zeros
   - site_id = all 0xFF

4. **Invalid cid (column identifier)**:
   - Non-existent column name
   - Empty string
   - Very long column name
   - Column name with special chars

5. **Invalid table names**:
   - Non-existent table
   - System table name
   - SQL injection attempts

6. **Sequence attacks**:
   - Same pk, different site_id, same col_version
   - Duplicate inserts
   - Out-of-sequence db_version

## Files to Create
- `zig/harness/test-adversarial-input.sh` (new)

## Acceptance Criteria
1. Both implementations handle malformed input gracefully (error, not crash)
2. Error messages/codes match OR divergence is documented
3. No data corruption from malformed input
4. Either find handling divergence OR confirm robustness parity

## Parent Docs / Cross-links
- Existing error handling: `test-error-handling.sh`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`

## Progress Log
- 2025-12-23: Created from hypothesis invalidation request.

## Completion Notes
(Empty until done.)
