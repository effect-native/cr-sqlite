#!/usr/bin/env bash
# Test: crsql_internal_sync_bit must be per-connection
#
# This test verifies that setting sync_bit on Connection A does NOT
# affect Connection B. If sync_bit is global (process-wide), then
# Connection A's merge operation would suppress change capture on
# Connection B, which is a correctness bug.
#
# Test approach:
# 1. Create a database with a CRR table
# 2. Connection A: sets sync_bit=1 AND KEEPS THE CONNECTION OPEN
# 3. Connection B (separate process): performs INSERT while A is holding
# 4. Connection B: verifies changes were captured in clock table
#
# Note: We use named pipes (FIFOs) to coordinate between processes.

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_ROOT="$SCRIPT_DIR/.."

# Determine extension path based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    EXT="$ZIG_ROOT/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_ROOT/zig-out/lib/libcrsqlite.so"
fi

# Check if extension exists
if [[ ! -f "$EXT" ]]; then
    echo -e "${RED}Error: Extension not found at $EXT${NC}"
    echo "Build it with: make -C zig build"
    exit 1
fi

# Create temp directory for test databases and FIFOs
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; kill $CONN_A_PID 2>/dev/null || true' EXIT

DB_FILE="$TMPDIR/test.db"
FIFO_A_READY="$TMPDIR/a_ready"
FIFO_B_DONE="$TMPDIR/b_done"

mkfifo "$FIFO_A_READY" "$FIFO_B_DONE"

echo "=== Test: sync_bit connection isolation ==="
echo "Extension: $EXT"
echo "Database: $DB_FILE"
echo ""

# Helper function to run SQL using nix-provided sqlite3
run_sql() {
    local db="$1"
    shift
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$@"
}

# Initialize the database and create a CRR table
echo "Step 1: Initialize database and create CRR table"
run_sql "$DB_FILE" "CREATE TABLE foo (id INTEGER PRIMARY KEY, value TEXT);" "SELECT crsql_as_crr('foo');"
echo "  Created foo as CRR"

echo ""
echo "Step 2: Start Connection A (holds sync_bit=1)"

# Connection A - runs in background, sets sync_bit=1, signals, then waits
(
    nix run nixpkgs#sqlite -- "$DB_FILE" -cmd ".load $EXT" <<EOF
-- Set sync_bit to 1 (simulating merge operation)
SELECT crsql_internal_sync_bit(1);
-- Signal that we've set the bit (create the file)
SELECT 'A: sync_bit set to 1';
EOF
    # Signal A is ready
    echo "ready" > "$FIFO_A_READY"
    # Wait for B to finish
    cat "$FIFO_B_DONE" > /dev/null
) &
CONN_A_PID=$!

# Wait for A to signal it's ready
echo "  Waiting for Connection A to set sync_bit..."
cat "$FIFO_A_READY" > /dev/null
echo "  Connection A ready (sync_bit=1)"

echo ""
echo "Step 3: Connection B performs local INSERT (separate process)"

# Connection B - separate process, should NOT see A's sync_bit
CONN_B_OUTPUT=$(run_sql "$DB_FILE" "
-- Check what sync_bit B sees (MUST be 0 if per-connection)
SELECT 'B_SEES_SYNC_BIT: ' || crsql_internal_sync_bit();
-- Do a local insert (should trigger change capture regardless of A's state)
INSERT INTO foo (id, value) VALUES (1, 'hello_from_b');
-- Check if change was captured
SELECT 'CLOCK_ROWS: ' || COUNT(*) FROM foo__crsql_clock;
")

# Signal B is done so A can exit
echo "done" > "$FIFO_B_DONE"

# Wait for A to finish
wait $CONN_A_PID 2>/dev/null || true

echo ""
echo "=== Results ==="
echo "$CONN_B_OUTPUT"
echo ""

# Parse results
SYNC_BIT_SEEN=$(echo "$CONN_B_OUTPUT" | grep "B_SEES_SYNC_BIT:" | sed 's/B_SEES_SYNC_BIT: //')
CLOCK_ROWS=$(echo "$CONN_B_OUTPUT" | grep "CLOCK_ROWS:" | sed 's/CLOCK_ROWS: //')

echo "Connection B saw sync_bit = $SYNC_BIT_SEEN"
echo "Clock table has $CLOCK_ROWS rows"
echo ""

# Test assertions
PASS=true

# Check 1: Connection B should see sync_bit=0 (per-connection isolation)
if [[ "$SYNC_BIT_SEEN" == "0" ]]; then
    echo -e "${GREEN}✓ PASS: Connection B sees sync_bit=0 (correct per-connection isolation)${NC}"
else
    echo -e "${RED}✗ FAIL: Connection B sees sync_bit=$SYNC_BIT_SEEN (expected 0)${NC}"
    echo "  This indicates sync_bit is GLOBAL, not per-connection!"
    PASS=false
fi

# Check 2: Clock table should have rows (change was captured)
if [[ "$CLOCK_ROWS" -gt 0 ]]; then
    echo -e "${GREEN}✓ PASS: Clock table has $CLOCK_ROWS rows (changes captured)${NC}"
else
    echo -e "${RED}✗ FAIL: Clock table has 0 rows (changes NOT captured)${NC}"
    echo "  This means Connection A's sync_bit=1 suppressed Connection B's triggers!"
    PASS=false
fi

echo ""
if $PASS; then
    echo -e "${GREEN}=== ALL TESTS PASSED ===${NC}"
    exit 0
else
    echo -e "${RED}=== TESTS FAILED ===${NC}"
    echo ""
    echo "The sync_bit is currently GLOBAL, which is a correctness bug."
    echo "Multi-connection scenarios will have suppressed change capture."
    exit 1
fi
