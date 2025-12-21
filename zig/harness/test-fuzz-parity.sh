#!/usr/bin/env bash
# Fuzz Parity Test: Stochastic invalidation of "full parity" hypothesis
#
# This test attempts to INVALIDATE the hypothesis that Zig and Rust/C CR-SQLite
# implementations have full behavioral parity by:
# 1. Generating random schemas (tables with random column types, PKs)
# 2. Generating random operations (INSERT, UPDATE, DELETE, transactions)
# 3. Running identical SQL against both implementations
# 4. Comparing: crsql_changes, crsql_db_version, crsql_site_id, table contents
#
# If any divergence is found, the test PASSES (we invalidated the hypothesis).
# If no divergence is found after N iterations, we document that finding.
set -euo pipefail

# Force C locale for consistent byte-level sorting of binary data
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ZIG_DIR/.." && pwd)"

# Configuration
ITERATIONS="${FUZZ_ITERATIONS:-100}"
SEED="${FUZZ_SEED:-$$}"
VERBOSE="${FUZZ_VERBOSE:-0}"
# Edge case modes: 0=random, 1=compound_pk, 2=nulls, 3=special_chars, 4=transactions
EDGE_MODE="${FUZZ_EDGE_MODE:-0}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Fuzz Parity Test: Stochastic Invalidation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Configuration:"
echo "  Iterations: $ITERATIONS"
echo "  Seed: $SEED"
echo "  Verbose: $VERBOSE"
echo "  Edge mode: $EDGE_MODE (0=random, 1=compound_pk, 2=nulls, 3=special_chars, 4=transactions)"
echo ""

# Initialize PRNG with seed (bash RANDOM)
RANDOM=$SEED

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

# Check for Zig extension (build if needed)
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
TMPDIR="${REPO_ROOT}/.tmp/fuzz-parity-$$"
mkdir -p "$TMPDIR"
# Only clean up if no divergences (set in summary section)
CLEANUP_ON_EXIT=1
cleanup() {
    if [[ $CLEANUP_ON_EXIT -eq 1 ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT

# Counters
PASS=0
FAIL=0
DIVERGENCES=0
DIVERGENCE_LOG="$TMPDIR/divergences.log"
touch "$DIVERGENCE_LOG"

# ═══════════════════════════════════════════════════════════════════════════════
# Random generators
# ═══════════════════════════════════════════════════════════════════════════════

# Generate a random column type
random_type() {
    local types=("INTEGER" "TEXT" "REAL" "BLOB")
    echo "${types[$((RANDOM % ${#types[@]}))]}"
}

# Generate a random value for a given type
# Supports: edge cases like NULL, empty strings, special chars
random_value() {
    local type="$1"
    local allow_null="${2:-1}"  # Allow NULL by default
    local mode="${EDGE_MODE:-0}"
    
    # Mode 2 or 10% chance: return NULL (if allowed)
    if [[ "$allow_null" == "1" ]] && { [[ "$mode" == "2" ]] || [[ $((RANDOM % 10)) -eq 0 ]]; }; then
        echo "NULL"
        return
    fi
    
    case "$type" in
        INTEGER)
            # Include edge cases: 0, -1, large numbers, boundaries
            local edge=$((RANDOM % 20))
            case $edge in
                0) echo "0" ;;
                1) echo "-1" ;;
                2) echo "2147483647" ;;   # INT_MAX
                3) echo "-2147483648" ;;  # INT_MIN
                4) echo "9223372036854775807" ;;  # BIGINT_MAX
                *) echo "$((RANDOM % 10000 - 5000))" ;;
            esac
            ;;
        TEXT)
            # Mode 3 or random: special characters
            if [[ "$mode" == "3" ]] || [[ $((RANDOM % 5)) -eq 0 ]]; then
                local specials=("''" "' '" "'hello''world'" "'line1\nline2'" "'tab\there'" "'emoji'" "'unicodé'" "'quotes\"here'" "'back\\slash'")
                echo "${specials[$((RANDOM % ${#specials[@]}))]}"
            else
                local words=("alpha" "beta" "gamma" "delta" "epsilon" "zeta" "eta" "theta")
                local word="${words[$((RANDOM % ${#words[@]}))]}"
                echo "'${word}_$((RANDOM % 100))'"
            fi
            ;;
        REAL)
            # Include edge cases: 0.0, negative, very small, very large
            local edge=$((RANDOM % 10))
            case $edge in
                0) echo "0.0" ;;
                1) echo "-0.0" ;;
                2) echo "1e-10" ;;
                3) echo "1e10" ;;
                *) echo "$((RANDOM % 1000)).$((RANDOM % 100))" ;;
            esac
            ;;
        BLOB)
            # Include edge cases: empty blob, single byte
            local edge=$((RANDOM % 10))
            case $edge in
                0) echo "X''" ;;  # Empty blob
                1) echo "X'00'" ;;  # Single null byte
                2) echo "X'FF'" ;;  # Single max byte
                *)
                    # Generate a small random hex blob
                    local len=$((RANDOM % 8 + 1))
                    local hex=""
                    for ((i=0; i<len; i++)); do
                        hex+=$(printf '%02X' $((RANDOM % 256)))
                    done
                    echo "X'$hex'"
                    ;;
            esac
            ;;
    esac
}

# Generate a random schema (1-5 columns + PK)
# Supports: simple PK, compound PK, nullable columns
generate_schema() {
    local table_name="$1"
    local mode="${EDGE_MODE:-0}"
    local num_cols=$((RANDOM % 4 + 1))  # 1-4 non-PK columns
    
    local cols=""
    local col_types=()
    local pk_cols=()
    local is_compound_pk=0
    
    # Mode 1 or 20% chance: compound primary key
    if [[ "$mode" == "1" ]] || [[ $((RANDOM % 5)) -eq 0 ]]; then
        is_compound_pk=1
        # Compound PK: 2-3 columns
        local num_pk_cols=$((RANDOM % 2 + 2))
        for ((i=1; i<=num_pk_cols; i++)); do
            local pk_type
            if [[ $((RANDOM % 2)) -eq 0 ]]; then
                pk_type="INTEGER"
            else
                pk_type="TEXT"
            fi
            [[ -n "$cols" ]] && cols+=", "
            cols+="pk$i $pk_type NOT NULL"
            col_types+=("$pk_type")
            pk_cols+=("pk$i")
        done
    else
        # Simple integer PK
        cols="id INTEGER PRIMARY KEY NOT NULL"
        col_types=("INTEGER")
        pk_cols=("id")
    fi
    
    # Add non-PK columns
    for ((i=1; i<=num_cols; i++)); do
        local col_type=$(random_type)
        [[ -n "$cols" ]] && cols+=", "
        # Mode 2 or 30% chance: nullable columns
        if [[ "$mode" == "2" ]] || [[ $((RANDOM % 3)) -eq 0 ]]; then
            cols+="col$i $col_type"  # No NOT NULL
        else
            cols+="col$i $col_type"
        fi
        col_types+=("$col_type")
    done
    
    # Add compound PK constraint if needed
    if [[ $is_compound_pk -eq 1 ]]; then
        local pk_list=$(IFS=','; echo "${pk_cols[*]}")
        cols+=", PRIMARY KEY ($pk_list)"
    fi
    
    echo "CREATE TABLE $table_name ($cols);"
    echo "TYPES:${col_types[*]}"
    echo "PKCOLS:${#pk_cols[@]}"
    echo "COMPOUND:$is_compound_pk"
}

# Generate a random INSERT for a table
generate_insert() {
    local table_name="$1"
    shift
    local col_types=("$@")
    
    local values=""
    for col_type in "${col_types[@]}"; do
        [[ -n "$values" ]] && values+=", "
        values+=$(random_value "$col_type")
    done
    
    echo "INSERT INTO $table_name VALUES ($values);"
}

# Generate a random UPDATE for a table
generate_update() {
    local table_name="$1"
    local pk_value="$2"
    shift 2
    local col_types=("$@")
    
    # Pick a random column to update (not the PK at index 0)
    local num_cols=${#col_types[@]}
    if [[ $num_cols -le 1 ]]; then
        # Only PK, can't update
        return
    fi
    
    local col_idx=$((RANDOM % (num_cols - 1) + 1))
    local col_type="${col_types[$col_idx]}"
    local new_value=$(random_value "$col_type")
    
    echo "UPDATE $table_name SET col$col_idx = $new_value WHERE id = $pk_value;"
}

# Generate a random DELETE for a table
generate_delete() {
    local table_name="$1"
    local pk_value="$2"
    
    echo "DELETE FROM $table_name WHERE id = $pk_value;"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execution helpers
# ═══════════════════════════════════════════════════════════════════════════════

run_zig() {
    local db="$1"
    local sql="$2"
    local out="$3"
    $SQLITE "$db" -cmd ".load $ZIG_EXT" "$sql" 2>"$TMPDIR/zig_err.txt" > "$out" || true
}

run_rust() {
    local db="$1"
    local sql="$2"
    local out="$3"
    $SQLITE "$db" -cmd ".load $RUST_EXT sqlite3_crsqlite_init" "$sql" 2>"$TMPDIR/rust_err.txt" > "$out" || true
}

# Compare two outputs and report divergence
compare_outputs() {
    local name="$1"
    local rust_out="$2"
    local zig_out="$3"
    local sql_log="$4"
    
    # Normalize outputs (sort if needed, remove trailing whitespace)
    sort "$rust_out" | sed 's/[[:space:]]*$//' > "$TMPDIR/rust_norm.txt"
    sort "$zig_out" | sed 's/[[:space:]]*$//' > "$TMPDIR/zig_norm.txt"
    
    if ! diff -q "$TMPDIR/rust_norm.txt" "$TMPDIR/zig_norm.txt" > /dev/null 2>&1; then
        return 1  # Divergence found
    fi
    return 0
}

# Log a divergence with full details
log_divergence() {
    local iteration="$1"
    local check_name="$2"
    local sql_log="$3"
    local rust_out="$4"
    local zig_out="$5"
    
    {
        echo "════════════════════════════════════════════════════════════════════"
        echo "DIVERGENCE #$((DIVERGENCES + 1)) found at iteration $iteration"
        echo "Check: $check_name"
        echo "════════════════════════════════════════════════════════════════════"
        echo ""
        echo "SQL sequence:"
        cat "$sql_log"
        echo ""
        echo "Rust/C output:"
        cat "$rust_out"
        echo ""
        echo "Zig output:"
        cat "$zig_out"
        echo ""
        echo "Diff:"
        diff "$rust_out" "$zig_out" || true
        echo ""
    } >> "$DIVERGENCE_LOG"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main fuzz loop
# ═══════════════════════════════════════════════════════════════════════════════

echo "Starting fuzz testing..."
echo ""

for ((iter=1; iter<=ITERATIONS; iter++)); do
    [[ "$VERBOSE" == "1" ]] && echo "Iteration $iter/$ITERATIONS"
    
    # Fresh databases for this iteration
    DB_ZIG="$TMPDIR/fuzz_zig_$iter.sqlite"
    DB_RUST="$TMPDIR/fuzz_rust_$iter.sqlite"
    SQL_LOG="$TMPDIR/sql_$iter.log"
    
    rm -f "$DB_ZIG" "$DB_RUST"
    > "$SQL_LOG"
    
    # Generate random schema
    TABLE_NAME="fuzz_table"
    SCHEMA_OUTPUT=$(generate_schema "$TABLE_NAME")
    SCHEMA_SQL=$(echo "$SCHEMA_OUTPUT" | head -1)
    COL_TYPES_STR=$(echo "$SCHEMA_OUTPUT" | grep "^TYPES:" | sed 's/^TYPES://')
    read -ra COL_TYPES <<< "$COL_TYPES_STR"
    NUM_PK_COLS=$(echo "$SCHEMA_OUTPUT" | grep "^PKCOLS:" | sed 's/^PKCOLS://')
    IS_COMPOUND=$(echo "$SCHEMA_OUTPUT" | grep "^COMPOUND:" | sed 's/^COMPOUND://')
    
    # Setup SQL (create table + enable CRR)
    SETUP_SQL="$SCHEMA_SQL
SELECT crsql_as_crr('$TABLE_NAME');"
    echo "$SETUP_SQL" >> "$SQL_LOG"
    
    run_zig "$DB_ZIG" "$SETUP_SQL" "$TMPDIR/zig_setup.txt"
    run_rust "$DB_RUST" "$SETUP_SQL" "$TMPDIR/rust_setup.txt"
    
    # Check for setup errors
    if [[ -s "$TMPDIR/zig_err.txt" ]] && grep -q "error" "$TMPDIR/zig_err.txt" 2>/dev/null; then
        [[ "$VERBOSE" == "1" ]] && echo "  SKIP: Zig setup error"
        continue
    fi
    if [[ -s "$TMPDIR/rust_err.txt" ]] && grep -q "error" "$TMPDIR/rust_err.txt" 2>/dev/null; then
        [[ "$VERBOSE" == "1" ]] && echo "  SKIP: Rust setup error"
        continue
    fi
    
    # Track inserted PKs for updates/deletes
    INSERTED_PKS=()
    NEXT_PK=1
    
    # Generate random operations (5-20 per iteration)
    NUM_OPS=$((RANDOM % 16 + 5))
    OPS_SQL=""
    
    # Mode 4 or 30% chance: wrap operations in a transaction
    USE_TX=0
    if [[ "$EDGE_MODE" == "4" ]] || [[ $((RANDOM % 3)) -eq 0 ]]; then
        USE_TX=1
        OPS_SQL+="BEGIN;"$'\n'
    fi
    
    for ((op=1; op<=NUM_OPS; op++)); do
        OP_TYPE=$((RANDOM % 10))
        
        if [[ $OP_TYPE -lt 5 ]]; then
            # 50% INSERT
            INSERT_SQL=$(generate_insert "$TABLE_NAME" "${COL_TYPES[@]}")
            
            if [[ "$IS_COMPOUND" == "1" ]]; then
                # For compound PK, generate multiple PK values
                pk_values=""
                for ((pk_i=0; pk_i<NUM_PK_COLS; pk_i++)); do
                    [[ -n "$pk_values" ]] && pk_values+=", "
                    if [[ "${COL_TYPES[$pk_i]}" == "TEXT" ]]; then
                        pk_values+="'pk${NEXT_PK}_${pk_i}'"
                    else
                        pk_values+="$((NEXT_PK * 10 + pk_i))"
                    fi
                done
                # Simpler approach: regenerate all values
                all_values="$pk_values"
                for ((col_i=NUM_PK_COLS; col_i<${#COL_TYPES[@]}; col_i++)); do
                    all_values+=", $(random_value "${COL_TYPES[$col_i]}")"
                done
                INSERT_SQL="INSERT INTO $TABLE_NAME VALUES ($all_values);"
            else
                # Simple PK: replace the first value (id) with our sequential PK
                INSERT_SQL=$(echo "$INSERT_SQL" | sed "s/VALUES ([^,]*/VALUES ($NEXT_PK/")
            fi
            
            OPS_SQL+="$INSERT_SQL"$'\n'
            INSERTED_PKS+=("$NEXT_PK")
            NEXT_PK=$((NEXT_PK + 1))
        elif [[ $OP_TYPE -lt 8 ]] && [[ ${#INSERTED_PKS[@]} -gt 0 ]]; then
            # 30% UPDATE (if we have rows)
            PK_IDX=$((RANDOM % ${#INSERTED_PKS[@]}))
            PK_VAL="${INSERTED_PKS[$PK_IDX]}"
            
            if [[ "$IS_COMPOUND" == "1" ]]; then
                # Build WHERE clause for compound PK
                where_clause=""
                for ((pk_i=0; pk_i<NUM_PK_COLS; pk_i++)); do
                    [[ -n "$where_clause" ]] && where_clause+=" AND "
                    if [[ "${COL_TYPES[$pk_i]}" == "TEXT" ]]; then
                        where_clause+="pk$((pk_i+1)) = 'pk${PK_VAL}_${pk_i}'"
                    else
                        where_clause+="pk$((pk_i+1)) = $((PK_VAL * 10 + pk_i))"
                    fi
                done
                # Pick a random non-PK column to update
                col_idx=$((RANDOM % (${#COL_TYPES[@]} - NUM_PK_COLS) + NUM_PK_COLS))
                col_num=$((col_idx - NUM_PK_COLS + 1))
                new_value=$(random_value "${COL_TYPES[$col_idx]}")
                UPDATE_SQL="UPDATE $TABLE_NAME SET col$col_num = $new_value WHERE $where_clause;"
            else
                UPDATE_SQL=$(generate_update "$TABLE_NAME" "$PK_VAL" "${COL_TYPES[@]}")
            fi
            [[ -n "$UPDATE_SQL" ]] && OPS_SQL+="$UPDATE_SQL"$'\n'
        elif [[ ${#INSERTED_PKS[@]} -gt 0 ]]; then
            # 20% DELETE (if we have rows)
            PK_IDX=$((RANDOM % ${#INSERTED_PKS[@]}))
            PK_VAL="${INSERTED_PKS[$PK_IDX]}"
            
            if [[ "$IS_COMPOUND" == "1" ]]; then
                # Build WHERE clause for compound PK
                where_clause=""
                for ((pk_i=0; pk_i<NUM_PK_COLS; pk_i++)); do
                    [[ -n "$where_clause" ]] && where_clause+=" AND "
                    if [[ "${COL_TYPES[$pk_i]}" == "TEXT" ]]; then
                        where_clause+="pk$((pk_i+1)) = 'pk${PK_VAL}_${pk_i}'"
                    else
                        where_clause+="pk$((pk_i+1)) = $((PK_VAL * 10 + pk_i))"
                    fi
                done
                DELETE_SQL="DELETE FROM $TABLE_NAME WHERE $where_clause;"
            else
                DELETE_SQL=$(generate_delete "$TABLE_NAME" "$PK_VAL")
            fi
            OPS_SQL+="$DELETE_SQL"$'\n'
            # Remove from tracking (still valid for future updates on tombstone)
        fi
    done
    
    # Close transaction if opened
    if [[ $USE_TX -eq 1 ]]; then
        OPS_SQL+="COMMIT;"$'\n'
    fi
    
    echo "$OPS_SQL" >> "$SQL_LOG"
    
    # Execute operations
    run_zig "$DB_ZIG" "$OPS_SQL" "$TMPDIR/zig_ops.txt"
    run_rust "$DB_RUST" "$OPS_SQL" "$TMPDIR/rust_ops.txt"
    
    # ═══════════════════════════════════════════════════════════════════════════
    # Parity checks
    # ═══════════════════════════════════════════════════════════════════════════
    
    ITER_DIVERGED=0
    
    # Check 1: Table contents
    CHECK_SQL="SELECT * FROM $TABLE_NAME ORDER BY id;"
    run_zig "$DB_ZIG" "$CHECK_SQL" "$TMPDIR/zig_table.txt"
    run_rust "$DB_RUST" "$CHECK_SQL" "$TMPDIR/rust_table.txt"
    
    if ! compare_outputs "table_contents" "$TMPDIR/rust_table.txt" "$TMPDIR/zig_table.txt" "$SQL_LOG"; then
        log_divergence "$iter" "table_contents" "$SQL_LOG" "$TMPDIR/rust_table.txt" "$TMPDIR/zig_table.txt"
        DIVERGENCES=$((DIVERGENCES + 1))
        ITER_DIVERGED=1
        echo "  DIVERGENCE: Table contents differ (iteration $iter)"
    fi
    
    # Check 2: db_version
    CHECK_SQL="SELECT crsql_db_version();"
    run_zig "$DB_ZIG" "$CHECK_SQL" "$TMPDIR/zig_dbver.txt"
    run_rust "$DB_RUST" "$CHECK_SQL" "$TMPDIR/rust_dbver.txt"
    
    if ! compare_outputs "db_version" "$TMPDIR/rust_dbver.txt" "$TMPDIR/zig_dbver.txt" "$SQL_LOG"; then
        log_divergence "$iter" "db_version" "$SQL_LOG" "$TMPDIR/rust_dbver.txt" "$TMPDIR/zig_dbver.txt"
        DIVERGENCES=$((DIVERGENCES + 1))
        ITER_DIVERGED=1
        echo "  DIVERGENCE: db_version differs (iteration $iter)"
    fi
    
    # Check 3: crsql_changes output (excluding site_id which differs by design)
    CHECK_SQL="SELECT [table], hex(pk), cid, quote(val), col_version, db_version, cl, seq FROM crsql_changes ORDER BY [table], pk, cid, db_version;"
    run_zig "$DB_ZIG" "$CHECK_SQL" "$TMPDIR/zig_changes.txt"
    run_rust "$DB_RUST" "$CHECK_SQL" "$TMPDIR/rust_changes.txt"
    
    if ! compare_outputs "crsql_changes" "$TMPDIR/rust_changes.txt" "$TMPDIR/zig_changes.txt" "$SQL_LOG"; then
        log_divergence "$iter" "crsql_changes" "$SQL_LOG" "$TMPDIR/rust_changes.txt" "$TMPDIR/zig_changes.txt"
        DIVERGENCES=$((DIVERGENCES + 1))
        ITER_DIVERGED=1
        echo "  DIVERGENCE: crsql_changes differs (iteration $iter)"
    fi
    
    # Check 4: Clock table contents (col_version values)
    CHECK_SQL="SELECT key, col_name, col_version, db_version FROM ${TABLE_NAME}__crsql_clock ORDER BY key, col_name;"
    run_zig "$DB_ZIG" "$CHECK_SQL" "$TMPDIR/zig_clock.txt"
    run_rust "$DB_RUST" "$CHECK_SQL" "$TMPDIR/rust_clock.txt"
    
    if ! compare_outputs "clock_table" "$TMPDIR/rust_clock.txt" "$TMPDIR/zig_clock.txt" "$SQL_LOG"; then
        log_divergence "$iter" "clock_table" "$SQL_LOG" "$TMPDIR/rust_clock.txt" "$TMPDIR/zig_clock.txt"
        DIVERGENCES=$((DIVERGENCES + 1))
        ITER_DIVERGED=1
        echo "  DIVERGENCE: Clock table differs (iteration $iter)"
    fi
    
    if [[ $ITER_DIVERGED -eq 0 ]]; then
        PASS=$((PASS + 1))
        [[ "$VERBOSE" == "1" ]] && echo "  PASS"
    else
        FAIL=$((FAIL + 1))
    fi
    
    # Progress indicator every 10 iterations
    if [[ $((iter % 10)) -eq 0 ]] && [[ "$VERBOSE" != "1" ]]; then
        echo "  Progress: $iter/$ITERATIONS iterations ($PASS passed, $DIVERGENCES divergences)"
    fi
    
    # Clean up iteration files to save disk space
    rm -f "$DB_ZIG" "$DB_RUST"
done

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Fuzz Parity Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Iterations:   $ITERATIONS"
echo "Seed:         $SEED"
echo "Passed:       $PASS"
echo "Failed:       $FAIL"
echo "Divergences:  $DIVERGENCES"
echo ""

if [[ $DIVERGENCES -gt 0 ]]; then
    CLEANUP_ON_EXIT=0  # Preserve temp dir for investigation
    echo "════════════════════════════════════════════════════════════════════════"
    echo "HYPOTHESIS INVALIDATED: Found $DIVERGENCES divergence(s)!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Full divergence log: $DIVERGENCE_LOG"
    echo ""
    echo "First divergence:"
    head -100 "$DIVERGENCE_LOG"
    echo ""
    echo "The Zig implementation does NOT have full behavioral parity with Rust/C."
    echo "Investigate the divergence(s) above."
    # Copy divergence log to a persistent location
    PERSISTENT_LOG="$REPO_ROOT/.tmp/fuzz-divergences-$(date +%Y%m%d-%H%M%S).log"
    cp "$DIVERGENCE_LOG" "$PERSISTENT_LOG"
    echo "Divergence log saved to: $PERSISTENT_LOG"
    echo "Temp dir preserved at: $TMPDIR"
    exit 1
else
    echo "════════════════════════════════════════════════════════════════════════"
    echo "NO DIVERGENCES FOUND after $ITERATIONS iterations"
    echo "════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "The 'full parity' hypothesis was NOT invalidated by this run."
    echo ""
    echo "To increase confidence, run with more iterations:"
    echo "  FUZZ_ITERATIONS=1000 $0"
    echo ""
    echo "Or with a different seed:"
    echo "  FUZZ_SEED=12345 $0"
    exit 0
fi
