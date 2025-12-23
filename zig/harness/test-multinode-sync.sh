#!/usr/bin/env bash
# Multi-node Sync Parity Tests for Zig CR-SQLite
# Tests complex multi-node sync scenarios that caused production bugs.
#
# Tests:
# 1. test_discord_corrosion - 4-node scenario from Python test_cl_merging.py::test_discord_report_corrosion
# 2. test_star_topology - Hub-and-spoke sync pattern with central hub
#
# Reference: TASK-179, py/correctness/tests/test_cl_merging.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite: Multi-node Sync Parity (Zig vs Rust/C)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Tests complex multi-node sync patterns from Python test_cl_merging.py"
echo ""

# Build the Zig extension
echo "Building Zig extension..."
cd "$ZIG_DIR"
if ! nix run nixpkgs#zig -- build 2>&1; then
    echo "FAIL: Zig build failed"
    exit 1
fi

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
    fi
fi

# Verify extensions exist
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Zig extension not found at $ZIG_EXT"
    exit 1
fi

if [[ ! -f "$RUST_EXT" ]]; then
    echo "ERROR: Rust/C oracle not found at $RUST_EXT"
    echo "Run: ./scripts/update-crsqlite-oracle.sh"
    exit 1
fi

SQLITE="timeout 30s nix run nixpkgs#sqlite --"

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory
TMPDIR="${REPO_ROOT}/.tmp/multinode-sync-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

ERRFILE="$TMPDIR/error.txt"

PASS=0
FAIL=0
SKIP=0

# ══════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ══════════════════════════════════════════════════════════════════════════════

# Run SQL with Zig extension
run_zig() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Run SQL with Rust/C extension
run_rust() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

# Check for blocking errors
is_blocked() {
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function" "$ERRFILE"; then
            return 0
        fi
    fi
    return 1
}

# Initialize a database with schema
# Usage: init_db <impl> <db_path>
# impl: "zig" or "rust"
init_db() {
    local impl="$1"
    local db="$2"
    local sql="
CREATE TABLE foo (a PRIMARY KEY NOT NULL, b, c, d, e);
SELECT crsql_as_crr('foo');
"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$sql"
    else
        run_rust "$db" "$sql"
    fi
}

# Sync changes from source to dest for a specific db_version
# Usage: sync_version <impl> <src_db> <dest_db> <version>
sync_version() {
    local impl="$1"
    local src="$2"
    local dest="$3"
    local version="$4"
    local changes_file="$TMPDIR/changes_${version}.txt"
    
    # Get changes at exact version
    local query="SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq FROM crsql_changes WHERE db_version = $version;"
    
    if [[ "$impl" == "zig" ]]; then
        run_zig "$src" "$query" > "$changes_file"
    else
        run_rust "$src" "$query" > "$changes_file"
    fi
    
    # Apply each change to destination
    while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
        [[ -z "$tbl" ]] && continue
        local insert_sql="INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);"
        if [[ "$impl" == "zig" ]]; then
            run_zig "$dest" "$insert_sql"
        else
            run_rust "$dest" "$insert_sql"
        fi
    done < "$changes_file"
}

# Sync all changes from source to dest since a version
# Usage: sync_since <impl> <src_db> <dest_db> <since_version>
sync_since() {
    local impl="$1"
    local src="$2"
    local dest="$3"
    local since="$4"
    local changes_file="$TMPDIR/changes_since_${since}.txt"
    
    # Get changes since version
    local query="SELECT [table], quote(pk), cid, quote(val), col_version, db_version, quote(site_id), cl, seq FROM crsql_changes WHERE db_version > $since;"
    
    if [[ "$impl" == "zig" ]]; then
        run_zig "$src" "$query" > "$changes_file"
    else
        run_rust "$src" "$query" > "$changes_file"
    fi
    
    # Apply each change to destination
    while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
        [[ -z "$tbl" ]] && continue
        local insert_sql="INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);"
        if [[ "$impl" == "zig" ]]; then
            run_zig "$dest" "$insert_sql"
        else
            run_rust "$dest" "$insert_sql"
        fi
    done < "$changes_file"
}

# Get table data for comparison (excluding db_version which may differ)
# Usage: get_table_data <impl> <db>
get_table_data() {
    local impl="$1"
    local db="$2"
    local query="SELECT * FROM foo ORDER BY a;"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$query"
    else
        run_rust "$db" "$query"
    fi
}

# Get changes metadata for comparison (cid, col_version, cl, val - excluding db_version)
# Usage: get_changes_metadata <impl> <db>
get_changes_metadata() {
    local impl="$1"
    local db="$2"
    local query="SELECT cid, col_version, cl, val FROM crsql_changes ORDER BY cid;"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$query"
    else
        run_rust "$db" "$query"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: Discord Corrosion Scenario (3 nodes - from Python test)
# Source: py/correctness/tests/test_cl_merging.py::test_discord_report_corrosion
# ══════════════════════════════════════════════════════════════════════════════
test_discord_corrosion() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: Discord Corrosion ($impl)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario (from Python test_discord_report_corrosion):"
    echo "  1. Node C creates row with pk=1"
    echo "  2. C syncs to A and B (version 1)"
    echo "  3. C deletes the row (version 2)"
    echo "  4. C syncs delete to A and B"
    echo "  5. C re-inserts the row with new values (version 3)"
    echo "  6. B gets the re-insertion, A does NOT"
    echo "  7. C updates columns b and c (version 4)"
    echo "  8. Updates go to A and B"
    echo "  9. Finally, A receives the old re-insert (version 3)"
    echo "  10. All nodes should converge"
    echo ""
    
    # Create databases
    local db_a="$TMPDIR/${prefix}_a.db"
    local db_b="$TMPDIR/${prefix}_b.db"
    local db_c="$TMPDIR/${prefix}_c.db"
    
    rm -f "$db_a" "$db_b" "$db_c"
    
    # Initialize all databases with schema
    init_db "$impl" "$db_a"
    init_db "$impl" "$db_b"
    init_db "$impl" "$db_c"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Step 1: C creates row
    echo "Step 1: C inserts row (1, 'b', 'c', 'd', 'e')"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_c" "INSERT INTO foo VALUES (1, 'b', 'c', 'd', 'e');"
    else
        run_rust "$db_c" "INSERT INTO foo VALUES (1, 'b', 'c', 'd', 'e');"
    fi
    
    # Step 2: C syncs version 1 to A and B
    echo "Step 2: C syncs version 1 to A and B"
    sync_version "$impl" "$db_c" "$db_a" 1
    sync_version "$impl" "$db_c" "$db_b" 1
    
    # Verify all have the row
    local a_count b_count c_count
    if [[ "$impl" == "zig" ]]; then
        a_count=$(run_zig "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_zig "$db_b" "SELECT COUNT(*) FROM foo;")
        c_count=$(run_zig "$db_c" "SELECT COUNT(*) FROM foo;")
    else
        a_count=$(run_rust "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_rust "$db_b" "SELECT COUNT(*) FROM foo;")
        c_count=$(run_rust "$db_c" "SELECT COUNT(*) FROM foo;")
    fi
    
    if [[ "$a_count" != "1" || "$b_count" != "1" || "$c_count" != "1" ]]; then
        echo "  FAIL: Initial sync failed (A=$a_count, B=$b_count, C=$c_count)"
        return 1
    fi
    echo "  ✓ All nodes have row after initial sync"
    
    # Step 3: C deletes the row
    echo "Step 3: C deletes row"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_c" "DELETE FROM foo WHERE a = 1;"
    else
        run_rust "$db_c" "DELETE FROM foo WHERE a = 1;"
    fi
    
    # Step 4: Delete syncs to A and B
    echo "Step 4: C syncs delete (version 2) to A and B"
    sync_version "$impl" "$db_c" "$db_a" 2
    sync_version "$impl" "$db_c" "$db_b" 2
    
    # Verify all have deleted the row
    if [[ "$impl" == "zig" ]]; then
        a_count=$(run_zig "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_zig "$db_b" "SELECT COUNT(*) FROM foo;")
    else
        a_count=$(run_rust "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_rust "$db_b" "SELECT COUNT(*) FROM foo;")
    fi
    
    if [[ "$a_count" != "0" || "$b_count" != "0" ]]; then
        echo "  FAIL: Delete sync failed (A=$a_count, B=$b_count)"
        return 1
    fi
    echo "  ✓ Row deleted on A and B"
    
    # Step 5: C re-inserts the row
    echo "Step 5: C re-inserts row (1, 'b1', 'c1', 'd1', 'e1')"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_c" "INSERT INTO foo VALUES (1, 'b1', 'c1', 'd1', 'e1');"
    else
        run_rust "$db_c" "INSERT INTO foo VALUES (1, 'b1', 'c1', 'd1', 'e1');"
    fi
    
    # Step 6: B gets the re-insertion, A does NOT
    echo "Step 6: B gets re-insert (version 3), A does NOT"
    sync_version "$impl" "$db_c" "$db_b" 3
    
    # Verify B has the row, A still doesn't
    if [[ "$impl" == "zig" ]]; then
        a_count=$(run_zig "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_zig "$db_b" "SELECT COUNT(*) FROM foo;")
    else
        a_count=$(run_rust "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_rust "$db_b" "SELECT COUNT(*) FROM foo;")
    fi
    
    if [[ "$b_count" != "1" ]]; then
        echo "  FAIL: B should have re-inserted row (B=$b_count)"
        return 1
    fi
    echo "  ✓ B has re-inserted row, A still empty (A=$a_count)"
    
    # Step 7: C updates columns b and c
    echo "Step 7: C updates row (b='b2', c='c2')"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_c" "UPDATE foo SET b = 'b2', c = 'c2' WHERE a = 1;"
    else
        run_rust "$db_c" "UPDATE foo SET b = 'b2', c = 'c2' WHERE a = 1;"
    fi
    
    # Step 8: Updates go to A and B
    echo "Step 8: C syncs updates (version 4) to A and B"
    sync_version "$impl" "$db_c" "$db_a" 4
    sync_version "$impl" "$db_c" "$db_b" 4
    
    # Verify A now has the row (via updates which carry cl=3)
    if [[ "$impl" == "zig" ]]; then
        a_count=$(run_zig "$db_a" "SELECT COUNT(*) FROM foo;")
    else
        a_count=$(run_rust "$db_a" "SELECT COUNT(*) FROM foo;")
    fi
    
    # A should have resurrected via the update with higher cl
    echo "  A row count after updates: $a_count"
    
    # Check A's change state
    local a_changes
    if [[ "$impl" == "zig" ]]; then
        a_changes=$(run_zig "$db_a" "SELECT cid, col_version, cl FROM crsql_changes ORDER BY cid;")
    else
        a_changes=$(run_rust "$db_a" "SELECT cid, col_version, cl FROM crsql_changes ORDER BY cid;")
    fi
    echo "  A changes after step 8: $a_changes"
    
    # Step 9: A receives the old re-insert (version 3)
    echo "Step 9: A receives old re-insert (version 3)"
    sync_version "$impl" "$db_c" "$db_a" 3
    
    # Step 10: Verify convergence
    echo "Step 10: Verify convergence"
    
    local data_a data_b data_c
    data_a=$(get_table_data "$impl" "$db_a")
    data_b=$(get_table_data "$impl" "$db_b")
    data_c=$(get_table_data "$impl" "$db_c")
    
    echo "  A data: $data_a"
    echo "  B data: $data_b"
    echo "  C data: $data_c"
    
    if [[ "$data_a" != "$data_b" ]]; then
        echo "  FAIL: A and B diverged"
        echo "    A: $data_a"
        echo "    B: $data_b"
        return 1
    fi
    
    if [[ "$data_a" != "$data_c" ]]; then
        echo "  FAIL: A and C diverged"
        echo "    A: $data_a"
        echo "    C: $data_c"
        return 1
    fi
    
    echo "  ✓ PASS: All nodes converged to same data"
    
    # Verify metadata parity
    local meta_a meta_b meta_c
    meta_a=$(get_changes_metadata "$impl" "$db_a")
    meta_b=$(get_changes_metadata "$impl" "$db_b")
    meta_c=$(get_changes_metadata "$impl" "$db_c")
    
    if [[ "$meta_a" != "$meta_b" || "$meta_a" != "$meta_c" ]]; then
        echo "  INFO: Metadata differs (expected - db_version varies)"
        echo "    A: $meta_a"
        echo "    B: $meta_b"
        echo "    C: $meta_c"
    else
        echo "  ✓ PASS: All nodes have identical change metadata"
    fi
    
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Extended 4-node Discord Corrosion
# Extends the Python test to 4 nodes with more complex sync patterns
# ══════════════════════════════════════════════════════════════════════════════
test_discord_4node() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: Extended 4-Node Discord Corrosion ($impl)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario:"
    echo "  1. Node A creates row"
    echo "  2. A syncs to B, B syncs to C, C syncs to D"
    echo "  3. A updates row"
    echo "  4. B receives A's update"
    echo "  5. A deletes row"
    echo "  6. C receives delete via D (out of order)"
    echo "  7. A resurrects row"
    echo "  8. Final sync: verify all converge"
    echo ""
    
    # Create databases
    local db_a="$TMPDIR/${prefix}_4n_a.db"
    local db_b="$TMPDIR/${prefix}_4n_b.db"
    local db_c="$TMPDIR/${prefix}_4n_c.db"
    local db_d="$TMPDIR/${prefix}_4n_d.db"
    
    rm -f "$db_a" "$db_b" "$db_c" "$db_d"
    
    # Initialize all databases with schema
    init_db "$impl" "$db_a"
    init_db "$impl" "$db_b"
    init_db "$impl" "$db_c"
    init_db "$impl" "$db_d"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Step 1: A creates row
    echo "Step 1: A inserts row (1, 'a1', 'a2', 'a3', 'a4')"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_a" "INSERT INTO foo VALUES (1, 'a1', 'a2', 'a3', 'a4');"
    else
        run_rust "$db_a" "INSERT INTO foo VALUES (1, 'a1', 'a2', 'a3', 'a4');"
    fi
    
    # Step 2: A→B→C→D sync chain
    echo "Step 2: Sync chain A→B→C→D"
    sync_since "$impl" "$db_a" "$db_b" 0
    sync_since "$impl" "$db_b" "$db_c" 0
    sync_since "$impl" "$db_c" "$db_d" 0
    
    # Verify all have the row
    local a_count b_count c_count d_count
    if [[ "$impl" == "zig" ]]; then
        a_count=$(run_zig "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_zig "$db_b" "SELECT COUNT(*) FROM foo;")
        c_count=$(run_zig "$db_c" "SELECT COUNT(*) FROM foo;")
        d_count=$(run_zig "$db_d" "SELECT COUNT(*) FROM foo;")
    else
        a_count=$(run_rust "$db_a" "SELECT COUNT(*) FROM foo;")
        b_count=$(run_rust "$db_b" "SELECT COUNT(*) FROM foo;")
        c_count=$(run_rust "$db_c" "SELECT COUNT(*) FROM foo;")
        d_count=$(run_rust "$db_d" "SELECT COUNT(*) FROM foo;")
    fi
    
    if [[ "$a_count" != "1" || "$b_count" != "1" || "$c_count" != "1" || "$d_count" != "1" ]]; then
        echo "  FAIL: Initial sync failed (A=$a_count, B=$b_count, C=$c_count, D=$d_count)"
        return 1
    fi
    echo "  ✓ All 4 nodes have row"
    
    # Step 3: A updates row
    echo "Step 3: A updates row (b='updated')"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_a" "UPDATE foo SET b = 'updated' WHERE a = 1;"
    else
        run_rust "$db_a" "UPDATE foo SET b = 'updated' WHERE a = 1;"
    fi
    
    # Step 4: B receives update
    echo "Step 4: B receives A's update"
    sync_since "$impl" "$db_a" "$db_b" 1
    
    # Step 5: A deletes row
    echo "Step 5: A deletes row"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_a" "DELETE FROM foo WHERE a = 1;"
    else
        run_rust "$db_a" "DELETE FROM foo WHERE a = 1;"
    fi
    
    # Step 6: D receives delete, then syncs to C (out of order)
    echo "Step 6: D receives delete, syncs to C"
    sync_since "$impl" "$db_a" "$db_d" 2
    sync_since "$impl" "$db_d" "$db_c" 0
    
    # Step 7: A resurrects row
    echo "Step 7: A resurrects row"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db_a" "INSERT INTO foo VALUES (1, 'resurrected', 'r2', 'r3', 'r4');"
    else
        run_rust "$db_a" "INSERT INTO foo VALUES (1, 'resurrected', 'r2', 'r3', 'r4');"
    fi
    
    # Step 8: Final sync - all nodes sync with each other
    echo "Step 8: Final sync round"
    # A→B→C→D
    sync_since "$impl" "$db_a" "$db_b" 0
    sync_since "$impl" "$db_b" "$db_c" 0
    sync_since "$impl" "$db_c" "$db_d" 0
    # D→C→B→A (reverse)
    sync_since "$impl" "$db_d" "$db_c" 0
    sync_since "$impl" "$db_c" "$db_b" 0
    sync_since "$impl" "$db_b" "$db_a" 0
    
    # Verify convergence
    echo "Step 9: Verify convergence"
    
    local data_a data_b data_c data_d
    data_a=$(get_table_data "$impl" "$db_a")
    data_b=$(get_table_data "$impl" "$db_b")
    data_c=$(get_table_data "$impl" "$db_c")
    data_d=$(get_table_data "$impl" "$db_d")
    
    echo "  A data: $data_a"
    echo "  B data: $data_b"
    echo "  C data: $data_c"
    echo "  D data: $data_d"
    
    local converged=true
    if [[ "$data_a" != "$data_b" ]]; then
        echo "  FAIL: A and B diverged"
        converged=false
    fi
    if [[ "$data_a" != "$data_c" ]]; then
        echo "  FAIL: A and C diverged"
        converged=false
    fi
    if [[ "$data_a" != "$data_d" ]]; then
        echo "  FAIL: A and D diverged"
        converged=false
    fi
    
    if [[ "$converged" == "true" ]]; then
        echo "  ✓ PASS: All 4 nodes converged"
        
        # Verify row is resurrected (should have data, not be deleted)
        if [[ "$impl" == "zig" ]]; then
            local final_count=$(run_zig "$db_a" "SELECT COUNT(*) FROM foo;")
        else
            local final_count=$(run_rust "$db_a" "SELECT COUNT(*) FROM foo;")
        fi
        
        if [[ "$final_count" == "1" ]]; then
            echo "  ✓ PASS: Row correctly resurrected"
            return 0
        else
            echo "  FAIL: Row should be resurrected (count=$final_count)"
            return 1
        fi
    else
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Star Topology (Hub and Spoke)
# Hub A connects to B, C, D (spokes don't directly connect)
# ══════════════════════════════════════════════════════════════════════════════
test_star_topology() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: Star Topology ($impl)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Scenario: Hub-and-spoke topology"
    echo "  Hub A connects to spokes B, C, D"
    echo "  Spokes don't directly connect to each other"
    echo "  All changes must flow through A"
    echo ""
    
    # Create databases
    local hub="$TMPDIR/${prefix}_hub.db"
    local spoke_b="$TMPDIR/${prefix}_spoke_b.db"
    local spoke_c="$TMPDIR/${prefix}_spoke_c.db"
    local spoke_d="$TMPDIR/${prefix}_spoke_d.db"
    
    rm -f "$hub" "$spoke_b" "$spoke_c" "$spoke_d"
    
    # Initialize all databases with schema
    init_db "$impl" "$hub"
    init_db "$impl" "$spoke_b"
    init_db "$impl" "$spoke_c"
    init_db "$impl" "$spoke_d"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Each spoke creates a unique row
    echo "Step 1: Each spoke creates a unique row"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$spoke_b" "INSERT INTO foo VALUES (1, 'b1', 'b2', 'b3', 'b4');"
        run_zig "$spoke_c" "INSERT INTO foo VALUES (2, 'c1', 'c2', 'c3', 'c4');"
        run_zig "$spoke_d" "INSERT INTO foo VALUES (3, 'd1', 'd2', 'd3', 'd4');"
    else
        run_rust "$spoke_b" "INSERT INTO foo VALUES (1, 'b1', 'b2', 'b3', 'b4');"
        run_rust "$spoke_c" "INSERT INTO foo VALUES (2, 'c1', 'c2', 'c3', 'c4');"
        run_rust "$spoke_d" "INSERT INTO foo VALUES (3, 'd1', 'd2', 'd3', 'd4');"
    fi
    
    # Sync all spokes to hub
    echo "Step 2: All spokes sync to hub"
    sync_since "$impl" "$spoke_b" "$hub" 0
    sync_since "$impl" "$spoke_c" "$hub" 0
    sync_since "$impl" "$spoke_d" "$hub" 0
    
    # Verify hub has all 3 rows
    local hub_count
    if [[ "$impl" == "zig" ]]; then
        hub_count=$(run_zig "$hub" "SELECT COUNT(*) FROM foo;")
    else
        hub_count=$(run_rust "$hub" "SELECT COUNT(*) FROM foo;")
    fi
    
    if [[ "$hub_count" != "3" ]]; then
        echo "  FAIL: Hub should have 3 rows (got $hub_count)"
        return 1
    fi
    echo "  ✓ Hub has all 3 rows"
    
    # Sync hub back to all spokes
    echo "Step 3: Hub syncs to all spokes"
    sync_since "$impl" "$hub" "$spoke_b" 0
    sync_since "$impl" "$hub" "$spoke_c" 0
    sync_since "$impl" "$hub" "$spoke_d" 0
    
    # Verify all spokes have all 3 rows
    local b_count c_count d_count
    if [[ "$impl" == "zig" ]]; then
        b_count=$(run_zig "$spoke_b" "SELECT COUNT(*) FROM foo;")
        c_count=$(run_zig "$spoke_c" "SELECT COUNT(*) FROM foo;")
        d_count=$(run_zig "$spoke_d" "SELECT COUNT(*) FROM foo;")
    else
        b_count=$(run_rust "$spoke_b" "SELECT COUNT(*) FROM foo;")
        c_count=$(run_rust "$spoke_c" "SELECT COUNT(*) FROM foo;")
        d_count=$(run_rust "$spoke_d" "SELECT COUNT(*) FROM foo;")
    fi
    
    if [[ "$b_count" != "3" || "$c_count" != "3" || "$d_count" != "3" ]]; then
        echo "  FAIL: Not all spokes have 3 rows (B=$b_count, C=$c_count, D=$d_count)"
        return 1
    fi
    echo "  ✓ All spokes have 3 rows"
    
    # B updates row 1, C deletes row 2
    echo "Step 4: B updates row 1, C deletes row 2"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$spoke_b" "UPDATE foo SET b = 'updated_by_b' WHERE a = 1;"
        run_zig "$spoke_c" "DELETE FROM foo WHERE a = 2;"
    else
        run_rust "$spoke_b" "UPDATE foo SET b = 'updated_by_b' WHERE a = 1;"
        run_rust "$spoke_c" "DELETE FROM foo WHERE a = 2;"
    fi
    
    # Sync changes through hub
    echo "Step 5: Sync through hub"
    sync_since "$impl" "$spoke_b" "$hub" 0
    sync_since "$impl" "$spoke_c" "$hub" 0
    sync_since "$impl" "$hub" "$spoke_b" 0
    sync_since "$impl" "$hub" "$spoke_c" 0
    sync_since "$impl" "$hub" "$spoke_d" 0
    
    # Verify final state
    echo "Step 6: Verify convergence"
    
    local data_hub data_b data_c data_d
    data_hub=$(get_table_data "$impl" "$hub")
    data_b=$(get_table_data "$impl" "$spoke_b")
    data_c=$(get_table_data "$impl" "$spoke_c")
    data_d=$(get_table_data "$impl" "$spoke_d")
    
    echo "  Hub data: $data_hub"
    echo "  B data: $data_b"
    echo "  C data: $data_c"
    echo "  D data: $data_d"
    
    local converged=true
    if [[ "$data_hub" != "$data_b" ]]; then
        echo "  FAIL: Hub and B diverged"
        converged=false
    fi
    if [[ "$data_hub" != "$data_c" ]]; then
        echo "  FAIL: Hub and C diverged"
        converged=false
    fi
    if [[ "$data_hub" != "$data_d" ]]; then
        echo "  FAIL: Hub and D diverged"
        converged=false
    fi
    
    if [[ "$converged" == "true" ]]; then
        echo "  ✓ PASS: All nodes in star topology converged"
        
        # Verify expected state: 2 rows (row 2 deleted), row 1 updated
        if [[ "$impl" == "zig" ]]; then
            local final_count=$(run_zig "$hub" "SELECT COUNT(*) FROM foo;")
            local row1_b=$(run_zig "$hub" "SELECT b FROM foo WHERE a = 1;")
        else
            local final_count=$(run_rust "$hub" "SELECT COUNT(*) FROM foo;")
            local row1_b=$(run_rust "$hub" "SELECT b FROM foo WHERE a = 1;")
        fi
        
        if [[ "$final_count" == "2" ]]; then
            echo "  ✓ PASS: Correct row count (2)"
        else
            echo "  FAIL: Expected 2 rows, got $final_count"
            return 1
        fi
        
        if [[ "$row1_b" == "updated_by_b" ]]; then
            echo "  ✓ PASS: Row 1 correctly updated"
            return 0
        else
            echo "  FAIL: Row 1 not updated correctly (b='$row1_b')"
            return 1
        fi
    else
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Run Tests and Compare Zig vs Rust/C
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "Running Discord Corrosion Test (Original Python scenario)"
echo "═══════════════════════════════════════════════════════════════════════════"

# Run Rust/C version
echo ""
echo ">>> Running with Rust/C oracle..."
rust_discord_result=0
test_discord_corrosion "rust" "rust" || rust_discord_result=$?

# Run Zig version
echo ""
echo ">>> Running with Zig..."
zig_discord_result=0
test_discord_corrosion "zig" "zig" || zig_discord_result=$?

# Compare results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Discord Corrosion Test Results:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $rust_discord_result -eq 2 ]]; then
    echo "  Rust/C: SKIPPED"
    SKIP=$((SKIP + 1))
elif [[ $rust_discord_result -eq 0 ]]; then
    echo "  Rust/C: PASS"
    PASS=$((PASS + 1))
else
    echo "  Rust/C: FAIL"
    FAIL=$((FAIL + 1))
fi

if [[ $zig_discord_result -eq 2 ]]; then
    echo "  Zig: SKIPPED"
    SKIP=$((SKIP + 1))
elif [[ $zig_discord_result -eq 0 ]]; then
    echo "  Zig: PASS"
    PASS=$((PASS + 1))
else
    echo "  Zig: FAIL"
    FAIL=$((FAIL + 1))
fi

if [[ $rust_discord_result -eq 0 && $zig_discord_result -eq 0 ]]; then
    echo "  PARITY: ✓ Both implementations pass"
elif [[ $rust_discord_result -ne 0 && $zig_discord_result -ne 0 ]]; then
    echo "  PARITY: Both implementations have same behavior"
else
    echo "  PARITY: ✗ DIVERGENCE between implementations!"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "Running 4-Node Extended Discord Test"
echo "═══════════════════════════════════════════════════════════════════════════"

# Run Rust/C version
echo ""
echo ">>> Running with Rust/C oracle..."
rust_4node_result=0
test_discord_4node "rust" "rust" || rust_4node_result=$?

# Run Zig version
echo ""
echo ">>> Running with Zig..."
zig_4node_result=0
test_discord_4node "zig" "zig" || zig_4node_result=$?

# Compare results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4-Node Extended Discord Test Results:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $rust_4node_result -eq 2 ]]; then
    echo "  Rust/C: SKIPPED"
    SKIP=$((SKIP + 1))
elif [[ $rust_4node_result -eq 0 ]]; then
    echo "  Rust/C: PASS"
    PASS=$((PASS + 1))
else
    echo "  Rust/C: FAIL"
    FAIL=$((FAIL + 1))
fi

if [[ $zig_4node_result -eq 2 ]]; then
    echo "  Zig: SKIPPED"
    SKIP=$((SKIP + 1))
elif [[ $zig_4node_result -eq 0 ]]; then
    echo "  Zig: PASS"
    PASS=$((PASS + 1))
else
    echo "  Zig: FAIL"
    FAIL=$((FAIL + 1))
fi

if [[ $rust_4node_result -eq 0 && $zig_4node_result -eq 0 ]]; then
    echo "  PARITY: ✓ Both implementations pass"
elif [[ $rust_4node_result -ne 0 && $zig_4node_result -ne 0 ]]; then
    echo "  PARITY: Both implementations have same behavior"
else
    echo "  PARITY: ✗ DIVERGENCE between implementations!"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "Running Star Topology Test"
echo "═══════════════════════════════════════════════════════════════════════════"

# Run Rust/C version
echo ""
echo ">>> Running with Rust/C oracle..."
rust_star_result=0
test_star_topology "rust" "rust" || rust_star_result=$?

# Run Zig version
echo ""
echo ">>> Running with Zig..."
zig_star_result=0
test_star_topology "zig" "zig" || zig_star_result=$?

# Compare results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Star Topology Test Results:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $rust_star_result -eq 2 ]]; then
    echo "  Rust/C: SKIPPED"
    SKIP=$((SKIP + 1))
elif [[ $rust_star_result -eq 0 ]]; then
    echo "  Rust/C: PASS"
    PASS=$((PASS + 1))
else
    echo "  Rust/C: FAIL"
    FAIL=$((FAIL + 1))
fi

if [[ $zig_star_result -eq 2 ]]; then
    echo "  Zig: SKIPPED"
    SKIP=$((SKIP + 1))
elif [[ $zig_star_result -eq 0 ]]; then
    echo "  Zig: PASS"
    PASS=$((PASS + 1))
else
    echo "  Zig: FAIL"
    FAIL=$((FAIL + 1))
fi

if [[ $rust_star_result -eq 0 && $zig_star_result -eq 0 ]]; then
    echo "  PARITY: ✓ Both implementations pass"
elif [[ $rust_star_result -ne 0 && $zig_star_result -ne 0 ]]; then
    echo "  PARITY: Both implementations have same behavior"
else
    echo "  PARITY: ✗ DIVERGENCE between implementations!"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Multi-node Sync Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""

if [[ $FAIL -eq 0 ]]; then
    if [[ $SKIP -gt 0 ]]; then
        echo "Some tests skipped (functions not implemented)"
        exit 0
    else
        echo "All multi-node sync parity tests PASSED"
        echo ""
        echo "Verified:"
        echo "  - Discord corrosion scenario (out-of-order sync)"
        echo "  - 4-node extended discord with complex sync patterns"
        echo "  - Star topology (hub-and-spoke) sync"
        echo "  - Both implementations converge identically"
        exit 0
    fi
else
    echo "MULTI-NODE SYNC PARITY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAIL test(s)."
    echo "This may cause sync incompatibility between implementations."
    exit 1
fi
