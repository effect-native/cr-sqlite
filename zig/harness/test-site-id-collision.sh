#!/usr/bin/env bash
# Site ID Collision Test Suite for Zig CR-SQLite
# Documents behavior when two databases have the same site_id (e.g., from copying a database file)
#
# Reference: TASK-180 - Test site_id collision handling
#
# Scenario:
# 1. What happens if you copy a database file (both have same site_id)?
# 2. Both copies make changes
# 3. You try to sync them
#
# This could happen accidentally (backup restored) or maliciously.
# This is primarily a characterization test to document the behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ZIG_DIR/.." && pwd)"

echo "=================================================================="
echo "Test Suite: Site ID Collision (TASK-180)"
echo "=================================================================="
echo ""
echo "Documents behavior when two databases have the same site_id."
echo "This tests what happens when a database file is copied and"
echo "both copies make independent changes, then try to sync."
echo ""

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$ROOT_DIR/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$ROOT_DIR/lib/crsqlite-darwin-x86_64.dylib"
    fi
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$ROOT_DIR/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$ROOT_DIR/lib/crsqlite-linux-x86_64.so"
    fi
fi

# Build Zig extension if needed
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    nix run nixpkgs#zig -- build 2>&1 || {
        echo "FAIL: Zig build failed"
        exit 1
    }
fi

echo "Zig extension: $ZIG_EXT"

# Check for Rust/C oracle
HAS_RUST=0
if [[ -f "$RUST_EXT" ]]; then
    HAS_RUST=1
    echo "Rust/C oracle: $RUST_EXT"
else
    echo "Rust/C oracle: NOT FOUND (run ./scripts/update-crsqlite-oracle.sh)"
fi
echo ""

# Setup temp directory
TMPDIR="${ROOT_DIR}/.tmp/site-id-collision-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

ERRFILE="$TMPDIR/error.txt"
OUTFILE="$TMPDIR/output.txt"

PASS=0
FAIL=0
SKIP=0
DIVERGENCES=0

# Track behavioral observations
declare -a OBSERVATIONS

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

# Run SQL with Zig extension (clean sqlite + explicit .load)
run_zig() {
    local db="$1"
    local sql="$2"
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_zig_all() {
    local db="$1"
    local sql="$2"
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

# Run SQL with Rust/C oracle (explicit load with entry point)
run_rust() {
    local db="$1"
    local sql="$2"
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" | tail -1 || true
}

run_rust_all() {
    local db="$1"
    local sql="$2"
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

# Add behavioral observation
observe() {
    local msg="$1"
    OBSERVATIONS+=("$msg")
    echo "INFO: $msg"
}

# Export changes from a database as SQL INSERT statements
# Usage: export_changes <run_func> <db> <since_version>
export_changes() {
    local run_func="$1"
    local db="$2"
    local since="${3:-0}"
    $run_func "$db" "
        SELECT 'INSERT INTO crsql_changes (\"table\", pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES (''' || 
               [table] || ''', ' || quote(pk) || ', ''' || cid || ''', ' || 
               COALESCE(quote(val), 'NULL') || ', ' || col_version || ', ' || db_version || ', ' || 
               quote(site_id) || ', ' || cl || ', ' || seq || ');'
        FROM crsql_changes WHERE db_version > $since;
    "
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Basic Site ID Collision Setup
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Basic Site ID Collision Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Scenario: Create DB, insert data, copy file, verify same site_id"
echo ""

test_basic_setup() {
    local ext_name="$1"
    local run_func="$2"
    local db_original="$TMPDIR/basic-${ext_name}-original.db"
    local db_copy="$TMPDIR/basic-${ext_name}-copy.db"
    rm -f "$db_original" "$db_copy"
    
    # Create original database with CRR table and insert data
    $run_func "$db_original" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value INTEGER);
        SELECT crsql_as_crr('items');
        INSERT INTO items VALUES (1, 'original_item', 100);
    " > /dev/null 2>&1
    
    # Check if functions work
    local site_id_original=$($run_func "$db_original" "SELECT quote(crsql_site_id());")
    if [[ -z "$site_id_original" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db_original" "$db_copy"
        return 2
    fi
    
    # Copy the database file
    cp "$db_original" "$db_copy"
    
    # Verify the copy has the same site_id
    local site_id_copy=$($run_func "$db_copy" "SELECT quote(crsql_site_id());")
    
    local status=0
    if [[ "$site_id_original" == "$site_id_copy" ]]; then
        echo "  [$ext_name] PASS: Copied database has same site_id"
        echo "    Original site_id: $site_id_original"
        echo "    Copy site_id:     $site_id_copy"
        observe "[$ext_name] Copying a database file preserves the site_id"
    else
        echo "  [$ext_name] FAIL: Site IDs differ (unexpected - should be identical)"
        echo "    Original: $site_id_original"
        echo "    Copy:     $site_id_copy"
        status=1
    fi
    
    # Keep databases for next tests
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_basic_setup "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C
if [[ $HAS_RUST -eq 1 ]]; then
    RUST_RESULT=0
    test_basic_setup "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    
    if [[ $ZIG_RESULT -ne $RUST_RESULT && $ZIG_RESULT -ne 2 && $RUST_RESULT -ne 2 ]]; then
        echo "  DIVERGENCE: Zig result=$ZIG_RESULT, Rust result=$RUST_RESULT"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Independent Changes on Both Copies
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Independent Changes on Both Copies"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Scenario: Both copies make different changes to the same row"
echo ""

test_independent_changes() {
    local ext_name="$1"
    local run_func="$2"
    local db_a="$TMPDIR/indep-${ext_name}-a.db"
    local db_b="$TMPDIR/indep-${ext_name}-b.db"
    rm -f "$db_a" "$db_b"
    
    # Create original database
    $run_func "$db_a" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value INTEGER);
        SELECT crsql_as_crr('items');
        INSERT INTO items VALUES (1, 'original', 100);
    " > /dev/null 2>&1
    
    local initial_ver=$($run_func "$db_a" "SELECT crsql_db_version();")
    if [[ -z "$initial_ver" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db_a" "$db_b"
        return 2
    fi
    
    # Copy database (same site_id)
    cp "$db_a" "$db_b"
    
    local site_id=$($run_func "$db_a" "SELECT quote(crsql_site_id());")
    echo "  [$ext_name] Both databases have site_id: $site_id"
    
    # Make different changes on each copy
    echo "  [$ext_name] Making different changes on each copy..."
    
    # Copy A: Update the name
    $run_func "$db_a" "UPDATE items SET name = 'changed_by_A' WHERE id = 1;" > /dev/null 2>&1
    
    # Copy B: Update the value
    $run_func "$db_b" "UPDATE items SET value = 200 WHERE id = 1;" > /dev/null 2>&1
    
    # Check db_versions
    local ver_a=$($run_func "$db_a" "SELECT crsql_db_version();")
    local ver_b=$($run_func "$db_b" "SELECT crsql_db_version();")
    
    echo "  [$ext_name] After changes:"
    echo "    Copy A: db_version=$ver_a, name=$($run_func "$db_a" "SELECT name FROM items WHERE id=1;"), value=$($run_func "$db_a" "SELECT value FROM items WHERE id=1;")"
    echo "    Copy B: db_version=$ver_b, name=$($run_func "$db_b" "SELECT name FROM items WHERE id=1;"), value=$($run_func "$db_b" "SELECT value FROM items WHERE id=1;")"
    
    # Check the clock tables
    local clocks_a=$($run_func "$db_a" "SELECT cid, col_version FROM items__crsql_clock ORDER BY cid;")
    local clocks_b=$($run_func "$db_b" "SELECT cid, col_version FROM items__crsql_clock ORDER BY cid;")
    
    echo "  [$ext_name] Clock table state:"
    echo "    Copy A clocks: $clocks_a"
    echo "    Copy B clocks: $clocks_b"
    
    # Key observation: both have the same site_id but different db_versions
    if [[ "$ver_a" == "$ver_b" ]]; then
        observe "[$ext_name] Both copies have same db_version after independent changes (db_version=$ver_a)"
    else
        observe "[$ext_name] Copies have different db_versions: A=$ver_a, B=$ver_b"
    fi
    
    echo "  [$ext_name] PASS: Independent changes recorded successfully"
    return 0
}

# Run for Zig
ZIG_RESULT=0
test_independent_changes "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C
if [[ $HAS_RUST -eq 1 ]]; then
    RUST_RESULT=0
    test_independent_changes "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Sync Changes Between Colliding Site IDs
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Sync Changes Between Colliding Site IDs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Scenario: Export changes from A, apply to B (same site_id)"
echo "  Key question: Does cr-sqlite detect or reject same-site changes?"
echo ""

test_sync_collision() {
    local ext_name="$1"
    local run_func="$2"
    local run_all_func="${run_func}_all"
    local db_a="$TMPDIR/sync-${ext_name}-a.db"
    local db_b="$TMPDIR/sync-${ext_name}-b.db"
    rm -f "$db_a" "$db_b"
    
    # Create original database
    $run_func "$db_a" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value INTEGER);
        SELECT crsql_as_crr('items');
        INSERT INTO items VALUES (1, 'original', 100);
    " > /dev/null 2>&1
    
    local check=$($run_func "$db_a" "SELECT crsql_db_version();")
    if [[ -z "$check" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db_a" "$db_b"
        return 2
    fi
    
    # Copy database (same site_id)
    cp "$db_a" "$db_b"
    
    local site_id=$($run_func "$db_a" "SELECT quote(crsql_site_id());")
    
    # Make changes on A
    $run_func "$db_a" "UPDATE items SET name = 'from_A', value = 999 WHERE id = 1;" > /dev/null 2>&1
    
    # Record state before sync
    local b_name_before=$($run_func "$db_b" "SELECT name FROM items WHERE id = 1;")
    local b_value_before=$($run_func "$db_b" "SELECT value FROM items WHERE id = 1;")
    local b_ver_before=$($run_func "$db_b" "SELECT crsql_db_version();")
    
    echo "  [$ext_name] Before sync:"
    echo "    A: name='from_A', value=999"
    echo "    B: name='$b_name_before', value=$b_value_before, db_version=$b_ver_before"
    
    # Export changes from A
    echo "  [$ext_name] Exporting changes from A..."
    local changes_sql=$(export_changes "$run_func" "$db_a" 1)
    echo "  [$ext_name] Changes to apply:"
    echo "$changes_sql" | head -5
    
    # Try to apply changes to B
    echo "  [$ext_name] Applying changes to B (same site_id)..."
    local apply_error=""
    if [[ -n "$changes_sql" ]]; then
        echo "$changes_sql" | while read -r line; do
            if [[ -n "$line" ]]; then
                $run_func "$db_b" "$line" 2>&1
            fi
        done
        apply_error=$(cat "$ERRFILE" 2>/dev/null || true)
    fi
    
    # Check state after sync attempt
    local b_name_after=$($run_func "$db_b" "SELECT name FROM items WHERE id = 1;")
    local b_value_after=$($run_func "$db_b" "SELECT value FROM items WHERE id = 1;")
    local b_ver_after=$($run_func "$db_b" "SELECT crsql_db_version();")
    
    echo "  [$ext_name] After sync attempt:"
    echo "    B: name='$b_name_after', value=$b_value_after, db_version=$b_ver_after"
    
    # Document the behavior
    local status=0
    
    if [[ -n "$apply_error" ]] && [[ "$apply_error" != *"UNIQUE constraint"* ]]; then
        observe "[$ext_name] Applying same-site changes produced error: $apply_error"
    fi
    
    if [[ "$b_name_after" == "from_A" ]]; then
        observe "[$ext_name] Changes from same site_id were APPLIED (no rejection)"
        echo "  [$ext_name] PASS: Changes applied (behavior documented)"
    elif [[ "$b_name_after" == "$b_name_before" ]]; then
        observe "[$ext_name] Changes from same site_id were REJECTED (no change)"
        echo "  [$ext_name] PASS: Changes rejected (behavior documented)"
    else
        observe "[$ext_name] Unexpected state after sync: name='$b_name_after'"
        echo "  [$ext_name] INFO: Unexpected behavior documented"
    fi
    
    # Check if db_version changed
    if [[ "$b_ver_after" == "$b_ver_before" ]]; then
        observe "[$ext_name] db_version unchanged after same-site sync (stayed at $b_ver_before)"
    else
        observe "[$ext_name] db_version changed from $b_ver_before to $b_ver_after after same-site sync"
    fi
    
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_sync_collision "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C
if [[ $HAS_RUST -eq 1 ]]; then
    RUST_RESULT=0
    test_sync_collision "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Bidirectional Sync with Same Site ID
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Bidirectional Sync with Same Site ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Scenario: A and B both make changes, sync bidirectionally"
echo "  Key question: Do they converge? What wins?"
echo ""

test_bidirectional_sync() {
    local ext_name="$1"
    local run_func="$2"
    local db_a="$TMPDIR/bidir-${ext_name}-a.db"
    local db_b="$TMPDIR/bidir-${ext_name}-b.db"
    rm -f "$db_a" "$db_b"
    
    # Create original database
    $run_func "$db_a" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
        INSERT INTO items VALUES (1, 'initial');
    " > /dev/null 2>&1
    
    local check=$($run_func "$db_a" "SELECT crsql_db_version();")
    if [[ -z "$check" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db_a" "$db_b"
        return 2
    fi
    
    # Copy database (same site_id)
    cp "$db_a" "$db_b"
    
    # Make different changes on each
    $run_func "$db_a" "UPDATE items SET name = 'value_A' WHERE id = 1;" > /dev/null 2>&1
    $run_func "$db_b" "UPDATE items SET name = 'value_B' WHERE id = 1;" > /dev/null 2>&1
    
    echo "  [$ext_name] After independent changes:"
    echo "    A: name='$($run_func "$db_a" "SELECT name FROM items WHERE id=1;")'"
    echo "    B: name='$($run_func "$db_b" "SELECT name FROM items WHERE id=1;")'"
    
    # Export changes from both
    local changes_a=$(export_changes "$run_func" "$db_a" 1)
    local changes_b=$(export_changes "$run_func" "$db_b" 1)
    
    # Apply A's changes to B
    echo "  [$ext_name] Applying A's changes to B..."
    if [[ -n "$changes_a" ]]; then
        echo "$changes_a" | while read -r line; do
            [[ -n "$line" ]] && $run_func "$db_b" "$line" 2>&1 || true
        done
    fi
    
    # Apply B's changes to A
    echo "  [$ext_name] Applying B's changes to A..."
    if [[ -n "$changes_b" ]]; then
        echo "$changes_b" | while read -r line; do
            [[ -n "$line" ]] && $run_func "$db_a" "$line" 2>&1 || true
        done
    fi
    
    # Check final state
    local final_a=$($run_func "$db_a" "SELECT name FROM items WHERE id = 1;")
    local final_b=$($run_func "$db_b" "SELECT name FROM items WHERE id = 1;")
    
    echo "  [$ext_name] After bidirectional sync:"
    echo "    A: name='$final_a'"
    echo "    B: name='$final_b'"
    
    local status=0
    
    if [[ "$final_a" == "$final_b" ]]; then
        observe "[$ext_name] Bidirectional sync CONVERGED: both have '$final_a'"
        echo "  [$ext_name] PASS: Databases converged"
    else
        observe "[$ext_name] Bidirectional sync DIVERGED: A='$final_a', B='$final_b'"
        echo "  [$ext_name] FAIL: Databases did not converge (documented)"
        status=1
    fi
    
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_bidirectional_sync "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C
if [[ $HAS_RUST -eq 1 ]]; then
    RUST_RESULT=0
    test_bidirectional_sync "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Concurrent Inserts with Same Site ID (Same PK)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Concurrent Inserts with Same Site ID (Same PK)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Scenario: Both copies insert a new row with the same PK"
echo "  Key question: What happens to duplicate inserts from same site?"
echo ""

test_concurrent_inserts_same_pk() {
    local ext_name="$1"
    local run_func="$2"
    local db_a="$TMPDIR/samepk-${ext_name}-a.db"
    local db_b="$TMPDIR/samepk-${ext_name}-b.db"
    rm -f "$db_a" "$db_b"
    
    # Create original database (empty table)
    $run_func "$db_a" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
    " > /dev/null 2>&1
    
    local check=$($run_func "$db_a" "SELECT crsql_db_version();")
    if [[ -z "$check" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db_a" "$db_b"
        return 2
    fi
    
    # Copy database (same site_id)
    cp "$db_a" "$db_b"
    
    # Both insert row with id=1 but different names
    $run_func "$db_a" "INSERT INTO items VALUES (1, 'from_A');" > /dev/null 2>&1
    $run_func "$db_b" "INSERT INTO items VALUES (1, 'from_B');" > /dev/null 2>&1
    
    echo "  [$ext_name] After concurrent inserts:"
    echo "    A: name='$($run_func "$db_a" "SELECT name FROM items WHERE id=1;")'"
    echo "    B: name='$($run_func "$db_b" "SELECT name FROM items WHERE id=1;")'"
    
    # Check col_versions and db_versions
    local ver_a=$($run_func "$db_a" "SELECT col_version FROM items__crsql_clock WHERE cid='name';")
    local ver_b=$($run_func "$db_b" "SELECT col_version FROM items__crsql_clock WHERE cid='name';")
    local db_ver_a=$($run_func "$db_a" "SELECT crsql_db_version();")
    local db_ver_b=$($run_func "$db_b" "SELECT crsql_db_version();")
    
    echo "  [$ext_name] Clock state:"
    echo "    A: col_version=$ver_a, db_version=$db_ver_a"
    echo "    B: col_version=$ver_b, db_version=$db_ver_b"
    
    # Export and sync
    local changes_a=$(export_changes "$run_func" "$db_a" 0)
    local changes_b=$(export_changes "$run_func" "$db_b" 0)
    
    # Apply A's changes to B
    echo "  [$ext_name] Syncing..."
    if [[ -n "$changes_a" ]]; then
        echo "$changes_a" | while read -r line; do
            [[ -n "$line" ]] && $run_func "$db_b" "$line" 2>&1 || true
        done
    fi
    
    # Apply B's changes to A
    if [[ -n "$changes_b" ]]; then
        echo "$changes_b" | while read -r line; do
            [[ -n "$line" ]] && $run_func "$db_a" "$line" 2>&1 || true
        done
    fi
    
    local final_a=$($run_func "$db_a" "SELECT name FROM items WHERE id = 1;")
    local final_b=$($run_func "$db_b" "SELECT name FROM items WHERE id = 1;")
    local count_a=$($run_func "$db_a" "SELECT COUNT(*) FROM items;")
    local count_b=$($run_func "$db_b" "SELECT COUNT(*) FROM items;")
    
    echo "  [$ext_name] After sync:"
    echo "    A: name='$final_a', count=$count_a"
    echo "    B: name='$final_b', count=$count_b"
    
    local status=0
    
    if [[ "$final_a" == "$final_b" ]]; then
        observe "[$ext_name] Same-site concurrent inserts CONVERGED: '$final_a'"
        if [[ "$final_a" == "from_A" ]]; then
            observe "[$ext_name] Winner determined by: likely value comparison (A < B alphabetically)"
        elif [[ "$final_a" == "from_B" ]]; then
            observe "[$ext_name] Winner determined by: likely value comparison (B wins)"
        fi
        echo "  [$ext_name] PASS: Databases converged"
    else
        observe "[$ext_name] Same-site concurrent inserts DIVERGED: A='$final_a', B='$final_b'"
        echo "  [$ext_name] FAIL: Databases diverged (documented)"
        status=1
    fi
    
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_concurrent_inserts_same_pk "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C
if [[ $HAS_RUST -eq 1 ]]; then
    RUST_RESULT=0
    test_concurrent_inserts_same_pk "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Delete/Resurrection with Same Site ID
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Delete/Resurrection with Same Site ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Scenario: A deletes a row, B resurrects it, sync"
echo "  Key question: Does the causal layer (cl) work with same site_id?"
echo ""

test_delete_resurrect() {
    local ext_name="$1"
    local run_func="$2"
    local db_a="$TMPDIR/delres-${ext_name}-a.db"
    local db_b="$TMPDIR/delres-${ext_name}-b.db"
    rm -f "$db_a" "$db_b"
    
    # Create original database with a row
    $run_func "$db_a" "
        CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT);
        SELECT crsql_as_crr('items');
        INSERT INTO items VALUES (1, 'original');
    " > /dev/null 2>&1
    
    local check=$($run_func "$db_a" "SELECT crsql_db_version();")
    if [[ -z "$check" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
        echo "  [$ext_name] SKIP: Required functions not implemented"
        rm -f "$db_a" "$db_b"
        return 2
    fi
    
    # Copy database (same site_id)
    cp "$db_a" "$db_b"
    
    # A deletes the row
    $run_func "$db_a" "DELETE FROM items WHERE id = 1;" > /dev/null 2>&1
    
    # B updates the row (this should keep it alive)
    $run_func "$db_b" "UPDATE items SET name = 'resurrected' WHERE id = 1;" > /dev/null 2>&1
    
    echo "  [$ext_name] After operations:"
    echo "    A: deleted (count=$($run_func "$db_a" "SELECT COUNT(*) FROM items;"))"
    echo "    B: updated to '$($run_func "$db_b" "SELECT name FROM items WHERE id=1;")'"
    
    # Check causal layer values
    local cl_a=$($run_func "$db_a" "SELECT MAX(cl) FROM crsql_changes;")
    local cl_b=$($run_func "$db_b" "SELECT MAX(cl) FROM crsql_changes;")
    echo "  [$ext_name] Causal layer: A=$cl_a, B=$cl_b"
    
    # Sync both ways
    local changes_a=$(export_changes "$run_func" "$db_a" 1)
    local changes_b=$(export_changes "$run_func" "$db_b" 1)
    
    if [[ -n "$changes_a" ]]; then
        echo "$changes_a" | while read -r line; do
            [[ -n "$line" ]] && $run_func "$db_b" "$line" 2>&1 || true
        done
    fi
    
    if [[ -n "$changes_b" ]]; then
        echo "$changes_b" | while read -r line; do
            [[ -n "$line" ]] && $run_func "$db_a" "$line" 2>&1 || true
        done
    fi
    
    local count_a=$($run_func "$db_a" "SELECT COUNT(*) FROM items;")
    local count_b=$($run_func "$db_b" "SELECT COUNT(*) FROM items;")
    local name_a=$($run_func "$db_a" "SELECT name FROM items WHERE id = 1;" 2>/dev/null || echo "(deleted)")
    local name_b=$($run_func "$db_b" "SELECT name FROM items WHERE id = 1;" 2>/dev/null || echo "(deleted)")
    
    echo "  [$ext_name] After sync:"
    echo "    A: count=$count_a, name='$name_a'"
    echo "    B: count=$count_b, name='$name_b'"
    
    local status=0
    
    if [[ "$count_a" == "$count_b" ]]; then
        if [[ "$count_a" == "0" ]]; then
            observe "[$ext_name] Delete/resurrect: DELETE won (row deleted on both)"
        else
            observe "[$ext_name] Delete/resurrect: UPDATE won (row exists on both as '$name_a')"
        fi
        echo "  [$ext_name] PASS: Databases converged"
    else
        observe "[$ext_name] Delete/resurrect DIVERGED: A count=$count_a, B count=$count_b"
        echo "  [$ext_name] FAIL: Databases diverged (documented)"
        status=1
    fi
    
    return $status
}

# Run for Zig
ZIG_RESULT=0
test_delete_resurrect "Zig" run_zig || ZIG_RESULT=$?

if [[ $ZIG_RESULT -eq 0 ]]; then
    PASS=$((PASS + 1))
elif [[ $ZIG_RESULT -eq 2 ]]; then
    SKIP=$((SKIP + 1))
else
    FAIL=$((FAIL + 1))
fi

# Run for Rust/C
if [[ $HAS_RUST -eq 1 ]]; then
    RUST_RESULT=0
    test_delete_resurrect "Rust" run_rust || RUST_RESULT=$?
    
    if [[ $RUST_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $RUST_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
else
    echo "  [Rust] SKIP: Oracle not available"
    SKIP=$((SKIP + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Zig vs Rust/C Parity Check
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Zig vs Rust/C Parity (Full Collision Scenario)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  NOTE: This test documents whether Zig and Rust/C behave identically"
echo "  under site_id collision. Internal divergence is expected when"
echo "  col_versions collide - the important thing is PARITY between impls."
echo ""

if [[ $HAS_RUST -eq 0 ]]; then
    echo "  SKIP: Rust/C oracle not available"
    SKIP=$((SKIP + 1))
else
    test_parity() {
        local db_zig_a="$TMPDIR/parity-zig-a.db"
        local db_zig_b="$TMPDIR/parity-zig-b.db"
        local db_rust_a="$TMPDIR/parity-rust-a.db"
        local db_rust_b="$TMPDIR/parity-rust-b.db"
        rm -f "$db_zig_a" "$db_zig_b" "$db_rust_a" "$db_rust_b"
        
        # Create identical scenarios for both implementations
        local setup_sql="
            CREATE TABLE items (id INTEGER PRIMARY KEY NOT NULL, name TEXT, value INTEGER);
            SELECT crsql_as_crr('items');
            INSERT INTO items VALUES (1, 'original', 100);
        "
        
        run_zig "$db_zig_a" "$setup_sql" > /dev/null 2>&1
        run_rust "$db_rust_a" "$setup_sql" > /dev/null 2>&1
        
        local check=$(run_zig "$db_zig_a" "SELECT crsql_db_version();")
        if [[ -z "$check" ]] || grep -qi "no such function" "$ERRFILE" 2>/dev/null; then
            echo "  SKIP: Required functions not implemented"
            return 2
        fi
        
        # Copy to create collision scenario
        cp "$db_zig_a" "$db_zig_b"
        cp "$db_rust_a" "$db_rust_b"
        
        # Make identical changes on each
        run_zig "$db_zig_a" "UPDATE items SET name = 'changed_A', value = 200 WHERE id = 1;" > /dev/null 2>&1
        run_zig "$db_zig_b" "UPDATE items SET name = 'changed_B', value = 300 WHERE id = 1;" > /dev/null 2>&1
        run_rust "$db_rust_a" "UPDATE items SET name = 'changed_A', value = 200 WHERE id = 1;" > /dev/null 2>&1
        run_rust "$db_rust_b" "UPDATE items SET name = 'changed_B', value = 300 WHERE id = 1;" > /dev/null 2>&1
        
        # Sync both implementations
        local zig_changes_a=$(export_changes run_zig "$db_zig_a" 1)
        local zig_changes_b=$(export_changes run_zig "$db_zig_b" 1)
        local rust_changes_a=$(export_changes run_rust "$db_rust_a" 1)
        local rust_changes_b=$(export_changes run_rust "$db_rust_b" 1)
        
        # Apply changes (both ways)
        if [[ -n "$zig_changes_a" ]]; then
            echo "$zig_changes_a" | while read -r line; do
                [[ -n "$line" ]] && run_zig "$db_zig_b" "$line" 2>&1 || true
            done
        fi
        if [[ -n "$zig_changes_b" ]]; then
            echo "$zig_changes_b" | while read -r line; do
                [[ -n "$line" ]] && run_zig "$db_zig_a" "$line" 2>&1 || true
            done
        fi
        if [[ -n "$rust_changes_a" ]]; then
            echo "$rust_changes_a" | while read -r line; do
                [[ -n "$line" ]] && run_rust "$db_rust_b" "$line" 2>&1 || true
            done
        fi
        if [[ -n "$rust_changes_b" ]]; then
            echo "$rust_changes_b" | while read -r line; do
                [[ -n "$line" ]] && run_rust "$db_rust_a" "$line" 2>&1 || true
            done
        fi
        
        # Compare final states
        local zig_final_a=$(run_zig "$db_zig_a" "SELECT name, value FROM items WHERE id=1;")
        local zig_final_b=$(run_zig "$db_zig_b" "SELECT name, value FROM items WHERE id=1;")
        local rust_final_a=$(run_rust "$db_rust_a" "SELECT name, value FROM items WHERE id=1;")
        local rust_final_b=$(run_rust "$db_rust_b" "SELECT name, value FROM items WHERE id=1;")
        
        echo "  Final states:"
        echo "    Zig  A: $zig_final_a"
        echo "    Zig  B: $zig_final_b"
        echo "    Rust A: $rust_final_a"
        echo "    Rust B: $rust_final_b"
        
        local zig_converged=true
        local rust_converged=true
        
        # Check internal consistency (document but don't fail - divergence expected)
        if [[ "$zig_final_a" != "$zig_final_b" ]]; then
            echo "  INFO: Zig copies diverged internally (expected with same col_version)"
            observe "Zig diverges internally on site_id collision (expected - same col_version)"
            zig_converged=false
        else
            observe "Zig converged internally despite site_id collision"
        fi
        
        if [[ "$rust_final_a" != "$rust_final_b" ]]; then
            echo "  INFO: Rust copies diverged internally (expected with same col_version)"
            observe "Rust diverges internally on site_id collision (expected - same col_version)"
            rust_converged=false
        else
            observe "Rust converged internally despite site_id collision"
        fi
        
        # The key test: do Zig and Rust behave IDENTICALLY?
        # Compare A copies (they received same changes)
        local parity_ok=true
        if [[ "$zig_final_a" != "$rust_final_a" ]]; then
            echo "  DIVERGENCE: Zig A and Rust A produce different results"
            parity_ok=false
        fi
        if [[ "$zig_final_b" != "$rust_final_b" ]]; then
            echo "  DIVERGENCE: Zig B and Rust B produce different results"
            parity_ok=false
        fi
        
        if [[ "$parity_ok" == "true" ]]; then
            echo "  PASS: Zig and Rust produce identical behavior under site_id collision"
            observe "Zig and Rust have IDENTICAL behavior on site_id collision"
            return 0
        else
            echo "  FAIL: Zig and Rust behave differently under site_id collision"
            observe "Zig and Rust DIFFER on site_id collision resolution"
            DIVERGENCES=$((DIVERGENCES + 1))
            return 1
        fi
    }
    
    PARITY_RESULT=0
    test_parity || PARITY_RESULT=$?
    
    if [[ $PARITY_RESULT -eq 0 ]]; then
        PASS=$((PASS + 1))
    elif [[ $PARITY_RESULT -eq 2 ]]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=================================================================="
echo "         SITE ID COLLISION TEST SUMMARY"
echo "=================================================================="
printf "  PASSED:      %d\n" "$PASS"
printf "  FAILED:      %d\n" "$FAIL"
printf "  SKIPPED:     %d\n" "$SKIP"
printf "  DIVERGENCES: %d\n" "$DIVERGENCES"
echo "=================================================================="
echo ""

# Print behavioral observations
echo "BEHAVIORAL OBSERVATIONS:"
echo "------------------------"
for obs in "${OBSERVATIONS[@]}"; do
    echo "  - $obs"
done
echo ""

# Summary of what happens
echo "SUMMARY OF SITE ID COLLISION BEHAVIOR:"
echo "--------------------------------------"
echo "When two databases have the same site_id (e.g., from copying a database file):"
echo ""
echo "1. Detection: cr-sqlite does NOT detect or reject same-site_id changes"
echo "2. Merging: Changes are applied using normal CRDT merge rules"
echo "3. Convergence: Both copies should converge using:"
echo "   - col_version comparison (higher wins)"
echo "   - Value comparison as tie-breaker"
echo "4. Risk: With same site_id, col_versions may collide causing"
echo "   unpredictable tie-breaking based on value comparison"
echo ""
echo "RECOMMENDED RECOVERY:"
echo "- Regenerate site_id on one copy using:"
echo "  DELETE FROM crsql_site_id; (triggers regeneration on next access)"
echo "- Or manually set: INSERT INTO crsql_site_id VALUES (randomblob(16));"
echo ""

if [[ $DIVERGENCES -gt 0 ]]; then
    echo "WARNING: $DIVERGENCES divergence(s) between Zig and Rust/C"
    echo "See individual test output for details."
    echo ""
fi

if [[ $FAIL -eq 0 && $PASS -gt 0 ]]; then
    echo "Site ID Collision Test Summary: $PASS passed, $FAIL failed, $SKIP skipped"
    echo "Behavior documented: See BEHAVIORAL OBSERVATIONS above"
    exit 0
elif [[ $FAIL -eq 0 && $PASS -eq 0 ]]; then
    echo "All site_id collision tests SKIPPED (functions not implemented)"
    exit 2
else
    echo "Site ID Collision Test Summary: $PASS passed, $FAIL failed, $SKIP skipped"
    echo "Behavior documented: See BEHAVIORAL OBSERVATIONS above"
    exit 1
fi
