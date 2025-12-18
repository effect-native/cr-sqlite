#!/usr/bin/env bash
# API Surface Parity Test
# Compares SQL functions and modules between Rust/C extension (oracle) and Zig extension
#
# The Rust/C extension is the golden master - any function or module present there
# but missing from Zig is a gap that needs to be addressed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Extension paths
RUST_EXT="$ROOT_DIR/lib/crsqlite.dylib"
ZIG_EXT="$ROOT_DIR/lib/crsqlite-zig-darwin-aarch64.dylib"

# Allow override via environment
RUST_EXT="${RUST_EXT_PATH:-$RUST_EXT}"
ZIG_EXT="${ZIG_EXT_PATH:-$ZIG_EXT}"

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║           API Surface Parity Test (Oracle: Rust/C)                    ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Rust/C extension: $RUST_EXT"
echo "Zig extension:    $ZIG_EXT"
echo ""

# Verify extensions exist
if [[ ! -f "$RUST_EXT" ]]; then
    echo "FAIL: Rust/C extension not found at $RUST_EXT"
    echo "      Build with: make -C core"
    exit 1
fi

if [[ ! -f "$ZIG_EXT" ]]; then
    echo "FAIL: Zig extension not found at $ZIG_EXT"
    echo "      Build with: make -C zig"
    exit 1
fi

# Create temp files
RUST_FUNCS=$(mktemp)
ZIG_FUNCS=$(mktemp)
RUST_MODS=$(mktemp)
ZIG_MODS=$(mktemp)
trap "rm -f $RUST_FUNCS $ZIG_FUNCS $RUST_MODS $ZIG_MODS" EXIT

# ═══════════════════════════════════════════════════════════════════════════
# Extract Function Lists
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Extracting function lists..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Extract Rust/C functions (ignore the sqlite3_close error which is a known issue)
nix run nixpkgs#sqlite -- :memory: \
    -cmd ".load $RUST_EXT" \
    "SELECT DISTINCT name FROM pragma_function_list WHERE name LIKE 'crsql%' ORDER BY name;" 2>&1 \
    | grep -v "^Error:" | sort -u > "$RUST_FUNCS"

# Extract Zig functions
nix run nixpkgs#sqlite -- :memory: \
    -cmd ".load $ZIG_EXT" \
    "SELECT DISTINCT name FROM pragma_function_list WHERE name LIKE 'crsql%' ORDER BY name;" 2>&1 \
    | grep -v "^Error:" | grep -v "^error" | sort -u > "$ZIG_FUNCS"

echo "Rust/C functions ($(wc -l < "$RUST_FUNCS" | tr -d ' ')):"
cat "$RUST_FUNCS" | sed 's/^/  /'
echo ""

echo "Zig functions ($(wc -l < "$ZIG_FUNCS" | tr -d ' ')):"
cat "$ZIG_FUNCS" | sed 's/^/  /'
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Extract Module Lists
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Extracting module lists..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Extract Rust/C modules
nix run nixpkgs#sqlite -- :memory: \
    -cmd ".load $RUST_EXT" \
    "SELECT name FROM pragma_module_list WHERE name LIKE 'crsql%' OR name = 'clset' ORDER BY name;" 2>&1 \
    | grep -v "^Error:" | sort -u > "$RUST_MODS"

# Extract Zig modules
nix run nixpkgs#sqlite -- :memory: \
    -cmd ".load $ZIG_EXT" \
    "SELECT name FROM pragma_module_list WHERE name LIKE 'crsql%' OR name = 'clset' ORDER BY name;" 2>&1 \
    | grep -v "^Error:" | grep -v "^error" | sort -u > "$ZIG_MODS"

echo "Rust/C modules ($(wc -l < "$RUST_MODS" | tr -d ' ')):"
cat "$RUST_MODS" | sed 's/^/  /'
echo ""

echo "Zig modules ($(wc -l < "$ZIG_MODS" | tr -d ' ')):"
cat "$ZIG_MODS" | sed 's/^/  /'
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Compare and Report
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Comparing API surfaces..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Functions missing from Zig
MISSING_FUNCS=$(comm -23 "$RUST_FUNCS" "$ZIG_FUNCS")
# Functions extra in Zig (not in Rust/C)
EXTRA_FUNCS=$(comm -13 "$RUST_FUNCS" "$ZIG_FUNCS")

# Modules missing from Zig
MISSING_MODS=$(comm -23 "$RUST_MODS" "$ZIG_MODS")
# Modules extra in Zig
EXTRA_MODS=$(comm -13 "$RUST_MODS" "$ZIG_MODS")

TOTAL_FAIL=0
TOTAL_PASS=0

# Report missing functions
if [[ -n "$MISSING_FUNCS" ]]; then
    MISSING_COUNT=$(echo "$MISSING_FUNCS" | wc -l | tr -d ' ')
    echo "FAIL: $MISSING_COUNT functions in Rust/C but missing from Zig:"
    echo "$MISSING_FUNCS" | sed 's/^/  - /'
    TOTAL_FAIL=$((TOTAL_FAIL + MISSING_COUNT))
    echo ""
else
    echo "PASS: All Rust/C functions are present in Zig"
    TOTAL_PASS=$((TOTAL_PASS + 1))
fi

# Report extra functions (informational, not a failure)
if [[ -n "$EXTRA_FUNCS" ]]; then
    EXTRA_COUNT=$(echo "$EXTRA_FUNCS" | wc -l | tr -d ' ')
    echo "INFO: $EXTRA_COUNT functions in Zig but not in Rust/C (Zig-specific):"
    echo "$EXTRA_FUNCS" | sed 's/^/  + /'
    echo ""
fi

# Report missing modules
if [[ -n "$MISSING_MODS" ]]; then
    MISSING_MOD_COUNT=$(echo "$MISSING_MODS" | wc -l | tr -d ' ')
    echo "FAIL: $MISSING_MOD_COUNT modules in Rust/C but missing from Zig:"
    echo "$MISSING_MODS" | sed 's/^/  - /'
    TOTAL_FAIL=$((TOTAL_FAIL + MISSING_MOD_COUNT))
    echo ""
else
    echo "PASS: All Rust/C modules are present in Zig"
    TOTAL_PASS=$((TOTAL_PASS + 1))
fi

# Report extra modules (informational)
if [[ -n "$EXTRA_MODS" ]]; then
    EXTRA_MOD_COUNT=$(echo "$EXTRA_MODS" | wc -l | tr -d ' ')
    echo "INFO: $EXTRA_MOD_COUNT modules in Zig but not in Rust/C (Zig-specific):"
    echo "$EXTRA_MODS" | sed 's/^/  + /'
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════
# Intentional Exclusions (documented)
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Intentional Exclusions (documented rationale):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  crsql_after_delete, crsql_after_insert, crsql_after_update:"
echo "    Internal trigger functions - not part of public API."
echo "    These are registered for use by auto-generated triggers only."
echo ""
echo "  crsql_sha:"
echo "    Debug/utility function - not essential for CRDT operations."
echo ""
echo "  crsql_siteid (alias):"
echo "    Legacy alias - crsql_site_id is the canonical function."
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                         API SURFACE SUMMARY                          ║"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  Rust/C Functions: %-50d ║\n" "$(wc -l < "$RUST_FUNCS" | tr -d ' ')"
printf "║  Zig Functions:    %-50d ║\n" "$(wc -l < "$ZIG_FUNCS" | tr -d ' ')"
printf "║  Rust/C Modules:   %-50d ║\n" "$(wc -l < "$RUST_MODS" | tr -d ' ')"
printf "║  Zig Modules:      %-50d ║\n" "$(wc -l < "$ZIG_MODS" | tr -d ' ')"
echo "╠═══════════════════════════════════════════════════════════════════════╣"
printf "║  Missing from Zig: %-50d ║\n" "$TOTAL_FAIL"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
    echo "✓ API surface parity: PASS"
    exit 0
else
    echo "✗ API surface parity: FAIL ($TOTAL_FAIL gaps found)"
    exit 1
fi
