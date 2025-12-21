# TASK-140: Add parallel test runner for faster CI

## Priority: P2 (SECONDARY)

## Summary

The full test suite in `zig/harness/` takes a long time to run sequentially. 
Implement a parallel test runner to speed up CI and local development feedback loops.

## Current State

- ~40 test scripts in `zig/harness/test-*.sh`
- Each test is independent (uses temp DBs, no shared state)
- Sequential run takes several minutes
- Each individual test takes 2-10 seconds

## Files to Modify

- `zig/harness/run-all-tests.sh` (new file)
- `zig/Makefile` (add `test-parallel` target)

## Acceptance Criteria

1. [x] Create `run-all-tests.sh` that runs tests in parallel
2. [x] Use GNU parallel or xargs -P for parallelism
3. [x] Collect and summarize results at end
4. [x] Exit non-zero if any test fails
5. [x] Support `--jobs N` or `PARALLEL_JOBS` env var
6. [x] Default to `nproc` or 4 concurrent jobs
7. [x] Show progress (e.g., "12/40 tests completed")
8. [x] Preserve individual test output for debugging failures

## Implementation Options

### Option A: GNU Parallel

```bash
#!/usr/bin/env bash
find . -name 'test-*.sh' -type f | \
  parallel --jobs ${PARALLEL_JOBS:-$(nproc)} \
           --bar \
           --results .tmp/test-results/{/} \
           bash {}
```

### Option B: xargs

```bash
#!/usr/bin/env bash
find . -name 'test-*.sh' -type f | \
  xargs -P ${PARALLEL_JOBS:-4} -I{} bash -c '
    echo "Running {}"
    bash {} > .tmp/test-output-$(basename {}).log 2>&1
    echo "Exit code: $?"
  '
```

### Option C: Makefile with dependencies

```makefile
TESTS := $(wildcard test-*.sh)
test-parallel: $(TESTS:.sh=.result)
%.result: %.sh
	@bash $< > .tmp/$@.log 2>&1 && touch $@ || (cat .tmp/$@.log; exit 1)
```

## Considerations

1. **Build contention**: Multiple tests may try to rebuild Zig extension concurrently
   - Solution: Add `zig build` as prerequisite before parallel tests
   
2. **Temp file collisions**: Tests create temp DBs in `.tmp/`
   - Current: Uses `mktemp` so no collision
   - Verify each test uses unique temp files

3. **Output interleaving**: Parallel output can be confusing
   - Solution: Capture per-test output, show only on failure

4. **Resource limits**: Too many concurrent SQLite processes
   - Solution: Default to 4, allow override

## Expected Speedup

With 40 tests at ~5 seconds each:
- Sequential: ~200 seconds (3+ minutes)
- Parallel (4 jobs): ~50 seconds
- Parallel (8 jobs): ~25 seconds

## Parent Docs / Cross-links

- Gap Analysis: `research/zig-cr/97-test-gap-analysis.md`
- Current runner: `zig/harness/test-parity.sh` (sequential)

## Progress Log

- 2024-12-20: Created task card
- 2024-12-20: Implemented parallel test runner

## Completion Notes

Completed on 2024-12-20.

### Implementation

Created `zig/harness/run-all-tests.sh` with:
- Parallel execution using xargs -P (portable, no GNU parallel dependency)
- `--fast` mode (default): excludes slow tests (fuzz, stress, large-data)
- `--all` mode: runs all tests including slow ones
- `--slow` mode: runs only slow tests
- `--jobs N` / `PARALLEL_JOBS` env var for parallelism control
- `--sequential` for debugging
- Progress output and summary with pass/fail/skip counts
- Individual test logs preserved in `.tmp/test-results/`

Added Makefile targets:
- `test-parity-parallel`: Fast tests only (default)
- `test-parity-all`: All tests including slow ones
- `test-slow`: Only slow tests

### Results

- **39 fast tests** complete in ~19s with 10 parallel jobs (vs ~200s+ sequential)
- **7x+ speedup** for regular CI runs
- Slow tests (fuzz, stress, large-data) excluded by default but available via `--all`
