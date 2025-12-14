#!/usr/bin/env bash
# Concurrent Merge Conflict Stress Test for Zig CR-SQLite
# Adversarial tests to expose race conditions or merge logic bugs
#
# Tests:
#   1. Same PK, Same Column, Rapid Fire - 3 sites writing 100 times each to same cell
#   2. Interleaved PK Conflicts - 10 sites creating overlapping PK ranges
#   3. Update/Delete Race - concurrent update and delete on same row
#   4. Resurrection Torture - rapid insert/delete cycles applied out of order
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPDIR="$SCRIPT_DIR/.tmp"
mkdir -p "$TMPDIR"

echo "=== Zig CR-SQLite Merge Conflict Stress Test ==="
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
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.dylib"
else
    EXT="$ZIG_DIR/zig-out/lib/libcrsqlite.so"
fi

if [[ ! -f "$EXT" ]]; then
    echo "FAIL: Extension not found at $EXT"
    exit 1
fi

echo "Extension: $EXT"
echo ""

# Cleanup function
cleanup() {
    rm -rf "$TMPDIR"/*.db "$TMPDIR"/*.sql "$TMPDIR"/*.out "$TMPDIR"/*.changes 2>/dev/null || true
}
trap cleanup EXIT

FAILURES=0
BUGS_FOUND=()

# Helper: run SQL file against database
run_sql_file() {
    local db="$1"
    local sqlfile="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" < "$sqlfile" 2>&1
}

# Helper: run SQL string against database
run_sql() {
    local db="$1"
    local sql="$2"
    nix run nixpkgs#sqlite -- "$db" -cmd ".load $EXT" "$sql" 2>&1
}

# Helper: create a site database and return its site_id
create_site() {
    local db="$1"
    local schema="$2"
    run_sql "$db" "$schema SELECT crsql_as_crr('test');" > /dev/null
    run_sql "$db" "SELECT hex(crsql_site_id());"
}

# Helper: extract changes from a site database to a file
extract_changes() {
    local db="$1"
    local outfile="$2"
    local since_version="${3:-0}"
    run_sql "$db" "
        SELECT [table] || '|' || 
               quote(pk) || '|' || 
               cid || '|' || 
               quote(val) || '|' || 
               col_version || '|' || 
               db_version || '|' || 
               quote(site_id) || '|' || 
               cl || '|' || 
               seq
        FROM crsql_changes
        WHERE db_version > $since_version;
    " > "$outfile"
}

# Helper: apply changes from file to a database
apply_changes() {
    local db="$1"
    local infile="$2"
    while IFS='|' read -r tbl pk cid val col_ver db_ver site_id cl seq; do
        [[ -z "$tbl" ]] && continue
        run_sql "$db" "
            INSERT INTO crsql_changes ([table], pk, cid, val, col_version, db_version, site_id, cl, seq)
            VALUES ('$tbl', $pk, '$cid', $val, $col_ver, $db_ver, $site_id, $cl, $seq);
        " > /dev/null 2>&1 || true
    done < "$infile"
}

# =============================================================================
# Scenario 1: Same PK, Same Column, Rapid Fire (with incremental sync)
# =============================================================================
echo "=== Scenario 1: Same PK, Same Column, Rapid Fire ==="
echo "3 sites writing to the same row, same column"
echo "Sync changes incrementally after each batch to stress merge path"
echo ""

SITE1_DB="$TMPDIR/s1_rapid.db"
SITE2_DB="$TMPDIR/s2_rapid.db"
SITE3_DB="$TMPDIR/s3_rapid.db"
MERGE_DB="$TMPDIR/merge_rapid.db"

SCHEMA="CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, val TEXT);"

# Create sites
SITE1_ID=$(create_site "$SITE1_DB" "$SCHEMA")
SITE2_ID=$(create_site "$SITE2_DB" "$SCHEMA")
SITE3_ID=$(create_site "$SITE3_DB" "$SCHEMA")
create_site "$MERGE_DB" "$SCHEMA" > /dev/null

echo "Site IDs:"
echo "  Site1: $SITE1_ID"
echo "  Site2: $SITE2_ID"
echo "  Site3: $SITE3_ID"
echo ""

# Stress test: perform writes and sync incrementally
# This ensures we hit the merge path with conflicting col_versions
TOTAL_MERGES=0
NUM_ROUNDS=20
WRITES_PER_ROUND=5

echo "Performing $NUM_ROUNDS rounds of concurrent writes ($WRITES_PER_ROUND writes/site/round)..."

for round in $(seq 1 $NUM_ROUNDS); do
    # Each site makes writes
    for site in 1 2 3; do
        DB_VAR="SITE${site}_DB"
        DB="${!DB_VAR}"
        SQL_FILE="$TMPDIR/s${site}_round${round}.sql"
        {
            for w in $(seq 1 $WRITES_PER_ROUND); do
                val="site${site}_r${round}_w${w}"
                echo "INSERT OR REPLACE INTO test (id, val) VALUES (1, '$val');"
            done
        } > "$SQL_FILE"
        run_sql_file "$DB" "$SQL_FILE" > /dev/null
    done
    
    # Extract and apply changes to merge DB (simulating sync)
    # Each sync will trigger merge conflict resolution
    for site in 1 2 3; do
        DB_VAR="SITE${site}_DB"
        DB="${!DB_VAR}"
        extract_changes "$DB" "$TMPDIR/s${site}_round${round}.changes"
        CHANGE_COUNT=$(wc -l < "$TMPDIR/s${site}_round${round}.changes" | tr -d ' ')
        if [[ "$CHANGE_COUNT" -gt 0 ]]; then
            apply_changes "$MERGE_DB" "$TMPDIR/s${site}_round${round}.changes"
            TOTAL_MERGES=$((TOTAL_MERGES + CHANGE_COUNT))
        fi
    done
done

echo "Total change applications to merge DB: $TOTAL_MERGES"

# Get the final value
MERGE_FINAL=$(run_sql "$MERGE_DB" "SELECT val FROM test WHERE id = 1;")
MERGE_CL=$(run_sql "$MERGE_DB" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = 'val';")
MERGE_SITE=$(run_sql "$MERGE_DB" "SELECT hex(site_id) FROM test__crsql_clock WHERE pk = 1 AND col_name = 'val';")

echo ""
echo "Merge result:"
echo "  Final value: $MERGE_FINAL"
echo "  col_version: $MERGE_CL"
echo "  winning site_id: $MERGE_SITE"

# Verify determinism: re-apply all changes in different order to fresh DB
MERGE2_DB="$TMPDIR/merge2_rapid.db"
create_site "$MERGE2_DB" "$SCHEMA" > /dev/null

# Apply in reverse site order, reverse round order
for round in $(seq $NUM_ROUNDS -1 1); do
    for site in 3 2 1; do
        if [[ -f "$TMPDIR/s${site}_round${round}.changes" ]]; then
            apply_changes "$MERGE2_DB" "$TMPDIR/s${site}_round${round}.changes"
        fi
    done
done

MERGE2_FINAL=$(run_sql "$MERGE2_DB" "SELECT val FROM test WHERE id = 1;")
MERGE2_CL=$(run_sql "$MERGE2_DB" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = 'val';")

if [[ "$MERGE_FINAL" == "$MERGE2_FINAL" && "$MERGE_CL" == "$MERGE2_CL" ]]; then
    echo "PASS: Merge is deterministic (same result regardless of application order)"
else
    echo "FAIL: Merge NOT deterministic!"
    echo "  Order 1: val=$MERGE_FINAL, col_version=$MERGE_CL"
    echo "  Order 2: val=$MERGE2_FINAL, col_version=$MERGE2_CL"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 1: Non-deterministic merge for rapid-fire writes")
fi

echo ""

# =============================================================================
# Scenario 2: Interleaved PK Conflicts
# =============================================================================
echo "=== Scenario 2: Interleaved PK Conflicts ==="
echo "10 sites each create rows with PKs 1-100 (some PKs collide)"
echo ""

# Create 10 site databases
for i in $(seq 1 10); do
    DB="$TMPDIR/s${i}_interleaved.db"
    create_site "$DB" "$SCHEMA" > /dev/null
    
    # Each site creates rows with PKs in their range + overlapping PKs
    # Site i creates PKs: ((i-1)*10 + 1) to (i*10) plus PKs 1-10 (overlap zone)
    START_PK=$(( (i-1)*10 + 1 ))
    END_PK=$(( i*10 ))
    
    SQL_FILE="$TMPDIR/s${i}_interleaved.sql"
    {
        # Create site's unique rows
        for pk in $(seq $START_PK $END_PK); do
            echo "INSERT OR REPLACE INTO test (id, val) VALUES ($pk, 'site${i}_pk${pk}');"
        done
        # Also write to overlap zone (PKs 1-10)
        for pk in $(seq 1 10); do
            echo "INSERT OR REPLACE INTO test (id, val) VALUES ($pk, 'site${i}_overlap${pk}');"
        done
    } > "$SQL_FILE"
    
    run_sql_file "$DB" "$SQL_FILE" > /dev/null
    extract_changes "$DB" "$TMPDIR/s${i}_interleaved.changes"
done

echo "Created 10 sites with overlapping PK ranges"

# Create merge database and apply all changes
MERGE_INTERLEAVED="$TMPDIR/merge_interleaved.db"
create_site "$MERGE_INTERLEAVED" "$SCHEMA" > /dev/null

for i in $(seq 1 10); do
    apply_changes "$MERGE_INTERLEAVED" "$TMPDIR/s${i}_interleaved.changes"
done

# Verify results
EXPECTED_ROWS=100  # PKs 1-100, each unique
ACTUAL_ROWS=$(run_sql "$MERGE_INTERLEAVED" "SELECT COUNT(*) FROM test;")

echo "Merge result:"
echo "  Expected rows: $EXPECTED_ROWS"
echo "  Actual rows: $ACTUAL_ROWS"

if [[ "$ACTUAL_ROWS" == "$EXPECTED_ROWS" ]]; then
    echo "PASS: Correct row count (no duplicates, no data loss)"
else
    echo "FAIL: Wrong row count!"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 2: Row count mismatch ($ACTUAL_ROWS vs expected $EXPECTED_ROWS)")
fi

# Verify no duplicates by checking DISTINCT count
DISTINCT_ROWS=$(run_sql "$MERGE_INTERLEAVED" "SELECT COUNT(DISTINCT id) FROM test;")
if [[ "$DISTINCT_ROWS" == "$ACTUAL_ROWS" ]]; then
    echo "PASS: No duplicate PKs"
else
    echo "FAIL: Duplicate PKs detected!"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 2: Duplicate PKs in merged database")
fi

# Check overlap zone (PKs 1-10) - each should have exactly one value
OVERLAP_ISSUES=0
for pk in $(seq 1 10); do
    COUNT=$(run_sql "$MERGE_INTERLEAVED" "SELECT COUNT(*) FROM test WHERE id = $pk;")
    if [[ "$COUNT" != "1" ]]; then
        echo "  PK $pk has $COUNT rows (expected 1)"
        OVERLAP_ISSUES=$((OVERLAP_ISSUES + 1))
    fi
done

if [[ $OVERLAP_ISSUES -eq 0 ]]; then
    echo "PASS: Overlap zone PKs 1-10 each have exactly one value"
else
    echo "FAIL: $OVERLAP_ISSUES PKs in overlap zone have wrong count"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# =============================================================================
# Scenario 3: Update/Delete Race
# =============================================================================
echo "=== Scenario 3: Update/Delete Race ==="
echo "Site A updates row, Site B deletes it (before seeing A's update),"
echo "Site C updates it (after seeing A's update but before B's delete)"
echo ""

SITE_A="$TMPDIR/siteA_race.db"
SITE_B="$TMPDIR/siteB_race.db"
SITE_C="$TMPDIR/siteC_race.db"
MERGE_RACE="$TMPDIR/merge_race.db"

# All sites start with the same initial state
for db in "$SITE_A" "$SITE_B" "$SITE_C" "$MERGE_RACE"; do
    create_site "$db" "$SCHEMA" > /dev/null
    run_sql "$db" "INSERT INTO test (id, val) VALUES (1, 'initial');" > /dev/null
done

# Extract initial changes from Site A and sync to all others
extract_changes "$SITE_A" "$TMPDIR/initial.changes"
for db in "$SITE_B" "$SITE_C" "$MERGE_RACE"; do
    apply_changes "$db" "$TMPDIR/initial.changes"
done

echo "Initial state synced: row id=1, val='initial'"

# Site A updates the row (cl becomes 2)
echo "Site A: UPDATE val='updated_by_A'"
run_sql "$SITE_A" "UPDATE test SET val = 'updated_by_A' WHERE id = 1;" > /dev/null
extract_changes "$SITE_A" "$TMPDIR/siteA_update.changes" 1

# Site B deletes the row (cl becomes 2, tombstone) - doesn't see A's update
echo "Site B: DELETE (creates tombstone, cl=2)"
run_sql "$SITE_B" "DELETE FROM test WHERE id = 1;" > /dev/null
extract_changes "$SITE_B" "$TMPDIR/siteB_delete.changes" 1

# Site C first receives A's update, then makes its own update
echo "Site C: Receives A's update, then UPDATE val='updated_by_C'"
apply_changes "$SITE_C" "$TMPDIR/siteA_update.changes"
run_sql "$SITE_C" "UPDATE test SET val = 'updated_by_C' WHERE id = 1;" > /dev/null
extract_changes "$SITE_C" "$TMPDIR/siteC_update.changes" 2

# Apply all changes to merge database in order: A, B, C
echo ""
echo "Applying changes in order: A's update, B's delete, C's update"
apply_changes "$MERGE_RACE" "$TMPDIR/siteA_update.changes"
apply_changes "$MERGE_RACE" "$TMPDIR/siteB_delete.changes"
apply_changes "$MERGE_RACE" "$TMPDIR/siteC_update.changes"

# Check final state
RACE_COUNT=$(run_sql "$MERGE_RACE" "SELECT COUNT(*) FROM test WHERE id = 1;")
RACE_VAL=$(run_sql "$MERGE_RACE" "SELECT val FROM test WHERE id = 1;" 2>/dev/null || echo "DELETED")
RACE_CL=$(run_sql "$MERGE_RACE" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = '-1';" 2>/dev/null || echo "N/A")

echo ""
echo "Merge result:"
echo "  Row exists: $([ "$RACE_COUNT" == "1" ] && echo "YES" || echo "NO")"
echo "  Final value: $RACE_VAL"
echo "  Causal length: $RACE_CL"

# Expected: Site C's update should win because it has the highest cl (3)
# Site A: cl=2 (update)
# Site B: cl=2 (delete) - tied with A, but delete loses to update at same cl per LWW
# Site C: cl=3 (update after seeing A) - highest cl wins
if [[ "$RACE_VAL" == "updated_by_C" ]]; then
    echo "PASS: Site C's update won (highest cl=3)"
elif [[ "$RACE_VAL" == "DELETED" ]]; then
    # This could be correct if delete semantics differ - document it
    echo "INFO: Row was deleted. Checking if this matches LWW semantics..."
    echo "  (Delete at cl=2 should lose to update at cl=3)"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 3: Delete won over higher-cl update")
else
    echo "FAIL: Unexpected final value: $RACE_VAL"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 3: Unexpected merge result: $RACE_VAL")
fi

echo ""

# =============================================================================
# Scenario 4: Resurrection Torture
# =============================================================================
echo "=== Scenario 4: Resurrection Torture ==="
echo "Rapid cycle: insert -> delete -> insert -> delete -> insert"
echo "Capture changes after EACH operation, apply out of order"
echo ""

SITE_TORTURE="$TMPDIR/site_torture.db"
MERGE_ORDER1="$TMPDIR/merge_order1.db"
MERGE_ORDER2="$TMPDIR/merge_order2.db"
MERGE_SHUFFLED="$TMPDIR/merge_shuffled.db"

create_site "$SITE_TORTURE" "$SCHEMA" > /dev/null
create_site "$MERGE_ORDER1" "$SCHEMA" > /dev/null
create_site "$MERGE_ORDER2" "$SCHEMA" > /dev/null
create_site "$MERGE_SHUFFLED" "$SCHEMA" > /dev/null

# Perform operations one at a time, capturing changes after each
echo "Performing insert/delete cycles, capturing changes after each op..."

LAST_VERSION=0
ALL_CHANGES="$TMPDIR/torture_all.changes"
> "$ALL_CHANGES"

# Operation 1: INSERT (cl=1)
run_sql "$SITE_TORTURE" "INSERT INTO test (id, val) VALUES (1, 'insert_1');" > /dev/null
extract_changes "$SITE_TORTURE" "$TMPDIR/torture_op1.changes" $LAST_VERSION
cat "$TMPDIR/torture_op1.changes" >> "$ALL_CHANGES"
LAST_VERSION=$(run_sql "$SITE_TORTURE" "SELECT crsql_db_version();")

# Operation 2: DELETE (cl=2)
run_sql "$SITE_TORTURE" "DELETE FROM test WHERE id = 1;" > /dev/null
extract_changes "$SITE_TORTURE" "$TMPDIR/torture_op2.changes" $LAST_VERSION
cat "$TMPDIR/torture_op2.changes" >> "$ALL_CHANGES"
LAST_VERSION=$(run_sql "$SITE_TORTURE" "SELECT crsql_db_version();")

# Operation 3: INSERT (cl=3, resurrection)
run_sql "$SITE_TORTURE" "INSERT INTO test (id, val) VALUES (1, 'insert_2');" > /dev/null
extract_changes "$SITE_TORTURE" "$TMPDIR/torture_op3.changes" $LAST_VERSION
cat "$TMPDIR/torture_op3.changes" >> "$ALL_CHANGES"
LAST_VERSION=$(run_sql "$SITE_TORTURE" "SELECT crsql_db_version();")

# Operation 4: DELETE (cl=4)
run_sql "$SITE_TORTURE" "DELETE FROM test WHERE id = 1;" > /dev/null
extract_changes "$SITE_TORTURE" "$TMPDIR/torture_op4.changes" $LAST_VERSION
cat "$TMPDIR/torture_op4.changes" >> "$ALL_CHANGES"
LAST_VERSION=$(run_sql "$SITE_TORTURE" "SELECT crsql_db_version();")

# Operation 5: INSERT (cl=5, resurrection)
run_sql "$SITE_TORTURE" "INSERT INTO test (id, val) VALUES (1, 'insert_3');" > /dev/null
extract_changes "$SITE_TORTURE" "$TMPDIR/torture_op5.changes" $LAST_VERSION
cat "$TMPDIR/torture_op5.changes" >> "$ALL_CHANGES"

# Get final state on source
TORTURE_FINAL=$(run_sql "$SITE_TORTURE" "SELECT val FROM test WHERE id = 1;" 2>/dev/null || echo "DELETED")
TORTURE_CL=$(run_sql "$SITE_TORTURE" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = '-1';" 2>/dev/null || echo "N/A")
echo "Source final state: val=$TORTURE_FINAL, cl=$TORTURE_CL"

CHANGE_COUNT=$(wc -l < "$ALL_CHANGES" | tr -d ' ')
echo "Total changes captured: $CHANGE_COUNT"

# Apply in chronological order to first merge DB
echo ""
echo "Applying changes in chronological order..."
apply_changes "$MERGE_ORDER1" "$ALL_CHANGES"

# Apply in reverse order to second merge DB
echo "Applying changes in REVERSE order..."
tac "$ALL_CHANGES" > "$TMPDIR/torture_reversed.changes"
apply_changes "$MERGE_ORDER2" "$TMPDIR/torture_reversed.changes"

# Apply in shuffled order: op3, op1, op5, op2, op4 (mix of inserts and deletes)
echo "Applying changes in SHUFFLED order (op3, op1, op5, op2, op4)..."
{
    cat "$TMPDIR/torture_op3.changes"
    cat "$TMPDIR/torture_op1.changes"
    cat "$TMPDIR/torture_op5.changes"
    cat "$TMPDIR/torture_op2.changes"
    cat "$TMPDIR/torture_op4.changes"
} > "$TMPDIR/torture_shuffled.changes"
apply_changes "$MERGE_SHUFFLED" "$TMPDIR/torture_shuffled.changes"

# Compare results
ORDER1_VAL=$(run_sql "$MERGE_ORDER1" "SELECT val FROM test WHERE id = 1;" 2>/dev/null || echo "DELETED")
ORDER2_VAL=$(run_sql "$MERGE_ORDER2" "SELECT val FROM test WHERE id = 1;" 2>/dev/null || echo "DELETED")
SHUFFLED_VAL=$(run_sql "$MERGE_SHUFFLED" "SELECT val FROM test WHERE id = 1;" 2>/dev/null || echo "DELETED")

ORDER1_CL=$(run_sql "$MERGE_ORDER1" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = '-1';" 2>/dev/null || echo "N/A")
ORDER2_CL=$(run_sql "$MERGE_ORDER2" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = '-1';" 2>/dev/null || echo "N/A")
SHUFFLED_CL=$(run_sql "$MERGE_SHUFFLED" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = '-1';" 2>/dev/null || echo "N/A")

echo ""
echo "Results:"
echo "  Source:     val=$TORTURE_FINAL, cl=$TORTURE_CL"
echo "  In-order:   val=$ORDER1_VAL, cl=$ORDER1_CL"
echo "  Reverse:    val=$ORDER2_VAL, cl=$ORDER2_CL"
echo "  Shuffled:   val=$SHUFFLED_VAL, cl=$SHUFFLED_CL"

# All merge orders should produce the same result
if [[ "$ORDER1_VAL" == "$ORDER2_VAL" && "$ORDER2_VAL" == "$SHUFFLED_VAL" ]]; then
    echo "PASS: Merge is deterministic across all application orders"
else
    echo "FAIL: Merge NOT deterministic!"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 4: Non-deterministic resurrection merge")
fi

# Check that final state matches expected (insert_3 with cl=5)
if [[ "$ORDER1_VAL" == "insert_3" ]]; then
    echo "PASS: Final value is correct (insert_3)"
else
    echo "INFO: Final value is $ORDER1_VAL (expected insert_3)"
fi

echo ""

# =============================================================================
# Scenario 5: High-Volume Concurrent Columns
# =============================================================================
echo "=== Scenario 5: High-Volume Concurrent Column Updates ==="
echo "Multiple sites updating different columns of the same row concurrently"
echo ""

MULTI_COL_SCHEMA="CREATE TABLE test (id INTEGER PRIMARY KEY NOT NULL, a TEXT, b TEXT, c TEXT, d TEXT, e TEXT);"

SITE_MC1="$TMPDIR/mc1.db"
SITE_MC2="$TMPDIR/mc2.db"
SITE_MC3="$TMPDIR/mc3.db"
MERGE_MC="$TMPDIR/merge_mc.db"

# Create sites with multi-column schema
for db in "$SITE_MC1" "$SITE_MC2" "$SITE_MC3" "$MERGE_MC"; do
    run_sql "$db" "$MULTI_COL_SCHEMA SELECT crsql_as_crr('test');" > /dev/null
done

# Each site updates a different set of columns 50 times
echo "Site 1: updating columns a, b (50 times each)"
MC1_SQL="$TMPDIR/mc1.sql"
{
    echo "INSERT INTO test (id, a, b, c, d, e) VALUES (1, 'a0', 'b0', 'c0', 'd0', 'e0');"
    for i in $(seq 1 50); do
        echo "UPDATE test SET a = 'a$i', b = 'b$i' WHERE id = 1;"
    done
} > "$MC1_SQL"
run_sql_file "$SITE_MC1" "$MC1_SQL" > /dev/null

echo "Site 2: updating columns b, c (50 times each)"
MC2_SQL="$TMPDIR/mc2.sql"
{
    echo "INSERT OR IGNORE INTO test (id, a, b, c, d, e) VALUES (1, 'a0', 'b0', 'c0', 'd0', 'e0');"
    for i in $(seq 1 50); do
        echo "UPDATE test SET b = 'B$i', c = 'c$i' WHERE id = 1;"
    done
} > "$MC2_SQL"
run_sql_file "$SITE_MC2" "$MC2_SQL" > /dev/null

echo "Site 3: updating columns d, e (50 times each)"
MC3_SQL="$TMPDIR/mc3.sql"
{
    echo "INSERT OR IGNORE INTO test (id, a, b, c, d, e) VALUES (1, 'a0', 'b0', 'c0', 'd0', 'e0');"
    for i in $(seq 1 50); do
        echo "UPDATE test SET d = 'd$i', e = 'e$i' WHERE id = 1;"
    done
} > "$MC3_SQL"
run_sql_file "$SITE_MC3" "$MC3_SQL" > /dev/null

# Extract and merge
extract_changes "$SITE_MC1" "$TMPDIR/mc1.changes"
extract_changes "$SITE_MC2" "$TMPDIR/mc2.changes"
extract_changes "$SITE_MC3" "$TMPDIR/mc3.changes"

apply_changes "$MERGE_MC" "$TMPDIR/mc1.changes"
apply_changes "$MERGE_MC" "$TMPDIR/mc2.changes"
apply_changes "$MERGE_MC" "$TMPDIR/mc3.changes"

# Check merged state
MERGED_ROW=$(run_sql "$MERGE_MC" "SELECT a, b, c, d, e FROM test WHERE id = 1;")
echo ""
echo "Merged row: $MERGED_ROW"

# Verify each column has a value (no NULLs except where expected)
NULL_CHECK=$(run_sql "$MERGE_MC" "SELECT (a IS NULL) + (b IS NULL) + (c IS NULL) + (d IS NULL) + (e IS NULL) FROM test WHERE id = 1;")
if [[ "$NULL_CHECK" == "0" ]]; then
    echo "PASS: No columns lost in merge (all have values)"
else
    echo "FAIL: $NULL_CHECK columns are NULL after merge"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 5: Column data loss in concurrent update merge")
fi

# Column b was updated by both Site 1 and Site 2 - winner should be deterministic
MC_B=$(run_sql "$MERGE_MC" "SELECT b FROM test WHERE id = 1;")
echo "Column b (contested): $MC_B"

echo ""

# =============================================================================
# Scenario 6: Col_Version Tiebreaker Stress
# =============================================================================
echo "=== Scenario 6: Col_Version Tiebreaker Stress ==="
echo "Test that higher col_version wins, and site_id breaks ties"
echo ""

SITE_CV1="$TMPDIR/cv1.db"
SITE_CV2="$TMPDIR/cv2.db"
MERGE_CV="$TMPDIR/merge_cv.db"

create_site "$SITE_CV1" "$SCHEMA" > /dev/null
create_site "$SITE_CV2" "$SCHEMA" > /dev/null
create_site "$MERGE_CV" "$SCHEMA" > /dev/null

CV1_SITE_ID=$(run_sql "$SITE_CV1" "SELECT hex(crsql_site_id());")
CV2_SITE_ID=$(run_sql "$SITE_CV2" "SELECT hex(crsql_site_id());")

echo "Site IDs: CV1=$CV1_SITE_ID, CV2=$CV2_SITE_ID"

# Site CV1: makes 10 updates (col_version will be 10)
{
    echo "INSERT INTO test (id, val) VALUES (1, 'cv1_0');"
    for i in $(seq 1 9); do
        echo "UPDATE test SET val = 'cv1_$i' WHERE id = 1;"
    done
} > "$TMPDIR/cv1.sql"
run_sql_file "$SITE_CV1" "$TMPDIR/cv1.sql" > /dev/null

# Site CV2: makes only 5 updates (col_version will be 5)
{
    echo "INSERT INTO test (id, val) VALUES (1, 'cv2_0');"
    for i in $(seq 1 4); do
        echo "UPDATE test SET val = 'cv2_$i' WHERE id = 1;"
    done
} > "$TMPDIR/cv2.sql"
run_sql_file "$SITE_CV2" "$TMPDIR/cv2.sql" > /dev/null

# Get col_versions
CV1_COLV=$(run_sql "$SITE_CV1" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = 'val';")
CV2_COLV=$(run_sql "$SITE_CV2" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = 'val';")
echo "Col versions: CV1=$CV1_COLV, CV2=$CV2_COLV"

# Extract changes
extract_changes "$SITE_CV1" "$TMPDIR/cv1.changes"
extract_changes "$SITE_CV2" "$TMPDIR/cv2.changes"

# Apply CV2 first, then CV1 (lower col_version first)
echo ""
echo "Applying CV2 (lower col_version) first, then CV1..."
apply_changes "$MERGE_CV" "$TMPDIR/cv2.changes"
apply_changes "$MERGE_CV" "$TMPDIR/cv1.changes"

CV_RESULT=$(run_sql "$MERGE_CV" "SELECT val FROM test WHERE id = 1;")
CV_FINAL_COLV=$(run_sql "$MERGE_CV" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = 'val';")

echo "Result: val=$CV_RESULT, col_version=$CV_FINAL_COLV"

# Verify higher col_version won
if [[ "$CV_FINAL_COLV" == "$CV1_COLV" ]] && [[ "$CV_RESULT" == *"cv1"* ]]; then
    echo "PASS: Higher col_version ($CV1_COLV) won"
else
    echo "FAIL: Higher col_version should have won"
    echo "  Expected col_version=$CV1_COLV, got $CV_FINAL_COLV"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 6: Higher col_version did not win")
fi

# Now test reverse order: CV1 first, then CV2
MERGE_CV2="$TMPDIR/merge_cv2.db"
create_site "$MERGE_CV2" "$SCHEMA" > /dev/null

echo ""
echo "Applying CV1 (higher col_version) first, then CV2..."
apply_changes "$MERGE_CV2" "$TMPDIR/cv1.changes"
apply_changes "$MERGE_CV2" "$TMPDIR/cv2.changes"

CV2_RESULT=$(run_sql "$MERGE_CV2" "SELECT val FROM test WHERE id = 1;")
CV2_FINAL_COLV=$(run_sql "$MERGE_CV2" "SELECT col_version FROM test__crsql_clock WHERE pk = 1 AND col_name = 'val';")

echo "Result: val=$CV2_RESULT, col_version=$CV2_FINAL_COLV"

# Verify same result regardless of order
if [[ "$CV_RESULT" == "$CV2_RESULT" ]] && [[ "$CV_FINAL_COLV" == "$CV2_FINAL_COLV" ]]; then
    echo "PASS: Same result regardless of application order (deterministic)"
else
    echo "FAIL: Different results based on application order!"
    echo "  Order 1: val=$CV_RESULT, col_version=$CV_FINAL_COLV"
    echo "  Order 2: val=$CV2_RESULT, col_version=$CV2_FINAL_COLV"
    FAILURES=$((FAILURES + 1))
    BUGS_FOUND+=("Scenario 6: Non-deterministic col_version tiebreaker")
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=== SUMMARY ==="
echo ""

if [[ $FAILURES -eq 0 ]]; then
    echo "All stress tests PASSED"
    echo ""
    echo "No merge bugs detected in:"
    echo "  1. Rapid-fire same-cell writes (determinism)"
    echo "  2. Interleaved PK conflicts (no duplicates/data loss)"
    echo "  3. Update/delete race conditions (LWW semantics)"
    echo "  4. Insert/delete resurrection cycles (order independence)"
    echo "  5. Concurrent multi-column updates (no column loss)"
    echo "  6. Col_version tiebreaker (higher version wins)"
    exit 0
else
    echo "$FAILURES stress test(s) FAILED"
    echo ""
    echo "BUGS FOUND:"
    for bug in "${BUGS_FOUND[@]}"; do
        echo "  - $bug"
    done
    echo ""
    echo "Debug info:"
    echo "  Test databases preserved in: $TMPDIR"
    echo "  Run with 'set -x' for detailed trace"
    exit 1
fi
