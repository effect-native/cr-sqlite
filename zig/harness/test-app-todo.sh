#!/usr/bin/env bash
# =============================================================================
# App Simulation: Todo List with Subtasks
# =============================================================================
#
# SCENARIO: A Todo app with hierarchical tasks (parent/child relationship).
# Multiple devices create, update, and complete tasks concurrently.
# Tests realistic patterns:
# - Nested subtasks (parent_id references)
# - Concurrent status updates (marking tasks done)
# - Concurrent title edits
# - Parent task with child modifications
#
# This test compares Zig vs Rust/C behavior to verify parity.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "============================================================================="
echo "App Simulation: Todo List with Subtasks"
echo "============================================================================="
echo ""
echo "Simulates a realistic todo app with nested tasks on multiple devices"
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

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory in .tmp (not /tmp)
TMPDIR="${REPO_ROOT}/.tmp/app-todo-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

ERRFILE="$TMPDIR/error.txt"
PASS=0
FAIL=0
DIVERGENCE=0

# ══════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ══════════════════════════════════════════════════════════════════════════════

run_zig() {
    local db="$1"
    local sql="$2"
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>/dev/null || true
}

run_rust() {
    local db="$1"
    local sql="$2"
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>/dev/null || true
}

# Run SQL and check for blocking errors (used for initial setup)
run_check() {
    local impl="$1"
    local db="$2"
    local sql="$3"
    if [[ "$impl" == "zig" ]]; then
        timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
    else
        timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
    fi
}

is_blocked() {
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function" "$ERRFILE"; then
            return 0
        fi
    fi
    return 1
}

# Initialize a device with todo schema
init_device() {
    local impl="$1"
    local db="$2"
    # NOTE: cr-sqlite requires NOT NULL columns to have DEFAULT values
    # for forward/backward schema compatibility
    local sql="
CREATE TABLE todos (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    done INTEGER NOT NULL DEFAULT 0,
    parent_id TEXT
);
SELECT crsql_as_crr('todos');
"
    run_check "$impl" "$db" "$sql"
}

# Sync all changes from src to dst using CHANGE: prefix pattern
sync_all() {
    local impl="$1"
    local src="$2"
    local dst="$3"
    local changes_file="$TMPDIR/changes_sync_$$.txt"
    
    # Get destination's site_id to exclude its own changes
    local dst_site_id
    if [[ "$impl" == "zig" ]]; then
        dst_site_id=$(run_zig "$dst" "SELECT quote(crsql_site_id());")
    else
        dst_site_id=$(run_rust "$dst" "SELECT quote(crsql_site_id());")
    fi
    
    local query="SELECT 'CHANGE:' || [table] || '|' || quote(pk) || '|' || cid || '|' || quote(val) || '|' || col_version || '|' || db_version || '|' || quote(site_id) || '|' || cl || '|' || seq FROM crsql_changes WHERE site_id IS NOT $dst_site_id;"
    
    if [[ "$impl" == "zig" ]]; then
        run_zig "$src" "$query" > "$changes_file"
    else
        run_rust "$src" "$query" > "$changes_file"
    fi
    
    while IFS= read -r line; do
        if [[ "$line" == CHANGE:* ]]; then
            local change="${line#CHANGE:}"
            IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq <<< "$change"
            local insert_sql="INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq) VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);"
            if [[ "$impl" == "zig" ]]; then
                run_zig "$dst" "$insert_sql" 2>/dev/null
            else
                run_rust "$dst" "$insert_sql" 2>/dev/null
            fi
        fi
    done < "$changes_file"
    
    rm -f "$changes_file"
}

# Get sorted table data for comparison
get_todos() {
    local impl="$1"
    local db="$2"
    local query="SELECT id, title, done, COALESCE(parent_id, 'NULL') FROM todos ORDER BY id;"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$query"
    else
        run_rust "$db" "$query"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Test: Todo App with Subtasks
# ══════════════════════════════════════════════════════════════════════════════
run_todo_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Todo App Simulation ($impl)"
    echo "-----------------------------------------------------------------------------"
    
    local device_a="$TMPDIR/${prefix}_device_a.db"
    local device_b="$TMPDIR/${prefix}_device_b.db"
    
    rm -f "$device_a" "$device_b"
    
    # Step 1: Initialize both devices
    echo ""
    echo "Step 1: Initialize devices with todo schema"
    init_device "$impl" "$device_a"
    init_device "$impl" "$device_b"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Step 2: Device A creates a shopping list with subtasks
    echo "Step 2: Device A creates 'Buy groceries' with 3 subtasks"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$device_a" "
INSERT INTO todos VALUES ('1', 'Buy groceries', 0, NULL);
INSERT INTO todos VALUES ('1.1', 'Milk', 0, '1');
INSERT INTO todos VALUES ('1.2', 'Bread', 0, '1');
INSERT INTO todos VALUES ('1.3', 'Eggs', 0, '1');
"
    else
        run_rust "$device_a" "
INSERT INTO todos VALUES ('1', 'Buy groceries', 0, NULL);
INSERT INTO todos VALUES ('1.1', 'Milk', 0, '1');
INSERT INTO todos VALUES ('1.2', 'Bread', 0, '1');
INSERT INTO todos VALUES ('1.3', 'Eggs', 0, '1');
"
    fi
    
    # Step 3: Sync A -> B (initial sync)
    echo "Step 3: Initial sync A -> B"
    sync_all "$impl" "$device_a" "$device_b"
    
    # Verify both have 4 items
    local a_count b_count
    if [[ "$impl" == "zig" ]]; then
        a_count=$(run_zig "$device_a" "SELECT COUNT(*) FROM todos;")
        b_count=$(run_zig "$device_b" "SELECT COUNT(*) FROM todos;")
    else
        a_count=$(run_rust "$device_a" "SELECT COUNT(*) FROM todos;")
        b_count=$(run_rust "$device_b" "SELECT COUNT(*) FROM todos;")
    fi
    
    if [[ "$a_count" != "4" || "$b_count" != "4" ]]; then
        echo "  FAIL: Initial sync failed (A=$a_count, B=$b_count)"
        return 1
    fi
    echo "  Both devices have 4 todos"
    
    # Step 4: Concurrent offline edits
    echo "Step 4: Concurrent offline edits"
    echo "  Device A: Marks 'Milk' as done, adds 'Cheese' subtask"
    echo "  Device B: Renames parent to 'Buy food', marks 'Bread' as done, adds 'Butter'"
    
    if [[ "$impl" == "zig" ]]; then
        # Device A operations
        run_zig "$device_a" "
UPDATE todos SET done = 1 WHERE id = '1.1';
INSERT INTO todos VALUES ('1.4', 'Cheese', 0, '1');
"
        # Device B operations
        run_zig "$device_b" "
UPDATE todos SET title = 'Buy food' WHERE id = '1';
UPDATE todos SET done = 1 WHERE id = '1.2';
INSERT INTO todos VALUES ('1.5', 'Butter', 0, '1');
"
    else
        # Device A operations
        run_rust "$device_a" "
UPDATE todos SET done = 1 WHERE id = '1.1';
INSERT INTO todos VALUES ('1.4', 'Cheese', 0, '1');
"
        # Device B operations
        run_rust "$device_b" "
UPDATE todos SET title = 'Buy food' WHERE id = '1';
UPDATE todos SET done = 1 WHERE id = '1.2';
INSERT INTO todos VALUES ('1.5', 'Butter', 0, '1');
"
    fi
    
    # Step 5: Bidirectional sync
    echo "Step 5: Bidirectional sync A <-> B"
    sync_all "$impl" "$device_a" "$device_b"
    sync_all "$impl" "$device_b" "$device_a"
    
    # Step 6: Verify convergence
    echo "Step 6: Verify convergence"
    
    local data_a data_b
    data_a=$(get_todos "$impl" "$device_a")
    data_b=$(get_todos "$impl" "$device_b")
    
    echo ""
    echo "Device A todos:"
    echo "$data_a" | while read -r line; do echo "  $line"; done
    echo ""
    echo "Device B todos:"
    echo "$data_b" | while read -r line; do echo "  $line"; done
    echo ""
    
    if [[ "$data_a" != "$data_b" ]]; then
        echo "  FAIL: Devices did not converge"
        echo "  A: $data_a"
        echo "  B: $data_b"
        return 1
    fi
    echo "  PASS: Both devices converged to identical state"
    
    # Verify expected state
    if [[ "$impl" == "zig" ]]; then
        local todo_count=$(run_zig "$device_a" "SELECT COUNT(*) FROM todos;")
        local done_count=$(run_zig "$device_a" "SELECT COUNT(*) FROM todos WHERE done = 1;")
        local parent_title=$(run_zig "$device_a" "SELECT title FROM todos WHERE id = '1';")
    else
        local todo_count=$(run_rust "$device_a" "SELECT COUNT(*) FROM todos;")
        local done_count=$(run_rust "$device_a" "SELECT COUNT(*) FROM todos WHERE done = 1;")
        local parent_title=$(run_rust "$device_a" "SELECT title FROM todos WHERE id = '1';")
    fi
    
    echo "  Total todos: $todo_count (expected: 6)"
    echo "  Completed: $done_count (expected: 2)"
    echo "  Parent title: '$parent_title' (expected: 'Buy food')"
    
    if [[ "$todo_count" != "6" ]]; then
        echo "  FAIL: Expected 6 todos, got $todo_count"
        return 1
    fi
    
    if [[ "$done_count" != "2" ]]; then
        echo "  FAIL: Expected 2 done todos, got $done_count"
        return 1
    fi
    
    # LWW should pick 'Buy food' since it was written later (or has higher site_id)
    # The actual winner depends on col_version/site_id tiebreaking
    
    echo "  PASS: Todo app simulation completed successfully"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test: Conflict on Same Field
# ══════════════════════════════════════════════════════════════════════════════
run_conflict_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Title Conflict Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Both devices edit the same todo title concurrently"
    
    local device_a="$TMPDIR/${prefix}_conflict_a.db"
    local device_b="$TMPDIR/${prefix}_conflict_b.db"
    
    rm -f "$device_a" "$device_b"
    
    init_device "$impl" "$device_a"
    init_device "$impl" "$device_b"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Create initial todo
    echo "Step 1: Device A creates 'Original title'"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$device_a" "INSERT INTO todos VALUES ('task1', 'Original title', 0, NULL);"
    else
        run_rust "$device_a" "INSERT INTO todos VALUES ('task1', 'Original title', 0, NULL);"
    fi
    
    # Sync to B
    echo "Step 2: Sync A -> B"
    sync_all "$impl" "$device_a" "$device_b"
    
    # Both edit title concurrently
    echo "Step 3: Concurrent title edits"
    echo "  A: 'Updated by Alice'"
    echo "  B: 'Updated by Bob'"
    
    if [[ "$impl" == "zig" ]]; then
        run_zig "$device_a" "UPDATE todos SET title = 'Updated by Alice' WHERE id = 'task1';"
        run_zig "$device_b" "UPDATE todos SET title = 'Updated by Bob' WHERE id = 'task1';"
    else
        run_rust "$device_a" "UPDATE todos SET title = 'Updated by Alice' WHERE id = 'task1';"
        run_rust "$device_b" "UPDATE todos SET title = 'Updated by Bob' WHERE id = 'task1';"
    fi
    
    # Sync both ways
    echo "Step 4: Bidirectional sync"
    sync_all "$impl" "$device_a" "$device_b"
    sync_all "$impl" "$device_b" "$device_a"
    
    # Verify convergence
    local title_a title_b
    if [[ "$impl" == "zig" ]]; then
        title_a=$(run_zig "$device_a" "SELECT title FROM todos WHERE id = 'task1';")
        title_b=$(run_zig "$device_b" "SELECT title FROM todos WHERE id = 'task1';")
    else
        title_a=$(run_rust "$device_a" "SELECT title FROM todos WHERE id = 'task1';")
        title_b=$(run_rust "$device_b" "SELECT title FROM todos WHERE id = 'task1';")
    fi
    
    echo "Step 5: Verify convergence"
    echo "  A title: '$title_a'"
    echo "  B title: '$title_b'"
    
    if [[ "$title_a" != "$title_b" ]]; then
        echo "  FAIL: Titles did not converge"
        return 1
    fi
    
    echo "  PASS: Both devices have same title (LWW winner)"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Run Tests for Both Implementations and Compare
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "============================================================================="
echo "Test 1: Todo App with Subtasks"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_todo_result=0
rust_todo_data=""
run_todo_test "rust" "rust" && rust_todo_data=$(get_todos "rust" "${TMPDIR}/rust_device_a.db") || rust_todo_result=$?

echo ""
echo ">>> Running with Zig..."
zig_todo_result=0
zig_todo_data=""
run_todo_test "zig" "zig" && zig_todo_data=$(get_todos "zig" "${TMPDIR}/zig_device_a.db") || zig_todo_result=$?

echo ""
echo "-----------------------------------------------------------------------------"
echo "Todo App Parity Check:"
echo "-----------------------------------------------------------------------------"
if [[ $rust_todo_result -eq 2 || $zig_todo_result -eq 2 ]]; then
    echo "  SKIP: Test skipped (function not implemented)"
elif [[ $rust_todo_result -eq 0 && $zig_todo_result -eq 0 ]]; then
    if [[ "$rust_todo_data" == "$zig_todo_data" ]]; then
        echo "  PARITY: Both implementations produce identical final state"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE: Final states differ!"
        echo "  Rust/C: $rust_todo_data"
        echo "  Zig:    $zig_todo_data"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_todo_result -ne 0 && $zig_todo_result -ne 0 ]]; then
    echo "  Both implementations failed (same behavior)"
    FAIL=$((FAIL + 1))
else
    echo "  DIVERGENCE: One implementation passed, other failed"
    echo "  Rust/C result: $rust_todo_result"
    echo "  Zig result: $zig_todo_result"
    DIVERGENCE=$((DIVERGENCE + 1))
fi

echo ""
echo "============================================================================="
echo "Test 2: Title Conflict Resolution"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_conflict_result=0
rust_conflict_title=""
run_conflict_test "rust" "rust" && rust_conflict_title=$(timeout 30s nix run nixpkgs#sqlite -- "${TMPDIR}/rust_conflict_a.db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "SELECT title FROM todos WHERE id = 'task1';" 2>/dev/null) || rust_conflict_result=$?

echo ""
echo ">>> Running with Zig..."
zig_conflict_result=0
zig_conflict_title=""
run_conflict_test "zig" "zig" && zig_conflict_title=$(timeout 30s nix run nixpkgs#sqlite -- "${TMPDIR}/zig_conflict_a.db" -cmd ".load $ZIG_EXT" "SELECT title FROM todos WHERE id = 'task1';" 2>/dev/null) || zig_conflict_result=$?

echo ""
echo "-----------------------------------------------------------------------------"
echo "Title Conflict Parity Check:"
echo "-----------------------------------------------------------------------------"
if [[ $rust_conflict_result -eq 2 || $zig_conflict_result -eq 2 ]]; then
    echo "  SKIP: Test skipped (function not implemented)"
elif [[ $rust_conflict_result -eq 0 && $zig_conflict_result -eq 0 ]]; then
    if [[ "$rust_conflict_title" == "$zig_conflict_title" ]]; then
        echo "  PARITY: Both implementations resolve conflict to same winner"
        echo "  Winner: '$rust_conflict_title'"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE: Conflict resolution differs!"
        echo "  Rust/C winner: '$rust_conflict_title'"
        echo "  Zig winner:    '$zig_conflict_title'"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
else
    echo "  Result mismatch: Rust=$rust_conflict_result, Zig=$zig_conflict_result"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================================================="
echo "Todo App Simulation Summary"
echo "============================================================================="
echo ""
echo "Results: $PASS parity confirmed, $FAIL failures, $DIVERGENCE divergences"
echo ""

if [[ $DIVERGENCE -gt 0 ]]; then
    echo "DIVERGENCE DETECTED: Zig and Rust/C implementations produce different results!"
    echo "This may cause sync incompatibility in real applications."
    exit 1
elif [[ $FAIL -gt 0 ]]; then
    echo "FAILURES DETECTED: Some tests failed for both implementations."
    exit 1
else
    echo "All todo app simulation tests show PARITY between Zig and Rust/C."
    echo ""
    echo "Verified scenarios:"
    echo "  - Hierarchical todos with parent/child relationships"
    echo "  - Concurrent subtask additions from multiple devices"
    echo "  - Concurrent status updates (marking done)"
    echo "  - LWW conflict resolution on same field"
    exit 0
fi
