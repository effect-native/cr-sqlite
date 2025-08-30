#!/usr/bin/env bash
set -euo pipefail

# Build Linux .so libraries inside Docker and write them to ./lib on the host.
# Usage: scripts/build-linux-docker.sh [amd64|arm64|both]

ARCH=${1:-both}
FETCH_TIMEOUT=${FETCH_TIMEOUT:-10m}
BUILD_TIMEOUT=${BUILD_TIMEOUT:-60m}
HEARTBEAT_SECS=${HEARTBEAT_SECS:-60}

run_build() {
  local docker_arch="$1"  # amd64 or arm64
  local arch_name
  case "$docker_arch" in
    amd64) arch_name='x86_64' ;;
    arm64) arch_name='aarch64' ;;
    *) echo "Unknown docker arch: $docker_arch" >&2; exit 1 ;;
  esac
  echo "🐳 Building for linux/${docker_arch} in Docker (rustup + make)..."

  docker run --rm \
    --platform "linux/${docker_arch}" \
    -e ARCH_NAME="${arch_name}" \
    -e FETCH_TIMEOUT="${FETCH_TIMEOUT}" \
    -e BUILD_TIMEOUT="${BUILD_TIMEOUT}" \
    -e HEARTBEAT_SECS="${HEARTBEAT_SECS}" \
    -v "$PWD":/workspace \
    -w /workspace \
    debian:bookworm-slim \
    bash -lc '
      set -euo pipefail
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates build-essential clang llvm llvm-dev libclang-dev pkg-config git coreutils
      update-ca-certificates
      echo ":: installing rustup toolchain"
      curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly-2024-03-15
      . "$HOME/.cargo/env"
      export LIBCLANG_PATH=$(llvm-config --libdir)
      export CC=clang
      export CARGO_TERM_PROGRESS_WHEN=always
      export CARGO_TERM_PROGRESS_WIDTH=80
      export CARGO_HTTP_TIMEOUT=120
      export CARGO_NET_RETRY=2
      export CARGO_TARGET_DIR="/tmp/cargo-target-$ARCH_NAME"
      rm -rf "$CARGO_TARGET_DIR"
      phase=setup
      echo ":: cargo fetch (network)"
      phase=cargo_fetch
      ( cd core/rs/bundle_static && timeout "$FETCH_TIMEOUT" stdbuf -oL -eL cargo fetch )
      echo ":: make -C core loadable (build)"
      phase=make_loadable
      timeout "$BUILD_TIMEOUT" stdbuf -oL -eL make -C core loadable V=1
      ls -la core/dist || true
      test -f core/dist/crsqlite.so
      mkdir -p lib
      cp -v core/dist/crsqlite.so "lib/crsqlite-linux-$ARCH_NAME.so"
      cp -v core/dist/crsqlite.so lib/crsqlite.so
      echo ":: done"
    '
}

case "$ARCH" in
  amd64)
    run_build amd64
    ;;
  arm64)
    run_build arm64
    ;;
  both)
    run_build amd64
    run_build arm64
    ;;
  *)
    echo "Unknown arch: $ARCH (expected amd64|arm64|both)" >&2
    exit 1
    ;;
esac

echo "✅ Linux builds complete. Files in ./lib:"
ls -la lib || true

