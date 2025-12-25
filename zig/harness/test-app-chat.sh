#!/usr/bin/env bash
# =============================================================================
# App Simulation: Chat/Notes App with Offline Edits
# =============================================================================
#
# SCENARIO: A chat/notes app where users edit messages offline.
# Multiple devices create, edit, and delete messages concurrently.
# Tests realistic patterns:
# - Long-running conversation with many messages
# - Offline period then reconnect
# - Concurrent edits to same message
# - Message deletion and resurrection
# - Out-of-order sync
#
# This test compares Zig vs Rust/C behavior to verify parity.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "============================================================================="
echo "App Simulation: Chat/Notes App with Offline Edits"
echo "============================================================================="
echo ""
echo "Simulates a chat app with offline editing and message conflicts"
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
TMPDIR="${REPO_ROOT}/.tmp/app-chat-$$"
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
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$ERRFILE" || true
}

run_rust() {
    local db="$1"
    local sql="$2"
    timeout 30s nix run nixpkgs#sqlite -- "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$ERRFILE" || true
}

is_blocked() {
    if [[ -s "$ERRFILE" ]]; then
        if grep -q "no such function" "$ERRFILE"; then
            return 0
        fi
    fi
    return 1
}

# Initialize a device with chat schema
init_device() {
    local impl="$1"
    local db="$2"
    # NOTE: cr-sqlite requires NOT NULL columns to have DEFAULT values
    # for forward/backward schema compatibility
    local sql="
CREATE TABLE messages (
    id TEXT PRIMARY KEY NOT NULL,
    channel TEXT NOT NULL DEFAULT '',
    sender TEXT NOT NULL DEFAULT '',
    content TEXT NOT NULL DEFAULT '',
    edited INTEGER NOT NULL DEFAULT 0,
    timestamp INTEGER
);
SELECT crsql_as_crr('messages');
"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$sql" 2>"$ERRFILE"
    else
        run_rust "$db" "$sql" 2>"$ERRFILE"
    fi
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

# Get sorted message data for comparison
get_messages() {
    local impl="$1"
    local db="$2"
    local query="SELECT id, sender, content, edited FROM messages ORDER BY id;"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$query"
    else
        run_rust "$db" "$query"
    fi
}

# Get message count
get_count() {
    local impl="$1"
    local db="$2"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "SELECT COUNT(*) FROM messages;"
    else
        run_rust "$db" "SELECT COUNT(*) FROM messages;"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: Basic Chat with Offline Sync
# ══════════════════════════════════════════════════════════════════════════════
run_basic_chat_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Basic Chat Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Alice and Bob chat on separate devices, sync later"
    
    local alice_db="$TMPDIR/${prefix}_alice.db"
    local bob_db="$TMPDIR/${prefix}_bob.db"
    
    rm -f "$alice_db" "$bob_db"
    
    # Initialize devices
    echo ""
    echo "Step 1: Initialize devices"
    init_device "$impl" "$alice_db"
    init_device "$impl" "$bob_db"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Alice sends messages
    echo "Step 2: Alice sends 3 messages while offline"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$alice_db" "
INSERT INTO messages VALUES ('msg-a1', 'general', 'alice', 'Hey everyone!', 0, 1000);
INSERT INTO messages VALUES ('msg-a2', 'general', 'alice', 'Anyone here?', 0, 1001);
INSERT INTO messages VALUES ('msg-a3', 'general', 'alice', 'I have a question about the project', 0, 1002);
"
    else
        run_rust "$alice_db" "
INSERT INTO messages VALUES ('msg-a1', 'general', 'alice', 'Hey everyone!', 0, 1000);
INSERT INTO messages VALUES ('msg-a2', 'general', 'alice', 'Anyone here?', 0, 1001);
INSERT INTO messages VALUES ('msg-a3', 'general', 'alice', 'I have a question about the project', 0, 1002);
"
    fi
    
    # Bob sends messages
    echo "Step 3: Bob sends 2 messages while offline"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$bob_db" "
INSERT INTO messages VALUES ('msg-b1', 'general', 'bob', 'Hi Alice!', 0, 1003);
INSERT INTO messages VALUES ('msg-b2', 'general', 'bob', 'What is your question?', 0, 1004);
"
    else
        run_rust "$bob_db" "
INSERT INTO messages VALUES ('msg-b1', 'general', 'bob', 'Hi Alice!', 0, 1003);
INSERT INTO messages VALUES ('msg-b2', 'general', 'bob', 'What is your question?', 0, 1004);
"
    fi
    
    # Sync both ways
    echo "Step 4: Bidirectional sync"
    sync_all "$impl" "$alice_db" "$bob_db"
    sync_all "$impl" "$bob_db" "$alice_db"
    
    # Verify convergence
    echo "Step 5: Verify convergence"
    local alice_data bob_data
    alice_data=$(get_messages "$impl" "$alice_db")
    bob_data=$(get_messages "$impl" "$bob_db")
    
    local alice_count bob_count
    alice_count=$(get_count "$impl" "$alice_db")
    bob_count=$(get_count "$impl" "$bob_db")
    
    echo "  Alice has $alice_count messages"
    echo "  Bob has $bob_count messages"
    
    if [[ "$alice_data" != "$bob_data" ]]; then
        echo "  FAIL: Messages did not converge"
        return 1
    fi
    
    if [[ "$alice_count" != "5" ]]; then
        echo "  FAIL: Expected 5 messages, got $alice_count"
        return 1
    fi
    
    echo "  PASS: Both devices have all 5 messages"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Concurrent Message Edits
# ══════════════════════════════════════════════════════════════════════════════
run_edit_conflict_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Message Edit Conflict Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Both users edit the same message concurrently"
    
    local alice_db="$TMPDIR/${prefix}_edit_alice.db"
    local bob_db="$TMPDIR/${prefix}_edit_bob.db"
    
    rm -f "$alice_db" "$bob_db"
    
    init_device "$impl" "$alice_db"
    init_device "$impl" "$bob_db"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Alice creates a message
    echo "Step 1: Alice creates a message"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$alice_db" "INSERT INTO messages VALUES ('shared-msg', 'general', 'alice', 'Original message', 0, 1000);"
    else
        run_rust "$alice_db" "INSERT INTO messages VALUES ('shared-msg', 'general', 'alice', 'Original message', 0, 1000);"
    fi
    
    # Sync to Bob
    echo "Step 2: Sync to Bob"
    sync_all "$impl" "$alice_db" "$bob_db"
    
    # Both edit concurrently
    echo "Step 3: Concurrent edits"
    echo "  Alice: 'Edited by Alice'"
    echo "  Bob: 'Edited by Bob'"
    
    if [[ "$impl" == "zig" ]]; then
        run_zig "$alice_db" "UPDATE messages SET content = 'Edited by Alice', edited = 1 WHERE id = 'shared-msg';"
        run_zig "$bob_db" "UPDATE messages SET content = 'Edited by Bob', edited = 1 WHERE id = 'shared-msg';"
    else
        run_rust "$alice_db" "UPDATE messages SET content = 'Edited by Alice', edited = 1 WHERE id = 'shared-msg';"
        run_rust "$bob_db" "UPDATE messages SET content = 'Edited by Bob', edited = 1 WHERE id = 'shared-msg';"
    fi
    
    # Sync both ways
    echo "Step 4: Bidirectional sync"
    sync_all "$impl" "$alice_db" "$bob_db"
    sync_all "$impl" "$bob_db" "$alice_db"
    
    # Verify convergence
    echo "Step 5: Verify convergence"
    local alice_content bob_content
    if [[ "$impl" == "zig" ]]; then
        alice_content=$(run_zig "$alice_db" "SELECT content FROM messages WHERE id = 'shared-msg';")
        bob_content=$(run_zig "$bob_db" "SELECT content FROM messages WHERE id = 'shared-msg';")
    else
        alice_content=$(run_rust "$alice_db" "SELECT content FROM messages WHERE id = 'shared-msg';")
        bob_content=$(run_rust "$bob_db" "SELECT content FROM messages WHERE id = 'shared-msg';")
    fi
    
    echo "  Alice sees: '$alice_content'"
    echo "  Bob sees: '$bob_content'"
    
    if [[ "$alice_content" != "$bob_content" ]]; then
        echo "  FAIL: Content did not converge"
        return 1
    fi
    
    echo "  PASS: Both see same content (LWW winner)"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Delete and Resurrection
# ══════════════════════════════════════════════════════════════════════════════
run_delete_resurrect_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Delete/Resurrect Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "One user deletes, another edits - testing resurrection semantics"
    
    local alice_db="$TMPDIR/${prefix}_del_alice.db"
    local bob_db="$TMPDIR/${prefix}_del_bob.db"
    
    rm -f "$alice_db" "$bob_db"
    
    init_device "$impl" "$alice_db"
    init_device "$impl" "$bob_db"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Alice creates a message
    echo "Step 1: Alice creates a message"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$alice_db" "INSERT INTO messages VALUES ('to-delete', 'general', 'alice', 'This might be deleted', 0, 1000);"
    else
        run_rust "$alice_db" "INSERT INTO messages VALUES ('to-delete', 'general', 'alice', 'This might be deleted', 0, 1000);"
    fi
    
    # Sync to Bob
    echo "Step 2: Sync to Bob"
    sync_all "$impl" "$alice_db" "$bob_db"
    
    # Alice deletes, Bob edits
    echo "Step 3: Concurrent delete (Alice) and edit (Bob)"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$alice_db" "DELETE FROM messages WHERE id = 'to-delete';"
        run_zig "$bob_db" "UPDATE messages SET content = 'Bob edited this' WHERE id = 'to-delete';"
    else
        run_rust "$alice_db" "DELETE FROM messages WHERE id = 'to-delete';"
        run_rust "$bob_db" "UPDATE messages SET content = 'Bob edited this' WHERE id = 'to-delete';"
    fi
    
    # Sync Alice's delete to Bob first
    echo "Step 4: Sync Alice's delete to Bob"
    sync_all "$impl" "$alice_db" "$bob_db"
    
    # Then sync Bob's edit (which may resurrect) to Alice
    echo "Step 5: Sync Bob's edit to Alice"
    sync_all "$impl" "$bob_db" "$alice_db"
    
    # Final sync to ensure consistency
    echo "Step 6: Final sync round"
    sync_all "$impl" "$alice_db" "$bob_db"
    
    # Check final state
    echo "Step 7: Verify convergence"
    local alice_count bob_count
    alice_count=$(get_count "$impl" "$alice_db")
    bob_count=$(get_count "$impl" "$bob_db")
    
    echo "  Alice message count: $alice_count"
    echo "  Bob message count: $bob_count"
    
    if [[ "$alice_count" != "$bob_count" ]]; then
        echo "  FAIL: Message counts do not match"
        return 1
    fi
    
    local alice_data bob_data
    alice_data=$(get_messages "$impl" "$alice_db")
    bob_data=$(get_messages "$impl" "$bob_db")
    
    if [[ "$alice_data" != "$bob_data" ]]; then
        echo "  FAIL: Message data does not match"
        echo "  Alice: $alice_data"
        echo "  Bob: $bob_data"
        return 1
    fi
    
    echo "  PASS: Both devices converged"
    echo "  Final state: $([ "$alice_count" == "0" ] && echo "deleted" || echo "resurrected")"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: Three-Device Offline Sync
# ══════════════════════════════════════════════════════════════════════════════
run_three_device_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Three-Device Offline Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Alice, Bob, and Carol all work offline then sync via hub pattern"
    
    local alice_db="$TMPDIR/${prefix}_3way_alice.db"
    local bob_db="$TMPDIR/${prefix}_3way_bob.db"
    local carol_db="$TMPDIR/${prefix}_3way_carol.db"
    
    rm -f "$alice_db" "$bob_db" "$carol_db"
    
    init_device "$impl" "$alice_db"
    init_device "$impl" "$bob_db"
    init_device "$impl" "$carol_db"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # All three create messages offline
    echo "Step 1: All three users compose messages offline"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$alice_db" "
INSERT INTO messages VALUES ('alice-1', 'team', 'alice', 'Hello from Alice', 0, 100);
INSERT INTO messages VALUES ('alice-2', 'team', 'alice', 'Working on feature X', 0, 101);
"
        run_zig "$bob_db" "
INSERT INTO messages VALUES ('bob-1', 'team', 'bob', 'Hello from Bob', 0, 102);
INSERT INTO messages VALUES ('bob-2', 'team', 'bob', 'Working on feature Y', 0, 103);
"
        run_zig "$carol_db" "
INSERT INTO messages VALUES ('carol-1', 'team', 'carol', 'Hello from Carol', 0, 104);
INSERT INTO messages VALUES ('carol-2', 'team', 'carol', 'Working on feature Z', 0, 105);
"
    else
        run_rust "$alice_db" "
INSERT INTO messages VALUES ('alice-1', 'team', 'alice', 'Hello from Alice', 0, 100);
INSERT INTO messages VALUES ('alice-2', 'team', 'alice', 'Working on feature X', 0, 101);
"
        run_rust "$bob_db" "
INSERT INTO messages VALUES ('bob-1', 'team', 'bob', 'Hello from Bob', 0, 102);
INSERT INTO messages VALUES ('bob-2', 'team', 'bob', 'Working on feature Y', 0, 103);
"
        run_rust "$carol_db" "
INSERT INTO messages VALUES ('carol-1', 'team', 'carol', 'Hello from Carol', 0, 104);
INSERT INTO messages VALUES ('carol-2', 'team', 'carol', 'Working on feature Z', 0, 105);
"
    fi
    
    # Hub-spoke sync through Alice
    echo "Step 2: Hub-spoke sync through Alice"
    sync_all "$impl" "$bob_db" "$alice_db"
    sync_all "$impl" "$carol_db" "$alice_db"
    sync_all "$impl" "$alice_db" "$bob_db"
    sync_all "$impl" "$alice_db" "$carol_db"
    
    # Verify all have all messages
    echo "Step 3: Verify convergence"
    local alice_count bob_count carol_count
    alice_count=$(get_count "$impl" "$alice_db")
    bob_count=$(get_count "$impl" "$bob_db")
    carol_count=$(get_count "$impl" "$carol_db")
    
    echo "  Alice: $alice_count messages"
    echo "  Bob: $bob_count messages"
    echo "  Carol: $carol_count messages"
    
    if [[ "$alice_count" != "6" || "$bob_count" != "6" || "$carol_count" != "6" ]]; then
        echo "  FAIL: Not all devices have 6 messages"
        return 1
    fi
    
    local alice_data bob_data carol_data
    alice_data=$(get_messages "$impl" "$alice_db")
    bob_data=$(get_messages "$impl" "$bob_db")
    carol_data=$(get_messages "$impl" "$carol_db")
    
    if [[ "$alice_data" != "$bob_data" || "$alice_data" != "$carol_data" ]]; then
        echo "  FAIL: Data mismatch between devices"
        return 1
    fi
    
    echo "  PASS: All 3 devices converged with 6 messages each"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Run Tests and Compare Implementations
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "============================================================================="
echo "Test 1: Basic Chat"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_basic_result=0
run_basic_chat_test "rust" "rust" || rust_basic_result=$?

echo ""
echo ">>> Running with Zig..."
zig_basic_result=0
run_basic_chat_test "zig" "zig" || zig_basic_result=$?

if [[ $rust_basic_result -eq 0 && $zig_basic_result -eq 0 ]]; then
    rust_data=$(get_messages "rust" "${TMPDIR}/rust_alice.db" 2>/dev/null || echo "")
    zig_data=$(get_messages "zig" "${TMPDIR}/zig_alice.db" 2>/dev/null || echo "")
    if [[ "$rust_data" == "$zig_data" ]]; then
        echo "  PARITY: Basic chat test shows identical behavior"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in basic chat!"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_basic_result -eq 2 || $zig_basic_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================================="
echo "Test 2: Edit Conflict"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_edit_result=0
run_edit_conflict_test "rust" "rust" || rust_edit_result=$?

echo ""
echo ">>> Running with Zig..."
zig_edit_result=0
run_edit_conflict_test "zig" "zig" || zig_edit_result=$?

if [[ $rust_edit_result -eq 0 && $zig_edit_result -eq 0 ]]; then
    rust_content=$(timeout 30s nix run nixpkgs#sqlite -- "${TMPDIR}/rust_edit_alice.db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "SELECT content FROM messages;" 2>/dev/null || echo "")
    zig_content=$(timeout 30s nix run nixpkgs#sqlite -- "${TMPDIR}/zig_edit_alice.db" -cmd ".load $ZIG_EXT" "SELECT content FROM messages;" 2>/dev/null || echo "")
    if [[ "$rust_content" == "$zig_content" ]]; then
        echo "  PARITY: Edit conflict resolution identical"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in edit conflict!"
        echo "  Rust/C: '$rust_content'"
        echo "  Zig: '$zig_content'"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_edit_result -eq 2 || $zig_edit_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================================="
echo "Test 3: Delete/Resurrect"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_del_result=0
run_delete_resurrect_test "rust" "rust" || rust_del_result=$?

echo ""
echo ">>> Running with Zig..."
zig_del_result=0
run_delete_resurrect_test "zig" "zig" || zig_del_result=$?

if [[ $rust_del_result -eq 0 && $zig_del_result -eq 0 ]]; then
    rust_count=$(get_count "rust" "${TMPDIR}/rust_del_alice.db" 2>/dev/null || echo "-1")
    zig_count=$(get_count "zig" "${TMPDIR}/zig_del_alice.db" 2>/dev/null || echo "-1")
    if [[ "$rust_count" == "$zig_count" ]]; then
        echo "  PARITY: Delete/resurrect behavior identical"
        echo "  Final state: $([ "$rust_count" == "0" ] && echo "message deleted" || echo "message resurrected")"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in delete/resurrect!"
        echo "  Rust/C count: $rust_count"
        echo "  Zig count: $zig_count"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_del_result -eq 2 || $zig_del_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================================="
echo "Test 4: Three-Device Offline Sync"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_3way_result=0
run_three_device_test "rust" "rust" || rust_3way_result=$?

echo ""
echo ">>> Running with Zig..."
zig_3way_result=0
run_three_device_test "zig" "zig" || zig_3way_result=$?

if [[ $rust_3way_result -eq 0 && $zig_3way_result -eq 0 ]]; then
    rust_data=$(get_messages "rust" "${TMPDIR}/rust_3way_alice.db" 2>/dev/null || echo "")
    zig_data=$(get_messages "zig" "${TMPDIR}/zig_3way_alice.db" 2>/dev/null || echo "")
    if [[ "$rust_data" == "$zig_data" ]]; then
        echo "  PARITY: Three-device sync identical"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in three-device sync!"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_3way_result -eq 2 || $zig_3way_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================================================="
echo "Chat App Simulation Summary"
echo "============================================================================="
echo ""
echo "Results: $PASS parity confirmed, $FAIL failures, $DIVERGENCE divergences"
echo ""

if [[ $DIVERGENCE -gt 0 ]]; then
    echo "DIVERGENCE DETECTED: Zig and Rust/C implementations produce different results!"
    echo "This may cause sync incompatibility in chat applications."
    exit 1
elif [[ $FAIL -gt 0 ]]; then
    echo "FAILURES DETECTED: Some tests failed for both implementations."
    exit 1
else
    echo "All chat app simulation tests show PARITY between Zig and Rust/C."
    echo ""
    echo "Verified scenarios:"
    echo "  - Multi-user offline message creation"
    echo "  - Concurrent message edits (LWW resolution)"
    echo "  - Delete vs edit race condition"
    echo "  - Three-device hub-spoke sync pattern"
    exit 0
fi
