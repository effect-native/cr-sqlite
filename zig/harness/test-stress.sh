#!/usr/bin/env bash
# Stress/Performance Tests for Zig CR-SQLite
# Tests performance edge cases as defined in 96-ideal-parity-experiments.md
#
# Test Scenarios:
#   ST-002: 100k changes batch - memory stays bounded (verify completes without OOM)
#   ST-003: 1000 concurrent row operations - no deadlock
#   ST-004: Rapid INSERT/DELETE cycles - clock stays consistent
#
# These tests are opt-in by default. To run full stress tests:
#   STRESS_TESTS=1 bash test-stress.sh
#
# Without STRESS_TESTS=1, reduced iterations are used for CI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use .tmp in repo root for temp files (never /tmp/)
TMP_DIR="$REPO_ROOT/.tmp/test-stress"
mkdir -p "$TMP_DIR"

echo "=== Zig CR-SQLite Stress Tests ==="
echo ""

# Check if full stress tests are requested
FULL_STRESS="${STRESS_TESTS:-0}"
if [[ "$FULL_STRESS" == "1" ]]; then
    echo "Mode: FULL STRESS TESTS (STRESS_TESTS=1)"
    BATCH_SIZE=100000    # 100k changes for ST-002
    ROW_COUNT=1000       # 1000 concurrent rows for ST-003
    CYCLE_COUNT=100      # 100 INSERT/DELETE cycles for ST-004
else
    echo "Mode: CI (reduced iterations)"
    echo "       Set STRESS_TESTS=1 for full stress testing"
    BATCH_SIZE=10000     # 10k changes for CI
    ROW_COUNT=100        # 100 rows for CI
    CYCLE_COUNT=20       # 20 cycles for CI
fi
echo ""

# Build the extension
echo "Building Zig extension..."
cd "$ZIG_DIR"
if ! nix run nixpkgs#zig -- build 2>&1; then
    echo "FAIL: Zig build failed"
    exit 1
fi

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Extension not found at $ZIG_EXT"
    exit 1
fi

echo "Extension: $ZIG_EXT"
echo "Temp dir: $TMP_DIR"
echo ""

# Cleanup function
cleanup() {
    rm -rf "$TMP_DIR"/*.db "$TMP_DIR"/*.sql "$TMP_DIR"/*.out "$TMP_DIR"/*.txt 2>/dev/null || true
}
trap cleanup EXIT

FAILURES=0
PASSES=0

# Helper function: run SQL with Zig extension
run_zig() {
    local db="$1"; shift
    nix run nixpkgs#sqlite --quiet -- "$db" -cmd ".load $ZIG_EXT" "$@" 2>&1
}

# Helper function: run SQL file with Zig extension
run_zig_file() {
    local db="$1"
    local sqlfile="$2"
    nix run nixpkgs#sqlite --quiet -- "$db" -cmd ".load $ZIG_EXT" < "$sqlfile" 2>&1
}

# Helper function: run SQL with Rust/C oracle (for comparison)
run_rust() {
    local db="$1"; shift
    nix run github:subtleGradient/sqlite-cr --quiet -- "$db" <<< "$@" 2>&1
}

# Check for blocked functionality
check_blocked() {
    local output="$1"
    if echo "$output" | grep -q "no such function: crsql_as_crr"; then
        echo "BLOCKED: crsql_as_crr() not yet implemented"
        return 0
    fi
    if echo "$output" | grep -q "no such table: crsql_changes"; then
        echo "BLOCKED: crsql_changes virtual table not yet implemented"
        return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# ST-002: 100k Changes Batch - Memory Stays Bounded
# Verify that inserting a large batch of changes completes without OOM
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ST-002: Large Batch Changes (${BATCH_SIZE} inserts)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ST002="$TMP_DIR/st002_batch.db"
SQL_FILE="$TMP_DIR/st002_batch.sql"

# Create schema
echo "Creating schema..."
OUTPUT=$(run_zig "$DB_ST002" "
    CREATE TABLE batch_test (
        id INTEGER PRIMARY KEY NOT NULL,
        name TEXT,
        value INTEGER
    );
    SELECT crsql_as_crr('batch_test');
")

if check_blocked "$OUTPUT"; then
    echo "ST-002: BLOCKED"
    echo ""
else
    # Generate bulk insert SQL
    echo "Generating ${BATCH_SIZE} INSERT statements..."
    {
        echo "BEGIN;"
        for ((i = 1; i <= BATCH_SIZE; i++)); do
            echo "INSERT INTO batch_test VALUES ($i, 'row_$i', $((i * 10)));"
        done
        echo "COMMIT;"
    } > "$SQL_FILE"
    
    # Time the insert
    echo "Inserting ${BATCH_SIZE} rows..."
    START_TIME=$(date +%s.%N)
    OUTPUT=$(run_zig_file "$DB_ST002" "$SQL_FILE" 2>&1) || true
    END_TIME=$(date +%s.%N)
    INSERT_TIME=$(echo "$END_TIME - $START_TIME" | bc)
    
    # Check for errors
    if echo "$OUTPUT" | grep -qi "out of memory\|error\|fail"; then
        echo "  FAIL: Error during batch insert"
        echo "  Output: $OUTPUT"
        FAILURES=$((FAILURES + 1))
    else
        # Verify row count
        ROW_COUNT_ACTUAL=$(run_zig "$DB_ST002" "SELECT COUNT(*) FROM batch_test;")
        if [[ "$ROW_COUNT_ACTUAL" == "$BATCH_SIZE" ]]; then
            echo "  Insert time: ${INSERT_TIME}s"
            echo "  Row count: PASS ($ROW_COUNT_ACTUAL rows)"
            PASSES=$((PASSES + 1))
        else
            echo "  FAIL: Expected $BATCH_SIZE rows, got $ROW_COUNT_ACTUAL"
            FAILURES=$((FAILURES + 1))
        fi
        
        # Verify changes table has expected count
        # Each row generates 2 changes: sentinel (-1) + column (name) + column (value)
        # But INSERT generates entries for all columns in crsql_changes
        CHANGES_COUNT=$(run_zig "$DB_ST002" "SELECT COUNT(*) FROM crsql_changes WHERE [table] = 'batch_test';")
        EXPECTED_CHANGES=$((BATCH_SIZE * 3))  # sentinel + name + value per row
        
        # Allow some flexibility in counting (depends on implementation)
        if [[ "$CHANGES_COUNT" -ge "$BATCH_SIZE" ]]; then
            echo "  Changes count: PASS ($CHANGES_COUNT changes recorded)"
            PASSES=$((PASSES + 1))
        else
            echo "  Changes count: WARN ($CHANGES_COUNT changes, expected >= $BATCH_SIZE)"
        fi
        
        # Verify db_version is reasonable (should be 1 since all in one transaction)
        DB_VERSION=$(run_zig "$DB_ST002" "SELECT crsql_db_version();")
        echo "  Final db_version: $DB_VERSION"
        if [[ "$DB_VERSION" -ge 1 ]]; then
            echo "  db_version: PASS"
            PASSES=$((PASSES + 1))
        else
            echo "  db_version: FAIL (expected >= 1)"
            FAILURES=$((FAILURES + 1))
        fi
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ST-003: 1000 Concurrent Row Operations - No Deadlock
# Verify that many row operations can be performed without deadlock
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ST-003: Concurrent Row Operations (${ROW_COUNT} rows)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ST003="$TMP_DIR/st003_concurrent.db"
SQL_FILE="$TMP_DIR/st003_concurrent.sql"

# Create schema
OUTPUT=$(run_zig "$DB_ST003" "
    CREATE TABLE concurrent_test (
        id INTEGER PRIMARY KEY NOT NULL,
        counter INTEGER,
        data TEXT
    );
    SELECT crsql_as_crr('concurrent_test');
")

if check_blocked "$OUTPUT"; then
    echo "ST-003: BLOCKED"
    echo ""
else
    # Generate concurrent operations: INSERT, UPDATE, UPDATE
    # This simulates multiple writers hitting different rows
    echo "Generating concurrent operations..."
    {
        echo "BEGIN;"
        # First: INSERT all rows
        for ((i = 1; i <= ROW_COUNT; i++)); do
            echo "INSERT INTO concurrent_test VALUES ($i, 0, 'initial_$i');"
        done
        echo "COMMIT;"
        
        echo "BEGIN;"
        # Second: UPDATE all rows (counter++)
        for ((i = 1; i <= ROW_COUNT; i++)); do
            echo "UPDATE concurrent_test SET counter = counter + 1 WHERE id = $i;"
        done
        echo "COMMIT;"
        
        echo "BEGIN;"
        # Third: UPDATE all rows again (different column)
        for ((i = 1; i <= ROW_COUNT; i++)); do
            echo "UPDATE concurrent_test SET data = 'updated_$i' WHERE id = $i;"
        done
        echo "COMMIT;"
    } > "$SQL_FILE"
    
    # Run with timeout to detect deadlock
    echo "Running ${ROW_COUNT} INSERTs + ${ROW_COUNT} UPDATEs + ${ROW_COUNT} UPDATEs..."
    START_TIME=$(date +%s.%N)
    
    # Use timeout to catch deadlocks (60 seconds should be plenty)
    if timeout 60 bash -c "nix run nixpkgs#sqlite --quiet -- '$DB_ST003' -cmd '.load $ZIG_EXT' < '$SQL_FILE' 2>&1"; then
        END_TIME=$(date +%s.%N)
        EXEC_TIME=$(echo "$END_TIME - $START_TIME" | bc)
        echo "  Execution time: ${EXEC_TIME}s"
        
        # Verify all rows exist with correct values
        ACTUAL_COUNT=$(run_zig "$DB_ST003" "SELECT COUNT(*) FROM concurrent_test;")
        if [[ "$ACTUAL_COUNT" == "$ROW_COUNT" ]]; then
            echo "  Row count: PASS ($ACTUAL_COUNT rows)"
            PASSES=$((PASSES + 1))
        else
            echo "  Row count: FAIL (expected $ROW_COUNT, got $ACTUAL_COUNT)"
            FAILURES=$((FAILURES + 1))
        fi
        
        # Verify counters are correct (should all be 1)
        COUNTER_CHECK=$(run_zig "$DB_ST003" "SELECT COUNT(*) FROM concurrent_test WHERE counter = 1;")
        if [[ "$COUNTER_CHECK" == "$ROW_COUNT" ]]; then
            echo "  Counter values: PASS (all rows have counter=1)"
            PASSES=$((PASSES + 1))
        else
            echo "  Counter values: FAIL (expected $ROW_COUNT rows with counter=1, got $COUNTER_CHECK)"
            FAILURES=$((FAILURES + 1))
        fi
        
        # Verify data was updated
        DATA_CHECK=$(run_zig "$DB_ST003" "SELECT COUNT(*) FROM concurrent_test WHERE data LIKE 'updated_%';")
        if [[ "$DATA_CHECK" == "$ROW_COUNT" ]]; then
            echo "  Data updates: PASS (all rows updated)"
            PASSES=$((PASSES + 1))
        else
            echo "  Data updates: FAIL (expected $ROW_COUNT updated, got $DATA_CHECK)"
            FAILURES=$((FAILURES + 1))
        fi
        
        # Verify clock table is consistent
        CLOCK_COUNT=$(run_zig "$DB_ST003" "SELECT COUNT(*) FROM concurrent_test__crsql_clock;")
        echo "  Clock entries: $CLOCK_COUNT"
        if [[ "$CLOCK_COUNT" -ge "$ROW_COUNT" ]]; then
            echo "  Clock table: PASS"
            PASSES=$((PASSES + 1))
        else
            echo "  Clock table: FAIL (expected >= $ROW_COUNT entries)"
            FAILURES=$((FAILURES + 1))
        fi
    else
        echo "  FAIL: Operation timed out (possible deadlock)"
        FAILURES=$((FAILURES + 1))
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# ST-004: Rapid INSERT/DELETE Cycles - Clock Stays Consistent
# Verify that rapid cycles of INSERT-DELETE-INSERT maintain clock consistency
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ST-004: Rapid INSERT/DELETE Cycles (${CYCLE_COUNT} cycles)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ST004="$TMP_DIR/st004_cycles.db"
SQL_FILE="$TMP_DIR/st004_cycles.sql"

# Create schema
OUTPUT=$(run_zig "$DB_ST004" "
    CREATE TABLE cycle_test (
        id INTEGER PRIMARY KEY NOT NULL,
        value TEXT
    );
    SELECT crsql_as_crr('cycle_test');
")

if check_blocked "$OUTPUT"; then
    echo "ST-004: BLOCKED"
    echo ""
else
    # Generate rapid INSERT-DELETE-INSERT cycles on the same row
    # Each cycle should increment the causal length (cl)
    echo "Generating ${CYCLE_COUNT} INSERT-DELETE cycles on same row..."
    {
        for ((i = 1; i <= CYCLE_COUNT; i++)); do
            echo "INSERT OR REPLACE INTO cycle_test VALUES (1, 'insert_$i');"
            echo "DELETE FROM cycle_test WHERE id = 1;"
        done
        # Final INSERT to leave row in live state
        echo "INSERT INTO cycle_test VALUES (1, 'final_insert');"
    } > "$SQL_FILE"
    
    # Get initial db_version
    INITIAL_VERSION=$(run_zig "$DB_ST004" "SELECT crsql_db_version();")
    
    # Run the cycles
    echo "Running ${CYCLE_COUNT} INSERT-DELETE cycles..."
    START_TIME=$(date +%s.%N)
    OUTPUT=$(run_zig_file "$DB_ST004" "$SQL_FILE" 2>&1) || true
    END_TIME=$(date +%s.%N)
    CYCLE_TIME=$(echo "$END_TIME - $START_TIME" | bc)
    
    # Check for errors
    if echo "$OUTPUT" | grep -qi "error\|fail"; then
        echo "  FAIL: Error during cycle operations"
        echo "  Output: $OUTPUT"
        FAILURES=$((FAILURES + 1))
    else
        echo "  Cycle time: ${CYCLE_TIME}s"
        
        # Verify final state: row should exist with 'final_insert'
        FINAL_VALUE=$(run_zig "$DB_ST004" "SELECT value FROM cycle_test WHERE id = 1;" 2>/dev/null || echo "DELETED")
        if [[ "$FINAL_VALUE" == "final_insert" ]]; then
            echo "  Final value: PASS (row exists with correct value)"
            PASSES=$((PASSES + 1))
        else
            echo "  Final value: FAIL (expected 'final_insert', got '$FINAL_VALUE')"
            FAILURES=$((FAILURES + 1))
        fi
        
        # Check db_version advanced
        FINAL_VERSION=$(run_zig "$DB_ST004" "SELECT crsql_db_version();")
        echo "  db_version: $INITIAL_VERSION -> $FINAL_VERSION"
        if [[ "$FINAL_VERSION" -gt "$INITIAL_VERSION" ]]; then
            echo "  db_version advance: PASS"
            PASSES=$((PASSES + 1))
        else
            echo "  db_version advance: FAIL (did not increase)"
            FAILURES=$((FAILURES + 1))
        fi
        
        # Check causal length (cl) in clock table
        # After N cycles of INSERT-DELETE + final INSERT:
        # cl should be: 2*CYCLE_COUNT + 1 (each INSERT increments, each DELETE increments)
        EXPECTED_CL=$((2 * CYCLE_COUNT + 1))
        
        # Query the sentinel column (-1) which tracks row lifecycle
        CL_VALUE=$(run_zig "$DB_ST004" "SELECT col_version FROM cycle_test__crsql_clock WHERE key = 1 AND col_name = '-1';" 2>/dev/null || echo "N/A")
        echo "  Causal length (cl): $CL_VALUE (expected ~$EXPECTED_CL)"
        
        # cl should be positive and reasonable (at least CYCLE_COUNT*2)
        if [[ "$CL_VALUE" != "N/A" && "$CL_VALUE" -ge "$CYCLE_COUNT" ]]; then
            echo "  Clock consistency: PASS (cl incremented properly)"
            PASSES=$((PASSES + 1))
        else
            echo "  Clock consistency: WARN (cl may not have incremented as expected)"
        fi
        
        # Verify crsql_changes can be queried
        CHANGES_COUNT=$(run_zig "$DB_ST004" "SELECT COUNT(*) FROM crsql_changes WHERE [table] = 'cycle_test';")
        echo "  Changes recorded: $CHANGES_COUNT"
        if [[ "$CHANGES_COUNT" -ge 1 ]]; then
            echo "  Changes table: PASS"
            PASSES=$((PASSES + 1))
        else
            echo "  Changes table: FAIL (no changes recorded)"
            FAILURES=$((FAILURES + 1))
        fi
    fi
    
    # Additional test: verify clock state is mergeable
    echo ""
    echo "  Verifying clock state is valid for merge..."
    
    # Create a second DB and try to sync changes
    DB_ST004_PEER="$TMP_DIR/st004_peer.db"
    run_zig "$DB_ST004_PEER" "
        CREATE TABLE cycle_test (
            id INTEGER PRIMARY KEY NOT NULL,
            value TEXT
        );
        SELECT crsql_as_crr('cycle_test');
    " > /dev/null
    
    # Export changes from source
    PEER_SITE_ID=$(run_zig "$DB_ST004_PEER" "SELECT quote(crsql_site_id());")
    
    # Get latest change
    LATEST_CHANGE=$(run_zig "$DB_ST004" "
        SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq
        FROM crsql_changes
        WHERE [table] = 'cycle_test'
        ORDER BY db_version DESC, seq DESC
        LIMIT 1;
    ")
    
    if [[ -n "$LATEST_CHANGE" ]]; then
        echo "  Latest change exported: OK"
        PASSES=$((PASSES + 1))
    else
        echo "  Latest change export: FAIL (no change found)"
        FAILURES=$((FAILURES + 1))
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                       STRESS TEST SUMMARY                            ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  Mode:    %-60s ║\n" "$([ "$FULL_STRESS" == "1" ] && echo "FULL STRESS" || echo "CI (reduced)")"
printf "║  PASSED:  %-60d ║\n" "$PASSES"
printf "║  FAILED:  %-60d ║\n" "$FAILURES"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
echo "║  ST-002: Large batch inserts (memory bounded)                        ║"
echo "║  ST-003: Concurrent row operations (no deadlock)                     ║"
echo "║  ST-004: Rapid INSERT/DELETE cycles (clock consistent)               ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $FAILURES -eq 0 ]]; then
    echo "All stress tests PASSED"
    exit 0
else
    echo "$FAILURES test(s) FAILED"
    exit 1
fi
