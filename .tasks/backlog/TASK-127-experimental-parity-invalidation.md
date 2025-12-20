# TASK-127: Experimentally invalidate "full parity" hypothesis

## Goal
The current hypothesis is that the Zig implementation has achieved full oracle parity with the Rust/C implementation (18/18 tests pass).
We need to **invalidate** this hypothesis experimentally by finding at least one divergence that is not yet covered by our test suite.

## Scope
- Create a new test harness `zig/harness/test-fuzz-parity.sh` (or similar).
- Implement a simple stochastic/fuzzing approach:
  - Generate random schemas (tables with random column types, PKs).
  - Generate random operations (INSERT, UPDATE, DELETE, transactions).
  - Run identical SQL against both Zig (loadable ext) and Rust/C (oracle via sqlite-cr wrapper).
  - Compare `crsql_changes`, `crsql_db_version`, `crsql_site_id`, and table contents.
- Run the fuzzer until a divergence is found.

## Files to Modify
- `zig/harness/test-fuzz-parity.sh` (new)
- `zig/harness/test-parity.sh` (optional, to include the new test)

## Acceptance Criteria
- [ ] A new test script `zig/harness/test-fuzz-parity.sh` exists.
- [ ] The script runs against both Zig and Rust/C oracle.
- [ ] The script identifies at least one divergence (a "counter-example" to the full parity hypothesis).
- [ ] The divergence is documented in the completion notes.

## Parent Docs
- `research/zig-cr/92-gap-backlog.md`
