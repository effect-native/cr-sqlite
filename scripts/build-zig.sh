#!/usr/bin/env bash
# Build Zig CR-SQLite extension for various platforms
#
# Usage:
#   ./scripts/build-zig.sh           # Build for current platform
#   ./scripts/build-zig.sh all       # Build for all supported platforms
#   ./scripts/build-zig.sh darwin    # Build for macOS (universal binary)
#   ./scripts/build-zig.sh linux     # Build for Linux (x64 and arm64)
#   ./scripts/build-zig.sh release   # Build all and copy to lib/ with release naming

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ZIG_DIR="$PROJECT_ROOT/zig"

# ANSI colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
BOLD='\033[1m'

log() { echo -e "${CYAN}${BOLD}[zig-build]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[zig-build]${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}[zig-build]${RESET} $*"; }
error() { echo -e "${RED}${BOLD}[zig-build]${RESET} $*"; }

# Detect current platform
detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  
  case "$os" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) error "Unsupported OS: $os"; exit 1 ;;
  esac
  
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    *) error "Unsupported architecture: $arch"; exit 1 ;;
  esac
  
  echo "${os}-${arch}"
}

# Build for a specific target
build_target() {
  local zig_target="$1"
  local output_dir="$2"
  
  log "Building for $zig_target -> $output_dir"
  
  cd "$ZIG_DIR"
  
  # Use nix to run zig for reproducibility
  if command -v nix &>/dev/null; then
    nix run nixpkgs#zig -- build -Dtarget="$zig_target" --prefix "$output_dir" -Doptimize=ReleaseFast
  else
    zig build -Dtarget="$zig_target" --prefix "$output_dir" -Doptimize=ReleaseFast
  fi
  
  success "Built $zig_target"
}

# Build for current platform
build_native() {
  log "Building for native platform..."
  cd "$ZIG_DIR"
  
  if command -v nix &>/dev/null; then
    nix run nixpkgs#zig -- build -Doptimize=ReleaseFast
  else
    zig build -Doptimize=ReleaseFast
  fi
  
  success "Built native extension at $ZIG_DIR/zig-out/lib/"
}

# Build macOS universal binary (arm64 + x64)
build_darwin_universal() {
  log "Building macOS universal binary..."
  
  # Build both architectures
  build_target "aarch64-macos" "$ZIG_DIR/zig-out-arm64"
  build_target "x86_64-macos" "$ZIG_DIR/zig-out-x64"
  
  # Create universal binary with lipo
  mkdir -p "$ZIG_DIR/zig-out-universal/lib"
  lipo -create \
    "$ZIG_DIR/zig-out-arm64/lib/libcrsqlite.dylib" \
    "$ZIG_DIR/zig-out-x64/lib/libcrsqlite.dylib" \
    -output "$ZIG_DIR/zig-out-universal/lib/libcrsqlite.dylib"
  
  success "Created universal binary at $ZIG_DIR/zig-out-universal/lib/libcrsqlite.dylib"
  lipo -info "$ZIG_DIR/zig-out-universal/lib/libcrsqlite.dylib"
}

# Build Linux targets
build_linux() {
  log "Building Linux targets..."
  build_target "x86_64-linux-gnu" "$ZIG_DIR/zig-out-linux-x64"
  build_target "aarch64-linux-gnu" "$ZIG_DIR/zig-out-linux-arm64"
  success "Built Linux extensions"
}

# Build all platforms
build_all() {
  log "Building all platforms..."
  
  # macOS universal (includes both arm64 and x64)
  build_darwin_universal
  
  # Linux targets
  build_linux
  
  success "All platforms built!"
  echo ""
  log "Artifacts:"
  echo "  macOS universal:  $ZIG_DIR/zig-out-universal/lib/libcrsqlite.dylib"
  echo "  macOS arm64:      $ZIG_DIR/zig-out-arm64/lib/libcrsqlite.dylib"
  echo "  macOS x64:        $ZIG_DIR/zig-out-x64/lib/libcrsqlite.dylib"
  echo "  Linux x64:        $ZIG_DIR/zig-out-linux-x64/lib/libcrsqlite.so"
  echo "  Linux arm64:      $ZIG_DIR/zig-out-linux-arm64/lib/libcrsqlite.so"
}

# Build release artifacts with GitHub Release naming convention
# Copies artifacts to lib/ at project root with release naming
build_release() {
  log "Building release artifacts..."
  
  # Build all platforms first
  build_all
  
  # Create lib directory at project root
  mkdir -p "$PROJECT_ROOT/lib"
  
  log "Copying artifacts with release naming to $PROJECT_ROOT/lib/"
  
  # macOS artifacts (following publish.yaml naming)
  cp "$ZIG_DIR/zig-out-arm64/lib/libcrsqlite.dylib" "$PROJECT_ROOT/lib/crsqlite-zig-darwin-aarch64.dylib"
  cp "$ZIG_DIR/zig-out-x64/lib/libcrsqlite.dylib" "$PROJECT_ROOT/lib/crsqlite-zig-darwin-x86_64.dylib"
  cp "$ZIG_DIR/zig-out-universal/lib/libcrsqlite.dylib" "$PROJECT_ROOT/lib/crsqlite-zig-darwin-universal.dylib"
  
  # Linux artifacts
  cp "$ZIG_DIR/zig-out-linux-x64/lib/libcrsqlite.so" "$PROJECT_ROOT/lib/crsqlite-zig-linux-x86_64.so"
  cp "$ZIG_DIR/zig-out-linux-arm64/lib/libcrsqlite.so" "$PROJECT_ROOT/lib/crsqlite-zig-linux-aarch64.so"
  
  success "Release artifacts ready!"
  echo ""
  log "Release artifacts in $PROJECT_ROOT/lib/:"
  ls -lh "$PROJECT_ROOT/lib/"*.dylib "$PROJECT_ROOT/lib/"*.so 2>/dev/null | while read line; do
    echo "  $line"
  done
  echo ""
  log "GitHub Release naming convention:"
  echo "  crsqlite-zig-darwin-aarch64.dylib  (Apple Silicon Mac)"
  echo "  crsqlite-zig-darwin-x86_64.dylib   (Intel Mac)"
  echo "  crsqlite-zig-darwin-universal.dylib (Universal macOS)"
  echo "  crsqlite-zig-linux-x86_64.so       (Intel/AMD Linux)"
  echo "  crsqlite-zig-linux-aarch64.so      (ARM64 Linux)"
}

# Main
case "${1:-native}" in
  native|current)
    build_native
    ;;
  darwin|macos)
    build_darwin_universal
    ;;
  linux)
    build_linux
    ;;
  all)
    build_all
    ;;
  release)
    build_release
    ;;
  *)
    error "Unknown target: $1"
    echo "Usage: $0 [native|darwin|linux|all|release]"
    exit 1
    ;;
esac
