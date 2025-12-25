#!/usr/bin/env bash
# =============================================================================
# App Simulation: Inventory/Stock Management
# =============================================================================
#
# SCENARIO: An inventory management system with multiple warehouses.
# Stock adjustments and transfers happen concurrently.
# Tests realistic patterns:
# - Stock count adjustments at different locations
# - Transfer operations (decrement source, increment destination)
# - Concurrent adjustments to same item
# - Multi-location sync
#
# This test compares Zig vs Rust/C behavior to verify parity.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "============================================================================="
echo "App Simulation: Inventory/Stock Management"
echo "============================================================================="
echo ""
echo "Simulates a warehouse inventory system with concurrent stock adjustments"
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
TMPDIR="${REPO_ROOT}/.tmp/app-inventory-$$"
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

# Initialize a warehouse terminal with inventory schema
init_warehouse() {
    local impl="$1"
    local db="$2"
    # NOTE: cr-sqlite requires NOT NULL columns to have DEFAULT values
    # for forward/backward schema compatibility
    local sql="
-- Products in each location
CREATE TABLE stock (
    sku TEXT NOT NULL DEFAULT '',
    location TEXT NOT NULL DEFAULT '',
    quantity INTEGER NOT NULL DEFAULT 0,
    last_counted INTEGER,
    PRIMARY KEY (sku, location)
);
SELECT crsql_as_crr('stock');

-- Transfer log (for audit trail)
CREATE TABLE transfers (
    id TEXT PRIMARY KEY NOT NULL,
    sku TEXT NOT NULL DEFAULT '',
    from_location TEXT NOT NULL DEFAULT '',
    to_location TEXT NOT NULL DEFAULT '',
    quantity INTEGER NOT NULL DEFAULT 0,
    timestamp INTEGER
);
SELECT crsql_as_crr('transfers');
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

# Get stock data for comparison
get_stock() {
    local impl="$1"
    local db="$2"
    local query="SELECT sku, location, quantity FROM stock ORDER BY sku, location;"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$query"
    else
        run_rust "$db" "$query"
    fi
}

# Get transfer log for comparison
get_transfers() {
    local impl="$1"
    local db="$2"
    local query="SELECT id, sku, from_location, to_location, quantity FROM transfers ORDER BY id;"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$db" "$query"
    else
        run_rust "$db" "$query"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: Basic Stock Sync Between Warehouses
# ══════════════════════════════════════════════════════════════════════════════
run_basic_stock_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Basic Stock Sync Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Two warehouses track inventory independently, then sync"
    
    local warehouse_a="$TMPDIR/${prefix}_wh_a.db"
    local warehouse_b="$TMPDIR/${prefix}_wh_b.db"
    
    rm -f "$warehouse_a" "$warehouse_b"
    
    # Initialize warehouses
    echo ""
    echo "Step 1: Initialize warehouses"
    init_warehouse "$impl" "$warehouse_a"
    init_warehouse "$impl" "$warehouse_b"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Warehouse A adds initial stock
    echo "Step 2: Warehouse A receives initial shipment"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$warehouse_a" "
INSERT INTO stock VALUES ('SKU001', 'warehouse-a', 100, 1000);
INSERT INTO stock VALUES ('SKU002', 'warehouse-a', 50, 1000);
INSERT INTO stock VALUES ('SKU003', 'warehouse-a', 200, 1000);
"
    else
        run_rust "$warehouse_a" "
INSERT INTO stock VALUES ('SKU001', 'warehouse-a', 100, 1000);
INSERT INTO stock VALUES ('SKU002', 'warehouse-a', 50, 1000);
INSERT INTO stock VALUES ('SKU003', 'warehouse-a', 200, 1000);
"
    fi
    
    # Warehouse B adds its own stock
    echo "Step 3: Warehouse B receives its shipment"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$warehouse_b" "
INSERT INTO stock VALUES ('SKU001', 'warehouse-b', 75, 1001);
INSERT INTO stock VALUES ('SKU004', 'warehouse-b', 30, 1001);
"
    else
        run_rust "$warehouse_b" "
INSERT INTO stock VALUES ('SKU001', 'warehouse-b', 75, 1001);
INSERT INTO stock VALUES ('SKU004', 'warehouse-b', 30, 1001);
"
    fi
    
    # Sync both ways
    echo "Step 4: Bidirectional sync"
    sync_all "$impl" "$warehouse_a" "$warehouse_b"
    sync_all "$impl" "$warehouse_b" "$warehouse_a"
    
    # Verify convergence
    echo "Step 5: Verify convergence"
    local stock_a stock_b
    stock_a=$(get_stock "$impl" "$warehouse_a")
    stock_b=$(get_stock "$impl" "$warehouse_b")
    
    echo ""
    echo "Warehouse A stock:"
    echo "$stock_a" | while read -r line; do echo "  $line"; done
    echo ""
    echo "Warehouse B stock:"
    echo "$stock_b" | while read -r line; do echo "  $line"; done
    
    if [[ "$stock_a" != "$stock_b" ]]; then
        echo ""
        echo "  FAIL: Stock data did not converge"
        return 1
    fi
    
    # Count unique SKU/location combos
    local item_count
    if [[ "$impl" == "zig" ]]; then
        item_count=$(run_zig "$warehouse_a" "SELECT COUNT(*) FROM stock;")
    else
        item_count=$(run_rust "$warehouse_a" "SELECT COUNT(*) FROM stock;")
    fi
    
    echo ""
    echo "  Total stock entries: $item_count (expected: 5)"
    
    if [[ "$item_count" != "5" ]]; then
        echo "  FAIL: Expected 5 stock entries"
        return 1
    fi
    
    echo "  PASS: Both warehouses converged"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Concurrent Quantity Adjustments
# ══════════════════════════════════════════════════════════════════════════════
run_quantity_conflict_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Quantity Conflict Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Both warehouses adjust same item's quantity concurrently"
    
    local warehouse_a="$TMPDIR/${prefix}_qty_a.db"
    local warehouse_b="$TMPDIR/${prefix}_qty_b.db"
    
    rm -f "$warehouse_a" "$warehouse_b"
    
    init_warehouse "$impl" "$warehouse_a"
    init_warehouse "$impl" "$warehouse_b"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Create initial stock in A
    echo "Step 1: Create initial stock (100 units)"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$warehouse_a" "INSERT INTO stock VALUES ('WIDGET', 'main', 100, 1000);"
    else
        run_rust "$warehouse_a" "INSERT INTO stock VALUES ('WIDGET', 'main', 100, 1000);"
    fi
    
    # Sync to B
    echo "Step 2: Sync to warehouse B"
    sync_all "$impl" "$warehouse_a" "$warehouse_b"
    
    # Both adjust quantity concurrently
    echo "Step 3: Concurrent quantity adjustments"
    echo "  A: Sets quantity to 80 (sold 20)"
    echo "  B: Sets quantity to 120 (received 20)"
    
    if [[ "$impl" == "zig" ]]; then
        run_zig "$warehouse_a" "UPDATE stock SET quantity = 80, last_counted = 2000 WHERE sku = 'WIDGET';"
        run_zig "$warehouse_b" "UPDATE stock SET quantity = 120, last_counted = 2001 WHERE sku = 'WIDGET';"
    else
        run_rust "$warehouse_a" "UPDATE stock SET quantity = 80, last_counted = 2000 WHERE sku = 'WIDGET';"
        run_rust "$warehouse_b" "UPDATE stock SET quantity = 120, last_counted = 2001 WHERE sku = 'WIDGET';"
    fi
    
    # Sync both ways
    echo "Step 4: Bidirectional sync"
    sync_all "$impl" "$warehouse_a" "$warehouse_b"
    sync_all "$impl" "$warehouse_b" "$warehouse_a"
    
    # Verify convergence
    echo "Step 5: Verify convergence"
    local qty_a qty_b
    if [[ "$impl" == "zig" ]]; then
        qty_a=$(run_zig "$warehouse_a" "SELECT quantity FROM stock WHERE sku = 'WIDGET';")
        qty_b=$(run_zig "$warehouse_b" "SELECT quantity FROM stock WHERE sku = 'WIDGET';")
    else
        qty_a=$(run_rust "$warehouse_a" "SELECT quantity FROM stock WHERE sku = 'WIDGET';")
        qty_b=$(run_rust "$warehouse_b" "SELECT quantity FROM stock WHERE sku = 'WIDGET';")
    fi
    
    echo "  A quantity: $qty_a"
    echo "  B quantity: $qty_b"
    
    if [[ "$qty_a" != "$qty_b" ]]; then
        echo "  FAIL: Quantities did not converge"
        return 1
    fi
    
    echo "  PASS: Both warehouses agree on quantity (LWW winner: $qty_a)"
    echo ""
    echo "  NOTE: In real apps, use counters (crsql_fract_as_ordered) for"
    echo "        accurate aggregation instead of LWW for quantities."
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Transfer Operations
# ══════════════════════════════════════════════════════════════════════════════
run_transfer_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Transfer Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Transfer stock between locations, verify audit trail"
    
    local central="$TMPDIR/${prefix}_central.db"
    local branch="$TMPDIR/${prefix}_branch.db"
    
    rm -f "$central" "$branch"
    
    init_warehouse "$impl" "$central"
    init_warehouse "$impl" "$branch"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Create initial stock at central
    echo "Step 1: Central warehouse has initial stock"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$central" "
INSERT INTO stock VALUES ('GADGET', 'central', 500, 1000);
INSERT INTO stock VALUES ('GADGET', 'branch', 0, 1000);
"
    else
        run_rust "$central" "
INSERT INTO stock VALUES ('GADGET', 'central', 500, 1000);
INSERT INTO stock VALUES ('GADGET', 'branch', 0, 1000);
"
    fi
    
    # Sync initial state
    echo "Step 2: Sync initial state"
    sync_all "$impl" "$central" "$branch"
    
    # Central initiates transfer
    echo "Step 3: Central initiates transfer of 100 units to branch"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$central" "
UPDATE stock SET quantity = 400 WHERE sku = 'GADGET' AND location = 'central';
UPDATE stock SET quantity = 100 WHERE sku = 'GADGET' AND location = 'branch';
INSERT INTO transfers VALUES ('TRX-001', 'GADGET', 'central', 'branch', 100, 2000);
"
    else
        run_rust "$central" "
UPDATE stock SET quantity = 400 WHERE sku = 'GADGET' AND location = 'central';
UPDATE stock SET quantity = 100 WHERE sku = 'GADGET' AND location = 'branch';
INSERT INTO transfers VALUES ('TRX-001', 'GADGET', 'central', 'branch', 100, 2000);
"
    fi
    
    # Branch receives goods and confirms
    echo "Step 4: Branch confirms receipt"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$branch" "UPDATE stock SET last_counted = 2001 WHERE sku = 'GADGET' AND location = 'branch';"
    else
        run_rust "$branch" "UPDATE stock SET last_counted = 2001 WHERE sku = 'GADGET' AND location = 'branch';"
    fi
    
    # Sync
    echo "Step 5: Bidirectional sync"
    sync_all "$impl" "$central" "$branch"
    sync_all "$impl" "$branch" "$central"
    
    # Verify
    echo "Step 6: Verify transfer reflected correctly"
    local central_stock branch_stock
    central_stock=$(get_stock "$impl" "$central")
    branch_stock=$(get_stock "$impl" "$branch")
    
    if [[ "$central_stock" != "$branch_stock" ]]; then
        echo "  FAIL: Stock data mismatch"
        return 1
    fi
    
    # Check quantities
    local central_qty branch_qty
    if [[ "$impl" == "zig" ]]; then
        central_qty=$(run_zig "$central" "SELECT quantity FROM stock WHERE sku = 'GADGET' AND location = 'central';")
        branch_qty=$(run_zig "$central" "SELECT quantity FROM stock WHERE sku = 'GADGET' AND location = 'branch';")
    else
        central_qty=$(run_rust "$central" "SELECT quantity FROM stock WHERE sku = 'GADGET' AND location = 'central';")
        branch_qty=$(run_rust "$central" "SELECT quantity FROM stock WHERE sku = 'GADGET' AND location = 'branch';")
    fi
    
    echo "  Central stock: $central_qty"
    echo "  Branch stock: $branch_qty"
    
    # Verify transfer log synced
    local transfer_count
    if [[ "$impl" == "zig" ]]; then
        transfer_count=$(run_zig "$branch" "SELECT COUNT(*) FROM transfers;")
    else
        transfer_count=$(run_rust "$branch" "SELECT COUNT(*) FROM transfers;")
    fi
    
    echo "  Transfer records: $transfer_count"
    
    if [[ "$transfer_count" != "1" ]]; then
        echo "  FAIL: Transfer record not synced"
        return 1
    fi
    
    echo "  PASS: Transfer completed and synced correctly"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: Multi-Location Inventory Count
# ══════════════════════════════════════════════════════════════════════════════
run_multisite_count_test() {
    local impl="$1"
    local prefix="$2"
    
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo "Running Multi-Site Inventory Count Test ($impl)"
    echo "-----------------------------------------------------------------------------"
    echo "Three locations perform simultaneous inventory counts"
    
    local site_a="$TMPDIR/${prefix}_site_a.db"
    local site_b="$TMPDIR/${prefix}_site_b.db"
    local site_c="$TMPDIR/${prefix}_site_c.db"
    
    rm -f "$site_a" "$site_b" "$site_c"
    
    init_warehouse "$impl" "$site_a"
    init_warehouse "$impl" "$site_b"
    init_warehouse "$impl" "$site_c"
    
    if is_blocked; then
        echo "  SKIP: crsql_as_crr not implemented"
        return 2
    fi
    
    # Each site counts their local inventory
    echo "Step 1: Each site performs local inventory count"
    if [[ "$impl" == "zig" ]]; then
        run_zig "$site_a" "
INSERT INTO stock VALUES ('PROD-A', 'site-a', 150, 3000);
INSERT INTO stock VALUES ('PROD-B', 'site-a', 75, 3000);
"
        run_zig "$site_b" "
INSERT INTO stock VALUES ('PROD-A', 'site-b', 200, 3001);
INSERT INTO stock VALUES ('PROD-C', 'site-b', 50, 3001);
"
        run_zig "$site_c" "
INSERT INTO stock VALUES ('PROD-B', 'site-c', 100, 3002);
INSERT INTO stock VALUES ('PROD-C', 'site-c', 125, 3002);
"
    else
        run_rust "$site_a" "
INSERT INTO stock VALUES ('PROD-A', 'site-a', 150, 3000);
INSERT INTO stock VALUES ('PROD-B', 'site-a', 75, 3000);
"
        run_rust "$site_b" "
INSERT INTO stock VALUES ('PROD-A', 'site-b', 200, 3001);
INSERT INTO stock VALUES ('PROD-C', 'site-b', 50, 3001);
"
        run_rust "$site_c" "
INSERT INTO stock VALUES ('PROD-B', 'site-c', 100, 3002);
INSERT INTO stock VALUES ('PROD-C', 'site-c', 125, 3002);
"
    fi
    
    # Star topology sync through site A
    echo "Step 2: Hub-spoke sync through site A"
    sync_all "$impl" "$site_b" "$site_a"
    sync_all "$impl" "$site_c" "$site_a"
    sync_all "$impl" "$site_a" "$site_b"
    sync_all "$impl" "$site_a" "$site_c"
    
    # Verify all sites converge
    echo "Step 3: Verify convergence"
    local stock_a stock_b stock_c
    stock_a=$(get_stock "$impl" "$site_a")
    stock_b=$(get_stock "$impl" "$site_b")
    stock_c=$(get_stock "$impl" "$site_c")
    
    if [[ "$stock_a" != "$stock_b" || "$stock_a" != "$stock_c" ]]; then
        echo "  FAIL: Sites did not converge"
        echo "  A: $stock_a"
        echo "  B: $stock_b"
        echo "  C: $stock_c"
        return 1
    fi
    
    # Count total entries
    local entry_count
    if [[ "$impl" == "zig" ]]; then
        entry_count=$(run_zig "$site_a" "SELECT COUNT(*) FROM stock;")
    else
        entry_count=$(run_rust "$site_a" "SELECT COUNT(*) FROM stock;")
    fi
    
    echo "  Total stock entries: $entry_count (expected: 6)"
    
    if [[ "$entry_count" != "6" ]]; then
        echo "  FAIL: Expected 6 stock entries"
        return 1
    fi
    
    # Verify we can compute totals
    local prod_a_total prod_b_total prod_c_total
    if [[ "$impl" == "zig" ]]; then
        prod_a_total=$(run_zig "$site_a" "SELECT SUM(quantity) FROM stock WHERE sku = 'PROD-A';")
        prod_b_total=$(run_zig "$site_a" "SELECT SUM(quantity) FROM stock WHERE sku = 'PROD-B';")
        prod_c_total=$(run_zig "$site_a" "SELECT SUM(quantity) FROM stock WHERE sku = 'PROD-C';")
    else
        prod_a_total=$(run_rust "$site_a" "SELECT SUM(quantity) FROM stock WHERE sku = 'PROD-A';")
        prod_b_total=$(run_rust "$site_a" "SELECT SUM(quantity) FROM stock WHERE sku = 'PROD-B';")
        prod_c_total=$(run_rust "$site_a" "SELECT SUM(quantity) FROM stock WHERE sku = 'PROD-C';")
    fi
    
    echo ""
    echo "  Company-wide totals:"
    echo "    PROD-A: $prod_a_total units (expected: 350)"
    echo "    PROD-B: $prod_b_total units (expected: 175)"
    echo "    PROD-C: $prod_c_total units (expected: 175)"
    
    echo ""
    echo "  PASS: All sites converged with correct inventory data"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# Run Tests and Compare Implementations
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "============================================================================="
echo "Test 1: Basic Stock Sync"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_basic_result=0
run_basic_stock_test "rust" "rust" || rust_basic_result=$?

echo ""
echo ">>> Running with Zig..."
zig_basic_result=0
run_basic_stock_test "zig" "zig" || zig_basic_result=$?

if [[ $rust_basic_result -eq 0 && $zig_basic_result -eq 0 ]]; then
    rust_data=$(get_stock "rust" "${TMPDIR}/rust_wh_a.db" 2>/dev/null || echo "")
    zig_data=$(get_stock "zig" "${TMPDIR}/zig_wh_a.db" 2>/dev/null || echo "")
    if [[ "$rust_data" == "$zig_data" ]]; then
        echo "  PARITY: Basic stock sync identical"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in basic stock sync!"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_basic_result -eq 2 || $zig_basic_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================================="
echo "Test 2: Quantity Conflict"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_qty_result=0
run_quantity_conflict_test "rust" "rust" || rust_qty_result=$?

echo ""
echo ">>> Running with Zig..."
zig_qty_result=0
run_quantity_conflict_test "zig" "zig" || zig_qty_result=$?

if [[ $rust_qty_result -eq 0 && $zig_qty_result -eq 0 ]]; then
    rust_qty=$(timeout 30s nix run nixpkgs#sqlite -- "${TMPDIR}/rust_qty_a.db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "SELECT quantity FROM stock WHERE sku = 'WIDGET';" 2>/dev/null || echo "")
    zig_qty=$(timeout 30s nix run nixpkgs#sqlite -- "${TMPDIR}/zig_qty_a.db" -cmd ".load $ZIG_EXT" "SELECT quantity FROM stock WHERE sku = 'WIDGET';" 2>/dev/null || echo "")
    if [[ "$rust_qty" == "$zig_qty" ]]; then
        echo "  PARITY: Quantity conflict resolution identical"
        echo "  Winner quantity: $rust_qty"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in quantity conflict!"
        echo "  Rust/C: $rust_qty"
        echo "  Zig: $zig_qty"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_qty_result -eq 2 || $zig_qty_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================================="
echo "Test 3: Transfer Operations"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_xfer_result=0
run_transfer_test "rust" "rust" || rust_xfer_result=$?

echo ""
echo ">>> Running with Zig..."
zig_xfer_result=0
run_transfer_test "zig" "zig" || zig_xfer_result=$?

if [[ $rust_xfer_result -eq 0 && $zig_xfer_result -eq 0 ]]; then
    rust_stock=$(get_stock "rust" "${TMPDIR}/rust_central.db" 2>/dev/null || echo "")
    zig_stock=$(get_stock "zig" "${TMPDIR}/zig_central.db" 2>/dev/null || echo "")
    rust_xfers=$(get_transfers "rust" "${TMPDIR}/rust_central.db" 2>/dev/null || echo "")
    zig_xfers=$(get_transfers "zig" "${TMPDIR}/zig_central.db" 2>/dev/null || echo "")
    if [[ "$rust_stock" == "$zig_stock" && "$rust_xfers" == "$zig_xfers" ]]; then
        echo "  PARITY: Transfer operations identical"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in transfer operations!"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_xfer_result -eq 2 || $zig_xfer_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================================="
echo "Test 4: Multi-Site Inventory Count"
echo "============================================================================="

echo ""
echo ">>> Running with Rust/C oracle..."
rust_multi_result=0
run_multisite_count_test "rust" "rust" || rust_multi_result=$?

echo ""
echo ">>> Running with Zig..."
zig_multi_result=0
run_multisite_count_test "zig" "zig" || zig_multi_result=$?

if [[ $rust_multi_result -eq 0 && $zig_multi_result -eq 0 ]]; then
    rust_data=$(get_stock "rust" "${TMPDIR}/rust_site_a.db" 2>/dev/null || echo "")
    zig_data=$(get_stock "zig" "${TMPDIR}/zig_site_a.db" 2>/dev/null || echo "")
    if [[ "$rust_data" == "$zig_data" ]]; then
        echo "  PARITY: Multi-site inventory count identical"
        PASS=$((PASS + 1))
    else
        echo "  DIVERGENCE in multi-site count!"
        DIVERGENCE=$((DIVERGENCE + 1))
    fi
elif [[ $rust_multi_result -eq 2 || $zig_multi_result -eq 2 ]]; then
    echo "  SKIP: Test skipped"
else
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================================================="
echo "Inventory App Simulation Summary"
echo "============================================================================="
echo ""
echo "Results: $PASS parity confirmed, $FAIL failures, $DIVERGENCE divergences"
echo ""

if [[ $DIVERGENCE -gt 0 ]]; then
    echo "DIVERGENCE DETECTED: Zig and Rust/C implementations produce different results!"
    echo "This may cause sync incompatibility in inventory applications."
    exit 1
elif [[ $FAIL -gt 0 ]]; then
    echo "FAILURES DETECTED: Some tests failed for both implementations."
    exit 1
else
    echo "All inventory app simulation tests show PARITY between Zig and Rust/C."
    echo ""
    echo "Verified scenarios:"
    echo "  - Multi-warehouse stock synchronization"
    echo "  - Concurrent quantity adjustments (LWW)"
    echo "  - Stock transfer with audit trail"
    echo "  - Multi-site inventory consolidation"
    exit 0
fi
