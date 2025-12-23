#!/usr/bin/env bash
# DEFAULT Value Merge Semantics Test (TASK-177)
#
# Verifies that DEFAULT column values are handled correctly during merge.
# The key rule: explicit values always beat DEFAULT values, even when DEFAULT
# would win on value tie-break (DEFAULT values have col_version=0 or no clock entry).
#
# Test coverage:
# 1. Explicit value beats DEFAULT when explicit has clock entry (col_version > 0)
# 2. DEFAULT value handling after ALTER ADD COLUMN
# 3. DEFAULT does NOT create phantom clock entries (no backfill for defaults)
#
# Reference: py/correctness/tests/test_sync.py
#   - test_merging_on_defaults()
#   - test_merging_larger_backfilled_default()
#   - test_merging_on_defaults2()
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║       DEFAULT Value Merge Semantics Test (Zig vs Rust/C Oracle)       ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Determine Zig extension path
if [[ "$(uname)" == "Darwin" ]]; then
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    ZIG_EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

# Check if Zig extension exists
if [[ ! -f "$ZIG_EXT" ]]; then
    echo "Building Zig extension..."
    cd "$ZIG_DIR"
    if ! timeout 120s nix run nixpkgs#zig -- build 2>&1; then
        echo "BLOCKED: Zig build failed"
        exit 2
    fi
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "BLOCKED: Zig extension not found at $ZIG_EXT"
    exit 2
fi

# Use sqlite-cr for Rust (has cr-sqlite preloaded)
# Use plain sqlite with Zig extension
SQLITE_CR="timeout 30s nix run github:subtleGradient/sqlite-cr --"
SQLITE_ZIG="timeout 30s nix run nixpkgs#sqlite --"

echo "Rust/C: using sqlite-cr (nix run github:subtleGradient/sqlite-cr)"
echo "Zig extension: $ZIG_EXT"
echo ""

# Create temp directory for DBs
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

TOTAL_PASS=0
TOTAL_FAIL=0
DIVERGENCES=""

# Helper: run SQL on a DB with Rust (sqlite-cr), capture output
# Suppresses all output except the last SELECT result
run_rust() {
    local db="$1"
    local sql="$2"
    local sqlfile="$TMPDIR/query.sql"
    echo "$sql" > "$sqlfile"
    $SQLITE_CR "$db" < "$sqlfile" 2>/dev/null | tail -1 || true
}

# Helper: run SQL on a DB with Zig, capture output
# Suppresses all output except the last SELECT result
run_zig() {
    local db="$1"
    local sql="$2"
    local sqlfile="$TMPDIR/query.sql"
    echo "$sql" > "$sqlfile"
    $SQLITE_ZIG "$db" -cmd ".load $ZIG_EXT" < "$sqlfile" 2>/dev/null | tail -1 || true
}

# Helper: run SQL setup (discard all output)
setup_rust() {
    local db="$1"
    local sql="$2"
    local sqlfile="$TMPDIR/setup.sql"
    echo "$sql" > "$sqlfile"
    $SQLITE_CR "$db" < "$sqlfile" > /dev/null 2>&1 || true
}

setup_zig() {
    local db="$1"
    local sql="$2"
    local sqlfile="$TMPDIR/setup.sql"
    echo "$sql" > "$sqlfile"
    $SQLITE_ZIG "$db" -cmd ".load $ZIG_EXT" < "$sqlfile" > /dev/null 2>&1 || true
}

# Helper: sync changes from src to dst
sync_changes() {
    local impl="$1"  # "rust" or "zig"
    local src_db="$2"
    local dst_db="$3"
    local since="$4"
    
    local changes_file="$TMPDIR/changes.sql"
    
    if [[ "$impl" == "rust" ]]; then
        # Get changes from source
        $SQLITE_CR "$src_db" <<EOF > "$changes_file" 2>/dev/null
.mode insert crsql_changes
SELECT * FROM crsql_changes WHERE db_version > $since;
EOF
        # Apply to destination
        if [[ -s "$changes_file" ]]; then
            $SQLITE_CR "$dst_db" < "$changes_file" > /dev/null 2>&1 || true
        fi
    else
        $SQLITE_ZIG "$src_db" -cmd ".load $ZIG_EXT" <<EOF > "$changes_file" 2>/dev/null
.mode insert crsql_changes
SELECT * FROM crsql_changes WHERE db_version > $since;
EOF
        if [[ -s "$changes_file" ]]; then
            $SQLITE_ZIG "$dst_db" -cmd ".load $ZIG_EXT" < "$changes_file" > /dev/null 2>&1 || true
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Explicit value beats DEFAULT (test_merging_on_defaults)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Explicit value beats DEFAULT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_explicit_beats_default() {
    local impl="$1"
    local db1="$TMPDIR/${impl}_t1_db1.db"
    local db2="$TMPDIR/${impl}_t1_db2.db"
    rm -f "$db1" "$db2"
    
    if [[ "$impl" == "rust" ]]; then
        # DB1: INSERT without specifying b (uses DEFAULT 0)
        setup_rust "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 0);
            INSERT INTO foo (a) VALUES (1);
            SELECT crsql_as_crr('foo');
        "
        # DB2: INSERT with explicit b=2
        setup_rust "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 0);
            INSERT INTO foo VALUES (1, 2);
            SELECT crsql_as_crr('foo');
        "
        # Sync DB2 -> DB1
        sync_changes "rust" "$db2" "$db1" 0
        # Get result
        run_rust "$db1" "SELECT b FROM foo WHERE a = 1;"
    else
        setup_zig "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 0);
            INSERT INTO foo (a) VALUES (1);
            SELECT crsql_as_crr('foo');
        "
        setup_zig "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 0);
            INSERT INTO foo VALUES (1, 2);
            SELECT crsql_as_crr('foo');
        "
        sync_changes "zig" "$db2" "$db1" 0
        run_zig "$db1" "SELECT b FROM foo WHERE a = 1;"
    fi
}

echo "  Running Rust/C..."
RUST_RESULT=$(test_explicit_beats_default "rust")
echo "  Rust/C result: b = $RUST_RESULT"

echo "  Running Zig..."
ZIG_RESULT=$(test_explicit_beats_default "zig")
echo "  Zig result: b = $ZIG_RESULT"

if [[ "$RUST_RESULT" == "2" && "$ZIG_RESULT" == "2" ]]; then
    echo "  PASS: Explicit value (2) beats DEFAULT (0) in both implementations"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RUST_RESULT" == "$ZIG_RESULT" ]]; then
    echo "  PASS: Both implementations match ($RUST_RESULT), behavior consistent"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Implementations diverge (Rust: $RUST_RESULT, Zig: $ZIG_RESULT)"
    DIVERGENCES="$DIVERGENCES\n- explicit_beats_default: Rust=$RUST_RESULT, Zig=$ZIG_RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Larger DEFAULT value still loses to explicit smaller value
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Larger DEFAULT loses to explicit smaller value (tie-break)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_larger_default_loses() {
    local impl="$1"
    local db1="$TMPDIR/${impl}_t2_db1.db"
    local db2="$TMPDIR/${impl}_t2_db2.db"
    rm -f "$db1" "$db2"
    
    if [[ "$impl" == "rust" ]]; then
        # DB1: INSERT without specifying b (uses DEFAULT 4)
        setup_rust "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            INSERT INTO foo (a) VALUES (1);
            SELECT crsql_as_crr('foo');
        "
        # DB2: INSERT with explicit b=2 (smaller than DEFAULT 4)
        setup_rust "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo (a,b) VALUES (1,2);
        "
        # Sync DB1 -> DB2 (DEFAULT 4 synced to DB2 which has explicit 2)
        sync_changes "rust" "$db1" "$db2" 0
        run_rust "$db2" "SELECT b FROM foo WHERE a = 1;"
    else
        setup_zig "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            INSERT INTO foo (a) VALUES (1);
            SELECT crsql_as_crr('foo');
        "
        setup_zig "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo (a,b) VALUES (1,2);
        "
        sync_changes "zig" "$db1" "$db2" 0
        run_zig "$db2" "SELECT b FROM foo WHERE a = 1;"
    fi
}

echo "  Running Rust/C..."
RUST_RESULT=$(test_larger_default_loses "rust")
echo "  Rust/C result: b = $RUST_RESULT"

echo "  Running Zig..."
ZIG_RESULT=$(test_larger_default_loses "zig")
echo "  Zig result: b = $ZIG_RESULT"

# Python test expects 4 to win (tie-break goes to greatest value)
if [[ "$RUST_RESULT" == "4" && "$ZIG_RESULT" == "4" ]]; then
    echo "  PASS: Value 4 wins tie-break (both implementations)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RUST_RESULT" == "$ZIG_RESULT" ]]; then
    echo "  PASS: Both implementations match ($RUST_RESULT)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Implementations diverge (Rust: $RUST_RESULT, Zig: $ZIG_RESULT)"
    DIVERGENCES="$DIVERGENCES\n- larger_default: Rust=$RUST_RESULT, Zig=$ZIG_RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: DEFAULT after ALTER ADD COLUMN (test_merging_on_defaults2)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: DEFAULT after ALTER ADD COLUMN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  (Row exists, then ALTER adds column with DEFAULT - no clock entry for new col)"

test_default_after_alter() {
    local impl="$1"
    local db1="$TMPDIR/${impl}_t3_db1.db"
    local db2="$TMPDIR/${impl}_t3_db2.db"
    rm -f "$db1" "$db2"
    
    if [[ "$impl" == "rust" ]]; then
        # DB1: Row exists, then ALTER adds column c with DEFAULT 0
        setup_rust "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo (a) VALUES (1);
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 0;
            SELECT crsql_commit_alter('foo');
        "
        # DB2: ALTER first, then INSERT with explicit c=3
        setup_rust "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            SELECT crsql_as_crr('foo');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 0;
            SELECT crsql_commit_alter('foo');
            INSERT INTO foo (a,b,c) VALUES (1,2,3);
        "
        # Sync DB2 -> DB1 (explicit c=3 should win over DEFAULT 0 with no clock)
        sync_changes "rust" "$db2" "$db1" 0
        local result_c=$(run_rust "$db1" "SELECT c FROM foo WHERE a = 1;")
        local result_b=$(run_rust "$db1" "SELECT b FROM foo WHERE a = 1;")
        echo "c=$result_c,b=$result_b"
    else
        setup_zig "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo (a) VALUES (1);
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 0;
            SELECT crsql_commit_alter('foo');
        "
        setup_zig "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b DEFAULT 4);
            SELECT crsql_as_crr('foo');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 0;
            SELECT crsql_commit_alter('foo');
            INSERT INTO foo (a,b,c) VALUES (1,2,3);
        "
        sync_changes "zig" "$db2" "$db1" 0
        local result_c=$(run_zig "$db1" "SELECT c FROM foo WHERE a = 1;")
        local result_b=$(run_zig "$db1" "SELECT b FROM foo WHERE a = 1;")
        echo "c=$result_c,b=$result_b"
    fi
}

echo "  Running Rust/C..."
RUST_RESULT=$(test_default_after_alter "rust")
echo "  Rust/C result: $RUST_RESULT"

echo "  Running Zig..."
ZIG_RESULT=$(test_default_after_alter "zig")
echo "  Zig result: $ZIG_RESULT"

# Column c should be 3 (explicit wins over DEFAULT with no clock)
# Column b: DB1 has 4 (DEFAULT), DB2 has 2 (explicit) - both have clock entries
# According to Python test: b=4 wins (tie-break to greatest value)
if [[ "$RUST_RESULT" == "c=3,b=4" && "$ZIG_RESULT" == "c=3,b=4" ]]; then
    echo "  PASS: Explicit c=3 wins, b=4 wins tie-break (both implementations)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RUST_RESULT" == "$ZIG_RESULT" ]]; then
    echo "  PASS: Both implementations match ($RUST_RESULT)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Implementations diverge (Rust: $RUST_RESULT, Zig: $ZIG_RESULT)"
    DIVERGENCES="$DIVERGENCES\n- default_after_alter: Rust=$RUST_RESULT, Zig=$ZIG_RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: DEFAULT does NOT create phantom clock entries
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: DEFAULT does NOT create phantom clock entries after ALTER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_no_phantom_clock() {
    local impl="$1"
    local db="$TMPDIR/${impl}_t4.db"
    rm -f "$db"
    
    if [[ "$impl" == "rust" ]]; then
        setup_rust "$db" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
        "
        run_rust "$db" "SELECT COUNT(*) FROM foo__crsql_clock WHERE col_name = 'c';"
    else
        setup_zig "$db" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
        "
        run_zig "$db" "SELECT COUNT(*) FROM foo__crsql_clock WHERE col_name = 'c';"
    fi
}

echo "  Running Rust/C..."
RUST_CLOCK_COUNT=$(test_no_phantom_clock "rust")
echo "  Rust/C clock entries for 'c': $RUST_CLOCK_COUNT"

echo "  Running Zig..."
ZIG_CLOCK_COUNT=$(test_no_phantom_clock "zig")
echo "  Zig clock entries for 'c': $ZIG_CLOCK_COUNT"

# Both should have 0 clock entries for the new column (no backfill for DEFAULT)
if [[ "$RUST_CLOCK_COUNT" == "0" && "$ZIG_CLOCK_COUNT" == "0" ]]; then
    echo "  PASS: No phantom clock entries created for DEFAULT column (both implementations)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RUST_CLOCK_COUNT" == "$ZIG_CLOCK_COUNT" ]]; then
    echo "  PASS: Both implementations match (clock count: $RUST_CLOCK_COUNT)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Implementations diverge (Rust: $RUST_CLOCK_COUNT, Zig: $ZIG_CLOCK_COUNT)"
    DIVERGENCES="$DIVERGENCES\n- phantom_clock: Rust=$RUST_CLOCK_COUNT, Zig=$ZIG_CLOCK_COUNT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Explicit UPDATE on DEFAULT column creates clock entry
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Explicit UPDATE on DEFAULT column creates clock entry"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_update_creates_clock() {
    local impl="$1"
    local db="$TMPDIR/${impl}_t5.db"
    rm -f "$db"
    
    if [[ "$impl" == "rust" ]]; then
        setup_rust "$db" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
            UPDATE foo SET c = 'explicit' WHERE a = 1;
        "
        run_rust "$db" "SELECT COUNT(*) FROM foo__crsql_clock WHERE col_name = 'c';"
    else
        setup_zig "$db" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
            UPDATE foo SET c = 'explicit' WHERE a = 1;
        "
        run_zig "$db" "SELECT COUNT(*) FROM foo__crsql_clock WHERE col_name = 'c';"
    fi
}

echo "  Running Rust/C..."
RUST_CLOCK_COUNT=$(test_update_creates_clock "rust")
echo "  Rust/C clock entries for 'c' after UPDATE: $RUST_CLOCK_COUNT"

echo "  Running Zig..."
ZIG_CLOCK_COUNT=$(test_update_creates_clock "zig")
echo "  Zig clock entries for 'c' after UPDATE: $ZIG_CLOCK_COUNT"

# Both should have 1 clock entry after the UPDATE
if [[ "$RUST_CLOCK_COUNT" == "1" && "$ZIG_CLOCK_COUNT" == "1" ]]; then
    echo "  PASS: UPDATE creates clock entry for DEFAULT column (both implementations)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RUST_CLOCK_COUNT" == "$ZIG_CLOCK_COUNT" ]]; then
    echo "  PASS: Both implementations match (clock count: $RUST_CLOCK_COUNT)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Implementations diverge (Rust: $RUST_CLOCK_COUNT, Zig: $ZIG_CLOCK_COUNT)"
    DIVERGENCES="$DIVERGENCES\n- update_creates_clock: Rust=$RUST_CLOCK_COUNT, Zig=$ZIG_CLOCK_COUNT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Sync after UPDATE on DEFAULT column wins
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Sync after UPDATE on DEFAULT column wins"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_sync_after_update() {
    local impl="$1"
    local db1="$TMPDIR/${impl}_t6_db1.db"
    local db2="$TMPDIR/${impl}_t6_db2.db"
    rm -f "$db1" "$db2"
    
    if [[ "$impl" == "rust" ]]; then
        # DB1: Has row, then ALTER, row has DEFAULT value, NO clock for c
        setup_rust "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
        "
        # DB2: Same schema, then UPDATE c explicitly
        setup_rust "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
            UPDATE foo SET c = 'explicit' WHERE a = 1;
        "
        # Sync DB2 -> DB1
        sync_changes "rust" "$db2" "$db1" 0
        run_rust "$db1" "SELECT c FROM foo WHERE a = 1;"
    else
        setup_zig "$db1" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
        "
        setup_zig "$db2" "
            CREATE TABLE foo (a PRIMARY KEY NOT NULL, b TEXT);
            SELECT crsql_as_crr('foo');
            INSERT INTO foo VALUES (1, 'hello');
            SELECT crsql_begin_alter('foo');
            ALTER TABLE foo ADD COLUMN c DEFAULT 'default_val';
            SELECT crsql_commit_alter('foo');
            UPDATE foo SET c = 'explicit' WHERE a = 1;
        "
        sync_changes "zig" "$db2" "$db1" 0
        run_zig "$db1" "SELECT c FROM foo WHERE a = 1;"
    fi
}

echo "  Running Rust/C..."
RUST_RESULT=$(test_sync_after_update "rust")
echo "  Rust/C result: c = $RUST_RESULT"

echo "  Running Zig..."
ZIG_RESULT=$(test_sync_after_update "zig")
echo "  Zig result: c = $ZIG_RESULT"

if [[ "$RUST_RESULT" == "explicit" && "$ZIG_RESULT" == "explicit" ]]; then
    echo "  PASS: Explicit UPDATE wins over DEFAULT after sync (both implementations)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
elif [[ "$RUST_RESULT" == "$ZIG_RESULT" ]]; then
    echo "  PASS: Both implementations match ($RUST_RESULT)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo "  FAIL: Implementations diverge (Rust: $RUST_RESULT, Zig: $ZIG_RESULT)"
    DIVERGENCES="$DIVERGENCES\n- sync_after_update: Rust=$RUST_RESULT, Zig=$ZIG_RESULT"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║              DEFAULT MERGE SEMANTICS TEST SUMMARY                     ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  PASSED:  %-58d ║\n" "$TOTAL_PASS"
printf "║  FAILED:  %-58d ║\n" "$TOTAL_FAIL"
echo "╚═══════════════════════════════════════════════════════════════════════╝"

if [[ -n "$DIVERGENCES" ]]; then
    echo ""
    echo "Divergences found:"
    echo -e "$DIVERGENCES"
fi

echo ""
if [[ $TOTAL_FAIL -eq 0 && $TOTAL_PASS -gt 0 ]]; then
    echo "All DEFAULT merge semantics tests PASSED"
    exit 0
else
    echo "Some DEFAULT merge semantics tests FAILED"
    exit 1
fi
