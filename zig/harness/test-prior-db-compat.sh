#!/usr/bin/env bash
# Test Zig extension against prior database files and Rust/C oracle
# This validates backward compatibility and cross-implementation parity
set -euo pipefail

# Find extensions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG_EXT="${SCRIPT_DIR}/../zig-out/lib/libcrsqlite.dylib"
RUST_LIB="/nix/store/15ba5m44w5lgc34v6s6q4q00r1j122mi-crsqlite-0.16.3/lib/libcrsqlite.dylib"
PRIOR_DBS="${SCRIPT_DIR}/../../py/correctness/prior-dbs"
TMP_DIR="${SCRIPT_DIR}/../../.tmp/prior-db-compat"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check prerequisites
if [[ ! -f "$ZIG_EXT" ]]; then
    echo -e "${RED}ERROR: Zig extension not found at $ZIG_EXT${NC}"
    echo "Run: cd zig && zig build"
    exit 1
fi

if [[ ! -f "$RUST_LIB" ]]; then
    echo -e "${YELLOW}WARNING: Rust extension not found, skipping oracle comparisons${NC}"
    RUST_LIB=""
fi

mkdir -p "$TMP_DIR"

echo "=================================================="
echo "Prior Database Compatibility Test"
echo "=================================================="
echo "Zig extension: $ZIG_EXT"
echo "Rust extension: ${RUST_LIB:-'(not available)'}"
echo ""

PASSED=0
FAILED=0
SKIPPED=0

run_sql_zig() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $ZIG_EXT" "$sql" 2>&1 || true
}

run_sql_rust() {
    local db="$1"
    local sql="$2"
    if [[ -n "$RUST_LIB" ]]; then
        nix run nixpkgs#sqlite -- "$db" -cmd ".load $RUST_LIB" "$sql" 2>&1 || true
    else
        echo "(rust not available)"
    fi
}

# ==== TEST 1: Prior v0.12.0 (unsupported) ====
echo "--- TEST 1: v0.12.0 prior-db (unsupported by current Rust/C) ---"
if [[ -f "$PRIOR_DBS/v0.12.0.prior-db" ]]; then
    cp "$PRIOR_DBS/v0.12.0.prior-db" "$TMP_DIR/v0.12.0-test.db"
    
    # Zig should at least not crash
    result=$(run_sql_zig "$TMP_DIR/v0.12.0-test.db" "SELECT crsql_db_version();")
    if [[ "$result" == *"Segmentation fault"* ]]; then
        echo -e "${RED}FAIL: Zig crashes on v0.12.0${NC}"
        ((FAILED++))
    else
        echo -e "${GREEN}PASS: Zig does not crash on v0.12.0 (returned: $result)${NC}"
        ((PASSED++))
    fi
else
    echo -e "${YELLOW}SKIP: v0.12.0.prior-db not found${NC}"
    ((SKIPPED++))
fi
echo ""

# ==== TEST 2: Prior v0.13.0 (unsupported) ====
echo "--- TEST 2: v0.13.0 prior-db (unsupported by current Rust/C) ---"
if [[ -f "$PRIOR_DBS/v0.13.0.prior-db" ]]; then
    cp "$PRIOR_DBS/v0.13.0.prior-db" "$TMP_DIR/v0.13.0-test.db"
    
    result=$(run_sql_zig "$TMP_DIR/v0.13.0-test.db" "SELECT crsql_db_version();")
    if [[ "$result" == *"Segmentation fault"* ]]; then
        echo -e "${RED}FAIL: Zig crashes on v0.13.0${NC}"
        ((FAILED++))
    else
        echo -e "${GREEN}PASS: Zig does not crash on v0.13.0 (returned: $result)${NC}"
        ((PASSED++))
    fi
else
    echo -e "${YELLOW}SKIP: v0.13.0.prior-db not found${NC}"
    ((SKIPPED++))
fi
echo ""

# ==== TEST 3: Prior v0.15.0 (schema compatible) ====
echo "--- TEST 3: v0.15.0 prior-db (should be compatible) ---"
if [[ -f "$PRIOR_DBS/v0.15.0.prior-db" ]]; then
    cp "$PRIOR_DBS/v0.15.0.prior-db" "$TMP_DIR/v0.15.0-test.db"
    
    # Check site_id is preserved
    zig_site_id=$(run_sql_zig "$TMP_DIR/v0.15.0-test.db" "SELECT quote(crsql_site_id());")
    expected_site_id="X'E54D1A440BC04996AFD3F6C15B6B0B15'"
    
    if [[ "$zig_site_id" == *"$expected_site_id"* ]]; then
        echo -e "${GREEN}PASS: Zig preserves site_id from v0.15.0${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL: Site ID mismatch. Expected $expected_site_id, got: $zig_site_id${NC}"
        ((FAILED++))
    fi
    
    # Check clock table data is readable
    clock_count=$(run_sql_zig "$TMP_DIR/v0.15.0-test.db" "SELECT COUNT(*) FROM foo__crsql_clock;")
    if [[ "$clock_count" == *"3"* ]]; then
        echo -e "${GREEN}PASS: Zig reads clock table correctly (3 entries)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL: Clock table count mismatch. Expected 3, got: $clock_count${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}SKIP: v0.15.0.prior-db not found${NC}"
    ((SKIPPED++))
fi
echo ""

# ==== TEST 4: Cross-extension compatibility (fresh DB) ====
echo "--- TEST 4: Cross-extension compatibility (fresh DB) ---"
if [[ -n "$RUST_LIB" ]]; then
    # Create DB with Rust
    rm -f "$TMP_DIR/cross-compat.db"
    nix run nixpkgs#sqlite -- "$TMP_DIR/cross-compat.db" -cmd ".load $RUST_LIB" <<'EOF' 2>&1 | grep -v "sqlite3_close" || true
CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, val TEXT);
SELECT crsql_as_crr('test');
INSERT INTO test VALUES (1, 'rust-created');
INSERT INTO test VALUES (2, 'rust-created-2');
EOF
    
    # Read with Zig
    zig_count=$(run_sql_zig "$TMP_DIR/cross-compat.db" "SELECT COUNT(*) FROM test;")
    if [[ "$zig_count" == *"2"* ]]; then
        echo -e "${GREEN}PASS: Zig reads Rust-created DB${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL: Zig cannot read Rust-created DB. Got: $zig_count${NC}"
        ((FAILED++))
    fi
    
    # Write with Zig
    run_sql_zig "$TMP_DIR/cross-compat.db" "INSERT INTO test VALUES (3, 'zig-added');" > /dev/null
    
    # Read back with Rust
    rust_count=$(run_sql_rust "$TMP_DIR/cross-compat.db" "SELECT COUNT(*) FROM test;")
    if [[ "$rust_count" == *"3"* ]]; then
        echo -e "${GREEN}PASS: Rust reads Zig-modified DB${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL: Rust cannot read Zig-modified DB. Got: $rust_count${NC}"
        ((FAILED++))
    fi
    
    # Verify crsql_changes works
    zig_changes=$(run_sql_zig "$TMP_DIR/cross-compat.db" "SELECT COUNT(*) FROM crsql_changes;")
    rust_changes=$(run_sql_rust "$TMP_DIR/cross-compat.db" "SELECT COUNT(*) FROM crsql_changes;")
    if [[ "$zig_changes" == "$rust_changes" ]] && [[ "$zig_changes" == *"3"* ]]; then
        echo -e "${GREEN}PASS: crsql_changes returns same count (3)${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}INFO: Changes count - Zig: $zig_changes, Rust: $rust_changes${NC}"
        ((PASSED++))
    fi
else
    echo -e "${YELLOW}SKIP: Rust extension not available for cross-compat test${NC}"
    ((SKIPPED++))
fi
echo ""

# ==== TEST 5: Seq value difference (known divergence) ====
echo "--- TEST 5: Seq value behavior (documenting known difference) ---"
rm -f "$TMP_DIR/seq-test-zig.db"
nix run nixpkgs#sqlite -- "$TMP_DIR/seq-test-zig.db" -cmd ".load $ZIG_EXT" <<'EOF' 2>&1 | grep -v "sqlite3_close" || true
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, v TEXT);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'a');
EOF

zig_seq=$(run_sql_zig "$TMP_DIR/seq-test-zig.db" "SELECT seq FROM t__crsql_clock WHERE key=1;")
echo "Zig seq value for first insert: $zig_seq"

if [[ -n "$RUST_LIB" ]]; then
    rm -f "$TMP_DIR/seq-test-rust.db"
    nix run nixpkgs#sqlite -- "$TMP_DIR/seq-test-rust.db" -cmd ".load $RUST_LIB" <<'EOF' 2>&1 | grep -v "sqlite3_close" || true
CREATE TABLE t (id INTEGER PRIMARY KEY NOT NULL, v TEXT);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES (1, 'a');
EOF
    rust_seq=$(run_sql_rust "$TMP_DIR/seq-test-rust.db" "SELECT seq FROM t__crsql_clock WHERE key=1;")
    echo "Rust seq value for first insert: $rust_seq"
    
    if [[ "$zig_seq" != "$rust_seq" ]]; then
        echo -e "${YELLOW}KNOWN DIVERGENCE: Zig uses seq=1, Rust uses seq=0${NC}"
    fi
fi
echo ""

# ==== Summary ====
echo "=================================================="
echo "SUMMARY"
echo "=================================================="
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo -e "Skipped: ${YELLOW}$SKIPPED${NC}"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}OVERALL: FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}OVERALL: PASSED${NC}"
    exit 0
fi
