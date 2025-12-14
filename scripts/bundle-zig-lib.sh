#!/usr/bin/env bash
# Bundle Zig-built CR-SQLite artifacts into lib/ with proper naming
#
# This script copies Zig-built artifacts to the lib/ directory with the
# naming convention: crsqlite-zig-<platform>-<arch>.<ext>
#
# The "zig" prefix distinguishes these from the C/Rust artifacts.
#
# Usage:
#   ./scripts/bundle-zig-lib.sh           # Bundle for current platform
#   ./scripts/bundle-zig-lib.sh all       # Bundle all available platforms
#   ./scripts/bundle-zig-lib.sh darwin    # Bundle macOS artifacts
#   ./scripts/bundle-zig-lib.sh linux     # Bundle Linux artifacts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ZIG_DIR="$PROJECT_ROOT/zig"
LIB_DIR="$PROJECT_ROOT/lib"

# ANSI colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
BOLD='\033[1m'

log() { echo -e "${CYAN}${BOLD}[bundle-zig]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[bundle-zig]${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}[bundle-zig]${RESET} $*"; }
error() { echo -e "${RED}${BOLD}[bundle-zig]${RESET} $*"; }

# Ensure lib/ exists
mkdir -p "$LIB_DIR"

# Copy artifact with logging
copy_artifact() {
  local src="$1"
  local dest="$2"
  
  if [[ -f "$src" ]]; then
    cp -v "$src" "$dest"
    success "Copied: $(basename "$dest")"
    return 0
  else
    warn "Not found: $src"
    return 1
  fi
}

# Bundle macOS artifacts
bundle_darwin() {
  log "Bundling macOS (darwin) Zig artifacts..."
  local count=0
  
  # Universal binary (preferred)
  if copy_artifact \
    "$ZIG_DIR/zig-out-universal/lib/libcrsqlite.dylib" \
    "$LIB_DIR/crsqlite-zig-darwin-universal.dylib"; then
    ((count++))
  fi
  
  # ARM64 (Apple Silicon)
  if copy_artifact \
    "$ZIG_DIR/zig-out-arm64/lib/libcrsqlite.dylib" \
    "$LIB_DIR/crsqlite-zig-darwin-aarch64.dylib"; then
    ((count++))
  fi
  
  # x86_64 (Intel)
  if copy_artifact \
    "$ZIG_DIR/zig-out-x64/lib/libcrsqlite.dylib" \
    "$LIB_DIR/crsqlite-zig-darwin-x86_64.dylib"; then
    ((count++))
  fi
  
  # Native build fallback
  if [[ $count -eq 0 ]] && [[ -f "$ZIG_DIR/zig-out/lib/libcrsqlite.dylib" ]]; then
    # Detect current arch for naming
    local arch
    arch="$(uname -m)"
    case "$arch" in
      arm64|aarch64) arch="aarch64" ;;
      x86_64|amd64) arch="x86_64" ;;
    esac
    copy_artifact \
      "$ZIG_DIR/zig-out/lib/libcrsqlite.dylib" \
      "$LIB_DIR/crsqlite-zig-darwin-${arch}.dylib"
    ((count++))
  fi
  
  if [[ $count -eq 0 ]]; then
    warn "No macOS Zig artifacts found. Run 'npm run build:zig darwin' first."
    return 1
  fi
  
  success "Bundled $count macOS artifact(s)"
}

# Bundle Linux artifacts
bundle_linux() {
  log "Bundling Linux Zig artifacts..."
  local count=0
  
  # x86_64
  if copy_artifact \
    "$ZIG_DIR/zig-out-linux-x64/lib/libcrsqlite.so" \
    "$LIB_DIR/crsqlite-zig-linux-x86_64.so"; then
    ((count++))
  fi
  
  # ARM64
  if copy_artifact \
    "$ZIG_DIR/zig-out-linux-arm64/lib/libcrsqlite.so" \
    "$LIB_DIR/crsqlite-zig-linux-aarch64.so"; then
    ((count++))
  fi
  
  # Native build fallback (if on Linux)
  if [[ $count -eq 0 ]] && [[ "$(uname -s)" == "Linux" ]] && [[ -f "$ZIG_DIR/zig-out/lib/libcrsqlite.so" ]]; then
    local arch
    arch="$(uname -m)"
    case "$arch" in
      arm64|aarch64) arch="aarch64" ;;
      x86_64|amd64) arch="x86_64" ;;
    esac
    copy_artifact \
      "$ZIG_DIR/zig-out/lib/libcrsqlite.so" \
      "$LIB_DIR/crsqlite-zig-linux-${arch}.so"
    ((count++))
  fi
  
  if [[ $count -eq 0 ]]; then
    warn "No Linux Zig artifacts found. Run 'npm run build:zig linux' first."
    return 1
  fi
  
  success "Bundled $count Linux artifact(s)"
}

# Bundle for current platform
bundle_native() {
  local os
  os="$(uname -s)"
  
  case "$os" in
    Darwin)
      bundle_darwin
      ;;
    Linux)
      bundle_linux
      ;;
    *)
      error "Unsupported OS: $os"
      exit 1
      ;;
  esac
}

# Bundle all available platforms
bundle_all() {
  log "Bundling all available Zig artifacts..."
  
  local darwin_ok=0
  local linux_ok=0
  
  bundle_darwin && darwin_ok=1
  bundle_linux && linux_ok=1
  
  echo ""
  log "Summary:"
  if [[ $darwin_ok -eq 1 ]]; then
    echo -e "  ${GREEN}macOS:  OK${RESET}"
  else
    echo -e "  ${YELLOW}macOS:  MISSING${RESET}"
  fi
  if [[ $linux_ok -eq 1 ]]; then
    echo -e "  ${GREEN}Linux:  OK${RESET}"
  else
    echo -e "  ${YELLOW}Linux:  MISSING${RESET}"
  fi
  
  echo ""
  log "Zig artifacts in lib/:"
  ls -la "$LIB_DIR"/crsqlite-zig-* 2>/dev/null || echo "  (none)"
}

# Main
case "${1:-native}" in
  native|current)
    bundle_native
    ;;
  darwin|macos)
    bundle_darwin
    ;;
  linux)
    bundle_linux
    ;;
  all)
    bundle_all
    ;;
  *)
    error "Unknown target: $1"
    echo "Usage: $0 [native|darwin|linux|all]"
    exit 1
    ;;
esac
