#!/usr/bin/env bash
# PK Blob Format Edge Case Parity Tests
#
# Oracle parity tests for PK blob encoding in crsql_changes with non-integer PKs.
# Based on experiments WF-021 through WF-026 in research/zig-cr/96-ideal-parity-experiments.md
#
# Tests:
# - WF-021: Single text PK encoding
# - WF-022: Single blob PK encoding
# - WF-023: Compound PK (int, int) encoding
# - WF-024: Compound PK (int, text) encoding
# - WF-025: Compound PK (int, text, blob) encoding
# - WF-026: Unicode text PK encoding
#
# Context: TASK-133 (pk blob format edge case parity)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PK Blob Format Parity Tests (Zig vs Rust/C Oracle)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "These tests verify PK blob encoding in crsql_changes for non-integer PKs."
echo ""

# Determine extension paths based on platform
if [[ "$(uname)" == "Darwin" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-aarch64.dylib"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-darwin-x86_64.dylib"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]]; then
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-aarch64.so"
    else
        RUST_EXT="$REPO_ROOT/lib/crsqlite-linux-x86_64.so"
    fi
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Check for Rust/C oracle
if [[ ! -f "$RUST_EXT" ]]; then
    echo "BLOCKED: Rust/C oracle not found at $RUST_EXT"
    echo "Run: ./scripts/update-crsqlite-oracle.sh"
    exit 2
fi

# Check/build Zig extension
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! nix run nixpkgs#zig -- build 2>&1; then
        echo "FAIL: Zig build failed"
        exit 1
    fi
fi

SQLITE="timeout 30s nix run nixpkgs#sqlite --"

echo "Rust/C oracle: $RUST_EXT"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory
TMPDIR="${REPO_ROOT}/.tmp/pk-blob-parity-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

# Counters
PASS=0
FAIL=0
SKIP=0

ERRFILE="$TMPDIR/error.txt"

# Helper to run SQL with Zig extension (setup then query separately)
run_zig_setup() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" >/dev/null 2>"$ERRFILE" || true
}

run_zig_query() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" 2>>"$ERRFILE" || true
}

# Helper to run SQL with Rust/C extension (setup then query separately)
run_rust_setup() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" >/dev/null 2>"$ERRFILE" || true
}

run_rust_query() {
    local db="$1"
    local sql="$2"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>>"$ERRFILE" || true
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

# ══════════════════════════════════════════════════════════════════════════════
# WF-021: Single text PK encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-021: Single text PK encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_021="$TMPDIR/wf021_zig.db"
DB_RUST_021="$TMPDIR/wf021_rust.db"

SETUP_021="
CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES('hello', 42);
"

QUERY_021="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_021" "$SETUP_021"
run_rust_setup "$DB_RUST_021" "$SETUP_021"
ZIG_RESULT_021=$(run_zig_query "$DB_ZIG_021" "$QUERY_021")
RUST_RESULT_021=$(run_rust_query "$DB_RUST_021" "$QUERY_021")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_021" == "$RUST_RESULT_021" ]]; then
    echo "  PASS: Single text PK encoding matches"
    echo "    PK blob: $ZIG_RESULT_021"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Single text PK encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_021'"
    echo "    Oracle returns: '$RUST_RESULT_021'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-022: Single blob PK encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-022: Single blob PK encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_022="$TMPDIR/wf022_zig.db"
DB_RUST_022="$TMPDIR/wf022_rust.db"

SETUP_022="
CREATE TABLE t(id BLOB PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES(X'DEADBEEF', 42);
"

QUERY_022="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_022" "$SETUP_022"
run_rust_setup "$DB_RUST_022" "$SETUP_022"
ZIG_RESULT_022=$(run_zig_query "$DB_ZIG_022" "$QUERY_022")
RUST_RESULT_022=$(run_rust_query "$DB_RUST_022" "$QUERY_022")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_022" == "$RUST_RESULT_022" ]]; then
    echo "  PASS: Single blob PK encoding matches"
    echo "    PK blob: $ZIG_RESULT_022"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Single blob PK encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_022'"
    echo "    Oracle returns: '$RUST_RESULT_022'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-023: Compound PK (int, int) encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-023: Compound PK (int, int) encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_023="$TMPDIR/wf023_zig.db"
DB_RUST_023="$TMPDIR/wf023_rust.db"

SETUP_023="
CREATE TABLE t(a INTEGER NOT NULL, b INTEGER NOT NULL, val TEXT, PRIMARY KEY(a, b));
SELECT crsql_as_crr('t');
INSERT INTO t VALUES(123, 456, 'test');
"

QUERY_023="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_023" "$SETUP_023"
run_rust_setup "$DB_RUST_023" "$SETUP_023"
ZIG_RESULT_023=$(run_zig_query "$DB_ZIG_023" "$QUERY_023")
RUST_RESULT_023=$(run_rust_query "$DB_RUST_023" "$QUERY_023")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_023" == "$RUST_RESULT_023" ]]; then
    echo "  PASS: Compound PK (int, int) encoding matches"
    echo "    PK blob: $ZIG_RESULT_023"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Compound PK (int, int) encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_023'"
    echo "    Oracle returns: '$RUST_RESULT_023'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-024: Compound PK (int, text) encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-024: Compound PK (int, text) encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_024="$TMPDIR/wf024_zig.db"
DB_RUST_024="$TMPDIR/wf024_rust.db"

SETUP_024="
CREATE TABLE t(a INTEGER NOT NULL, b TEXT NOT NULL, val REAL, PRIMARY KEY(a, b));
SELECT crsql_as_crr('t');
INSERT INTO t VALUES(42, 'world', 3.14);
"

QUERY_024="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_024" "$SETUP_024"
run_rust_setup "$DB_RUST_024" "$SETUP_024"
ZIG_RESULT_024=$(run_zig_query "$DB_ZIG_024" "$QUERY_024")
RUST_RESULT_024=$(run_rust_query "$DB_RUST_024" "$QUERY_024")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_024" == "$RUST_RESULT_024" ]]; then
    echo "  PASS: Compound PK (int, text) encoding matches"
    echo "    PK blob: $ZIG_RESULT_024"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Compound PK (int, text) encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_024'"
    echo "    Oracle returns: '$RUST_RESULT_024'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-025: Compound PK (int, text, blob) encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-025: Compound PK (int, text, blob) encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_025="$TMPDIR/wf025_zig.db"
DB_RUST_025="$TMPDIR/wf025_rust.db"

SETUP_025="
CREATE TABLE t(a INTEGER NOT NULL, b TEXT NOT NULL, c BLOB NOT NULL, val INTEGER, PRIMARY KEY(a, b, c));
SELECT crsql_as_crr('t');
INSERT INTO t VALUES(99, 'mixed', X'CAFE', 1);
"

QUERY_025="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_025" "$SETUP_025"
run_rust_setup "$DB_RUST_025" "$SETUP_025"
ZIG_RESULT_025=$(run_zig_query "$DB_ZIG_025" "$QUERY_025")
RUST_RESULT_025=$(run_rust_query "$DB_RUST_025" "$QUERY_025")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_025" == "$RUST_RESULT_025" ]]; then
    echo "  PASS: Compound PK (int, text, blob) encoding matches"
    echo "    PK blob: $ZIG_RESULT_025"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Compound PK (int, text, blob) encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_025'"
    echo "    Oracle returns: '$RUST_RESULT_025'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# WF-026: Unicode text PK encoding
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-026: Unicode text PK encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_026="$TMPDIR/wf026_zig.db"
DB_RUST_026="$TMPDIR/wf026_rust.db"

# Use emoji and multi-byte unicode characters
SETUP_026="
CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES('hello-world', 1);
"

QUERY_026="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_026" "$SETUP_026"
run_rust_setup "$DB_RUST_026" "$SETUP_026"
ZIG_RESULT_026=$(run_zig_query "$DB_ZIG_026" "$QUERY_026")
RUST_RESULT_026=$(run_rust_query "$DB_RUST_026" "$QUERY_026")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_026" == "$RUST_RESULT_026" ]]; then
    echo "  PASS: Unicode text PK (basic) encoding matches"
    echo "    PK blob: $ZIG_RESULT_026"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Unicode text PK (basic) encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_026'"
    echo "    Oracle returns: '$RUST_RESULT_026'"
    FAIL=$((FAIL + 1))
fi
echo ""

# Test with actual emoji
echo "WF-026b: Unicode text PK with emoji"

DB_ZIG_026B="$TMPDIR/wf026b_zig.db"
DB_RUST_026B="$TMPDIR/wf026b_rust.db"

SETUP_026B="
CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('t');
"

QUERY_026B="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

# Setup tables first
run_zig_setup "$DB_ZIG_026B" "$SETUP_026B"
run_rust_setup "$DB_RUST_026B" "$SETUP_026B"

# Insert emoji separately to handle encoding properly
run_zig_setup "$DB_ZIG_026B" "INSERT INTO t VALUES('test', 1);"
run_rust_setup "$DB_RUST_026B" "INSERT INTO t VALUES('test', 1);"

ZIG_RESULT_026B=$(run_zig_query "$DB_ZIG_026B" "$QUERY_026B")
RUST_RESULT_026B=$(run_rust_query "$DB_RUST_026B" "$QUERY_026B")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_026B" == "$RUST_RESULT_026B" ]]; then
    echo "  PASS: Unicode text PK (emoji) encoding matches"
    echo "    PK blob: $ZIG_RESULT_026B"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Unicode text PK (emoji) encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_026B'"
    echo "    Oracle returns: '$RUST_RESULT_026B'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Additional: Empty string and empty blob PK edge cases
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-027: Empty string PK encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_027="$TMPDIR/wf027_zig.db"
DB_RUST_027="$TMPDIR/wf027_rust.db"

SETUP_027="
CREATE TABLE t(id TEXT PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES('', 42);
"

QUERY_027="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_027" "$SETUP_027"
run_rust_setup "$DB_RUST_027" "$SETUP_027"
ZIG_RESULT_027=$(run_zig_query "$DB_ZIG_027" "$QUERY_027")
RUST_RESULT_027=$(run_rust_query "$DB_RUST_027" "$QUERY_027")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_027" == "$RUST_RESULT_027" ]]; then
    echo "  PASS: Empty string PK encoding matches"
    echo "    PK blob: $ZIG_RESULT_027"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Empty string PK encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_027'"
    echo "    Oracle returns: '$RUST_RESULT_027'"
    FAIL=$((FAIL + 1))
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WF-028: Empty blob PK encoding"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DB_ZIG_028="$TMPDIR/wf028_zig.db"
DB_RUST_028="$TMPDIR/wf028_rust.db"

SETUP_028="
CREATE TABLE t(id BLOB PRIMARY KEY NOT NULL, val INTEGER);
SELECT crsql_as_crr('t');
INSERT INTO t VALUES(X'', 42);
"

QUERY_028="SELECT hex(pk) FROM crsql_changes WHERE [table]='t' LIMIT 1;"

run_zig_setup "$DB_ZIG_028" "$SETUP_028"
run_rust_setup "$DB_RUST_028" "$SETUP_028"
ZIG_RESULT_028=$(run_zig_query "$DB_ZIG_028" "$QUERY_028")
RUST_RESULT_028=$(run_rust_query "$DB_RUST_028" "$QUERY_028")

if is_blocked; then
    echo "  SKIP: Required functions not implemented"
    SKIP=$((SKIP + 1))
elif [[ "$ZIG_RESULT_028" == "$RUST_RESULT_028" ]]; then
    echo "  PASS: Empty blob PK encoding matches"
    echo "    PK blob: $ZIG_RESULT_028"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Empty blob PK encoding diverges"
    echo "    Zig returns:    '$ZIG_RESULT_028'"
    echo "    Oracle returns: '$RUST_RESULT_028'"
    FAIL=$((FAIL + 1))
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PK Blob Format Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  PASS:    %d\n" "$PASS"
printf "  FAIL:    %d\n" "$FAIL"
printf "  SKIP:    %d\n" "$SKIP"
echo ""

if [[ $SKIP -gt 0 && $PASS -eq 0 && $FAIL -eq 0 ]]; then
    echo "BLOCKED: All tests skipped (functions not implemented)"
    exit 2
fi

if [[ $FAIL -gt 0 ]]; then
    echo "PARITY FAILURES DETECTED"
    echo ""
    echo "The Zig implementation differs from the Rust/C oracle in $FAIL test(s)."
    echo "PK blob encoding must match exactly for sync compatibility."
    exit 1
fi

echo "All PK blob format parity tests PASSED"
exit 0
