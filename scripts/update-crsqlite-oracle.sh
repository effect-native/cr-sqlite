#!/usr/bin/env bash
# Update cr-sqlite oracle binaries from official vlcn-io releases
# Uses the same source as github:subtleGradient/sqlite-cr
#
# Usage: ./scripts/update-crsqlite-oracle.sh [version]
# Default version: 0.16.3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

VERSION="${1:-0.16.3}"
BASE_URL="https://github.com/vlcn-io/cr-sqlite/releases/download/v${VERSION}"

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║       Update CR-SQLite Oracle Binaries (v${VERSION})                     ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

TMPDIR="$PROJECT_ROOT/.tmp/crsqlite-update-$$"
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

download_and_install() {
    local platform="$1"
    local ext="$2"
    local zip_name="crsqlite-${platform}.zip"
    local output_name="crsqlite-${platform}.${ext}"
    local url="${BASE_URL}/${zip_name}"
    
    echo "Downloading $platform..."
    if ! curl -fsSL "$url" -o "$TMPDIR/$zip_name"; then
        echo "  SKIP: Failed to download $url"
        return 1
    fi
    
    echo "  Extracting..."
    unzip -q -o "$TMPDIR/$zip_name" -d "$TMPDIR/$platform"
    
    # Find the library file (dylib or so)
    local lib_file
    lib_file=$(find "$TMPDIR/$platform" -name "crsqlite.*" -type f | head -1)
    
    if [[ -z "$lib_file" ]]; then
        echo "  ERROR: No library file found in archive"
        return 1
    fi
    
    # Install with correct naming
    cp "$lib_file" "$LIB_DIR/$output_name"
    chmod +x "$LIB_DIR/$output_name"
    echo "  Installed: $output_name ($(stat -f%z "$LIB_DIR/$output_name" 2>/dev/null || stat -c%s "$LIB_DIR/$output_name") bytes)"
}

# Download all platforms
download_and_install "darwin-aarch64" "dylib" || true
download_and_install "darwin-x86_64" "dylib" || true
download_and_install "linux-aarch64" "so" || true
download_and_install "linux-x86_64" "so" || true

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                           Summary                                     ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Updated oracle binaries in $LIB_DIR:"
ls -la "$LIB_DIR"/crsqlite-darwin-*.dylib "$LIB_DIR"/crsqlite-linux-*.so 2>/dev/null || echo "(none found)"
echo ""
echo "Version: $VERSION"
echo "Source: $BASE_URL"
echo ""
echo "Test with:"
echo "  nix run nixpkgs#sqlite -- :memory: -cmd '.load lib/crsqlite-darwin-aarch64.dylib sqlite3_crsqlite_init' 'SELECT crsql_db_version();'"
