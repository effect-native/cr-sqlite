#!/usr/bin/env bash
# Parallel Test Runner for Zig CR-SQLite Harness
#
# Runs all test-*.sh scripts in parallel for faster CI feedback.
# Each test is independent (uses temp DBs via mktemp, no shared state).
#
# Usage:
#   ./run-all-tests.sh              # Run fast tests only (excludes slow tests)
#   ./run-all-tests.sh --all        # Run all tests including slow ones
#   ./run-all-tests.sh --slow       # Run only slow tests (fuzz, stress, large-data)
#   ./run-all-tests.sh --jobs 8     # Run with 8 parallel jobs
#   PARALLEL_JOBS=8 ./run-all-tests.sh  # Same via env var
#   ./run-all-tests.sh --sequential # Run tests sequentially (debugging)
#
# Slow tests (excluded by default):
#   - test-fuzz-parity.sh      (~140s) - Stochastic fuzz testing
#   - test-merge-stress.sh     (~60s)  - Stress testing merge operations  
#   - test-large-data.sh       (~30s)  - Large dataset testing
#
# Output:
#   - Shows progress as tests complete
#   - Preserves individual test output in .tmp/test-results/
#   - Summarizes pass/fail at end
#   - Exits non-zero if any test fails

set -euo pipefail

# Slow tests to exclude by default (these take >20s each)
SLOW_TESTS=(
    "test-fuzz-parity.sh"
    "test-merge-stress.sh"
    "test-large-data.sh"
)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/.tmp/test-results"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Default parallelism: nproc on Linux, sysctl on macOS, fallback to 4
get_nproc() {
    if command -v nproc &>/dev/null; then
        nproc
    elif [[ "$(uname)" == "Darwin" ]]; then
        sysctl -n hw.ncpu
    else
        echo 4
    fi
}

# Parse arguments
JOBS="${PARALLEL_JOBS:-$(get_nproc)}"
SEQUENTIAL=false
VERBOSE=false
RUN_MODE="fast"  # fast (default), all, slow

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs|-j)
            JOBS="$2"
            shift 2
            ;;
        --sequential|-s)
            SEQUENTIAL=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --all|-a)
            RUN_MODE="all"
            shift
            ;;
        --slow)
            RUN_MODE="slow"
            shift
            ;;
        --fast)
            RUN_MODE="fast"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --fast            Run fast tests only (default, excludes slow tests)"
            echo "  --all, -a         Run all tests including slow ones"
            echo "  --slow            Run only slow tests (fuzz, stress, large-data)"
            echo "  --jobs N, -j N    Number of parallel jobs (default: nproc or 4)"
            echo "  --sequential, -s  Run tests sequentially"
            echo "  --verbose, -v     Show test output as it runs"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Environment:"
            echo "  PARALLEL_JOBS     Alternative way to set job count"
            echo ""
            echo "Slow tests (excluded by --fast):"
            for t in "${SLOW_TESTS[@]}"; do
                echo "  - $t"
            done
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Zig CR-SQLite Parallel Test Runner${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo ""

# Build the extension first (avoids build contention during parallel tests)
echo -e "${CYAN}Building Zig extension...${RESET}"
cd "$ZIG_DIR"
if ! nix run nixpkgs#zig -- build 2>&1; then
    echo -e "${RED}FAIL: Zig build failed${RESET}"
    exit 1
fi

# Determine extension path
if [[ "$(uname)" == "Darwin" ]]; then
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$EXT" ]]; then
    echo -e "${RED}FAIL: Extension not found at $EXT${RESET}"
    exit 1
fi

echo -e "${GREEN}Extension built: $EXT${RESET}"
echo ""

# Clean and create results directory
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

# Helper to check if a test is slow
is_slow_test() {
    local test_name="$1"
    for slow in "${SLOW_TESTS[@]}"; do
        if [[ "$test_name" == "./$slow" || "$test_name" == "$slow" ]]; then
            return 0
        fi
    done
    return 1
}

# Find test scripts based on run mode
cd "$SCRIPT_DIR"
ALL_TEST_SCRIPTS=($(find . -maxdepth 1 -name 'test-*.sh' -type f | sort))
TEST_SCRIPTS=()

for script in "${ALL_TEST_SCRIPTS[@]}"; do
    case "$RUN_MODE" in
        fast)
            if ! is_slow_test "$script"; then
                TEST_SCRIPTS+=("$script")
            fi
            ;;
        slow)
            if is_slow_test "$script"; then
                TEST_SCRIPTS+=("$script")
            fi
            ;;
        all)
            TEST_SCRIPTS+=("$script")
            ;;
    esac
done

TOTAL_TESTS=${#TEST_SCRIPTS[@]}

if [[ $TOTAL_TESTS -eq 0 ]]; then
    echo -e "${YELLOW}No test scripts found${RESET}"
    exit 0
fi

echo -e "${BOLD}Found $TOTAL_TESTS test scripts${RESET} (mode: $RUN_MODE)"
if [[ "$RUN_MODE" == "fast" ]]; then
    echo -e "${YELLOW}Excluding ${#SLOW_TESTS[@]} slow tests. Use --all to include them.${RESET}"
fi
if $SEQUENTIAL; then
    echo -e "Running ${BOLD}sequentially${RESET}"
else
    echo -e "Running with ${BOLD}$JOBS parallel jobs${RESET}"
fi
echo ""

# Export extension path for tests
export ZIG_EXT_PATH="$EXT"
export CRSQL_EXT="$EXT"

# Function to run a single test and record results
run_single_test() {
    local test_script="$1"
    local test_name="${test_script#./}"
    local test_basename="${test_name%.sh}"
    local log_file="$RESULTS_DIR/${test_basename}.log"
    local start_time=$(date +%s)
    
    # Run the test
    local exit_code=0
    if bash "$test_script" > "$log_file" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Write result to a status file (exit code + duration)
    echo "${exit_code}:${duration}" > "$RESULTS_DIR/${test_basename}.status"
    
    # Print result (simple output, no progress counter to avoid race)
    local status=""
    local status_color=""
    if [[ $exit_code -eq 0 ]]; then
        status="PASS"
        status_color="$GREEN"
    elif [[ $exit_code -eq 2 ]]; then
        status="SKIP"
        status_color="$YELLOW"
    else
        status="FAIL"
        status_color="$RED"
    fi
    
    printf "${status_color}%-6s${RESET} %-45s (%ds)\n" "$status" "$test_name" "$duration"
    
    # Show output on failure (verbose mode or actual failures)
    if [[ $exit_code -ne 0 && $exit_code -ne 2 ]]; then
        if [[ -s "$log_file" ]]; then
            echo "  Output (first 20 lines):"
            sed 's/^/    /' "$log_file" | head -20
            local lines=$(wc -l < "$log_file")
            if [[ $lines -gt 20 ]]; then
                echo "    ... ($((lines - 20)) more lines in $log_file)"
            fi
        fi
    fi
}

export -f run_single_test
export RESULTS_DIR VERBOSE
export RED GREEN YELLOW CYAN BOLD RESET

# Run tests
START_TIME=$(date +%s)

if $SEQUENTIAL; then
    for test_script in "${TEST_SCRIPTS[@]}"; do
        run_single_test "$test_script"
    done
else
    # Use xargs for parallelism (more portable than GNU parallel)
    printf '%s\n' "${TEST_SCRIPTS[@]}" | \
        xargs -P "$JOBS" -I{} bash -c 'run_single_test "$@"' _ {}
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Count results from status files
PASSED=0
FAILED=0
SKIPPED=0

for status_file in "$RESULTS_DIR"/*.status; do
    if [[ -f "$status_file" ]]; then
        exit_code=$(cut -d: -f1 < "$status_file")
        if [[ $exit_code -eq 0 ]]; then
            PASSED=$((PASSED + 1))
        elif [[ $exit_code -eq 2 ]]; then
            SKIPPED=$((SKIPPED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    fi
done

# Final summary
echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Test Summary${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${GREEN}Passed:${RESET}  $PASSED"
echo -e "  ${RED}Failed:${RESET}  $FAILED"
echo -e "  ${YELLOW}Skipped:${RESET} $SKIPPED"
echo -e "  ${BOLD}Total:${RESET}   $TOTAL_TESTS"
echo ""
echo -e "  ${BOLD}Duration:${RESET} ${DURATION}s"
echo ""

# List failed tests
if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}${BOLD}Failed tests:${RESET}"
    for status_file in "$RESULTS_DIR"/*.status; do
        if [[ -f "$status_file" ]]; then
            exit_code=$(cut -d: -f1 < "$status_file")
            if [[ $exit_code -ne 0 && $exit_code -ne 2 ]]; then
                test_name=$(basename "$status_file" .status)
                echo -e "  ${RED}✗${RESET} $test_name.sh (exit $exit_code)"
                echo "    Log: $RESULTS_DIR/${test_name}.log"
            fi
        fi
    done
    echo ""
fi

# Exit with appropriate code
if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}${BOLD}Some tests FAILED${RESET}"
    exit 1
else
    echo -e "${GREEN}${BOLD}All tests PASSED${RESET}"
    exit 0
fi
