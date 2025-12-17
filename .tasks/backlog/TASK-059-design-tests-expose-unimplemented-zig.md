# TASK-059: Design and Add Tests to Expose Unimplemented Zig Functionality

## Status
- [x] Planned
- [ ] Assigned
- [ ] In Progress
- [ ] Blocked (reason: ...)
- [ ] Complete

## Priority
medium

## Assigned To
subagent (general)

## Parent Docs / Cross-links
- Test oracle design: `research/zig-cr/10-test-oracle.md`
- Feature matrix: `research/zig-cr/90-feature-matrix.md`
- Gap backlog: `research/zig-cr/92-gap-backlog.md`
- Existing test harnesses: `zig/harness/`
- C oracle tests: `core/c/`

## Description
Design and implement additional tests to systematically expose any gaps in the Zig implementation that aren't caught by existing test suites.

Focus areas:
1. **Edge cases and error conditions**: Test boundary conditions, error handling, and failure modes
2. **Multi-table scenarios**: Complex interactions between multiple CRR tables
3. **Merge conflict resolution**: All tie-breaker paths (cl/col_version/value/site_id)
4. **Clock semantics**: dbVersion/pendingDbVersion/seq invariants across transactions
5. **Serialization formats**: PK blob packing/unpacking edge cases
6. **Virtual table operations**: xUpdate paths, transaction boundaries, best-index scenarios
7. **Hook chaining**: Commit/rollback hook interactions with other extensions
8. **Schema evolution**: as_crr/as_table with different table configurations
9. **Performance characteristics**: Large UNION query scaling, statement cache effectiveness

Each test should:
- Be deterministic and reproducible
- Have clear pass/fail criteria
- Document what functionality it's validating
- Run quickly (avoid long-running stress tests in CI)

## Files to Modify
- `zig/harness/` (new test scripts or extensions to existing ones)
- `zig/src/` (add unit tests in relevant modules)
- `research/zig-cr/92-gap-backlog.md` (document test coverage improvements)

## Acceptance Criteria
- [ ] Identify at least 5-10 additional test scenarios not covered by existing tests
- [ ] Document the test design in the `Progress Log` with rationale
- [ ] Implement the new tests
- [ ] Tests successfully expose at least one previously undetected gap (if any exist)
- [ ] All new tests pass (or are marked as expected failures with task cards created for fixes)
- [ ] Test documentation explains what each test validates and why it's important
- [ ] Tests are integrated into existing test harness (make test-* targets)

## Progress Log
### 2025-12-17
- Task created to improve test coverage and expose implementation gaps
- Current test status: 154/154 MVP tests passing per gap backlog
- C oracle harness: 19/20 tests pass (fract_as_ordered stub causes 1 failure)
- Need to design tests that go beyond existing coverage

## Completion Notes
[fill in when done]
