# CR-SQLite WASM Build Makefile
#
# This Makefile provides convenience targets for building SQLite WASM
# with the Zig CR-SQLite extension.
#
# Usage:
#   make              - Build release WASM (default)
#   make debug        - Build debug WASM with assertions
#   make clean        - Remove build artifacts
#   make zig-wasm     - Build the Zig WASM library first
#   make all          - Build Zig lib + WASM bundle
#   make shell        - Enter nix shell with Emscripten
#
# Requirements:
#   - Emscripten (emcc) in PATH
#   - Zig compiler for building libcrsqlite.a

SCRIPT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PROJECT_ROOT := $(abspath $(SCRIPT_DIR)/../..)
ZIG_DIR := $(PROJECT_ROOT)/zig
DIST_DIR := $(SCRIPT_DIR)/dist
BUILD_DIR := $(SCRIPT_DIR)/build

# Zig outputs
ZIG_WASM_LIB := $(ZIG_DIR)/zig-out/lib/libcrsqlite.a

# Final outputs
WASM_JS := $(DIST_DIR)/sql-wasm.js
WASM_FILE := $(DIST_DIR)/sql-wasm.wasm

.PHONY: all release debug clean zig-wasm shell test help

# Default target: build release WASM
all: zig-wasm release

release: $(WASM_JS)

$(WASM_JS): $(ZIG_WASM_LIB)
	@echo "Building release WASM bundle..."
	./build-sqlite-wasm.sh

debug: $(ZIG_WASM_LIB)
	@echo "Building debug WASM bundle..."
	./build-sqlite-wasm.sh --debug

# Build the Zig WASM library
zig-wasm: $(ZIG_WASM_LIB)

$(ZIG_WASM_LIB):
	@echo "Building Zig CR-SQLite WASM library..."
	cd $(ZIG_DIR) && zig build wasm

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
	@echo "Build artifacts cleaned"

# Enter nix shell with Emscripten
shell:
	@echo "Entering nix shell with Emscripten..."
	@cd $(PROJECT_ROOT) && nix develop .#wasm

# Run browser tests (requires built WASM)
test: $(WASM_JS)
	@echo "Running browser tests..."
	cd $(ZIG_DIR)/browser-test && npm test

help:
	@echo "CR-SQLite WASM Build"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build Zig lib + WASM bundle (default)"
	@echo "  release  - Build release WASM bundle"
	@echo "  debug    - Build debug WASM bundle with assertions"
	@echo "  zig-wasm - Build the Zig WASM library"
	@echo "  clean    - Remove build artifacts"
	@echo "  shell    - Enter nix shell with Emscripten"
	@echo "  test     - Run browser tests"
	@echo ""
	@echo "Example workflow:"
	@echo "  make shell         # Get emcc in PATH"
	@echo "  make all           # Build everything"
	@echo ""
	@echo "Or use nix directly:"
	@echo "  nix develop .#wasm"
	@echo "  cd zig/wasm-build && make"
