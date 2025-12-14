# zig/Makefile - Unified test runner for Zig CR-SQLite
#
# Usage:
#   make test         - Run all tests concurrently
#   make test-unit    - Run Zig unit tests
#   make test-parity  - Run shell parity tests
#   make test-browser - Run Playwright browser tests
#   make build        - Build the extension
#   make clean        - Clean build artifacts
#   make help         - Show this help

.PHONY: all test test-unit test-parity test-browser build clean help \
        _test-unit _test-parity _test-browser

# ANSI colors for output
CYAN := \033[36m
GREEN := \033[32m
RED := \033[31m
YELLOW := \033[33m
RESET := \033[0m
BOLD := \033[1m

# Default: run all tests
all: test

# Build the Zig extension
build:
	@echo "$(CYAN)$(BOLD)Building Zig extension...$(RESET)"
	@nix run nixpkgs#zig -- build

# Zig unit tests
test-unit: build
	@echo ""
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)$(BOLD)  Zig Unit Tests$(RESET)"
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@nix run nixpkgs#zig -- build test

# Shell parity tests (includes filter, rowid, merge, alter, e2e)
test-parity:
	@echo ""
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)$(BOLD)  Shell Parity Tests$(RESET)"
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@cd harness && bash test-parity.sh

# Browser tests (Playwright + sql.js)
test-browser:
	@echo ""
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)$(BOLD)  Browser Tests (Playwright + sql.js)$(RESET)"
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@if [ ! -d "browser-test/node_modules" ]; then \
		echo "$(YELLOW)Installing browser test dependencies...$(RESET)"; \
		cd browser-test && npm install && npx playwright install chromium; \
	fi
	@cd browser-test && npm test

# Internal targets for parallel execution (no headers, used by test target)
_test-unit:
	@nix run nixpkgs#zig -- build 2>&1
	@nix run nixpkgs#zig -- build test 2>&1

_test-parity:
	@cd harness && bash test-parity.sh 2>&1

_test-browser:
	@if [ ! -d "browser-test/node_modules" ]; then \
		cd browser-test && npm install --silent && npx playwright install chromium; \
	fi
	@cd browser-test && npm test 2>&1

# Run all tests concurrently
# Uses background jobs with wait to run in parallel and collect exit codes
test:
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)$(BOLD)  Zig CR-SQLite Test Suite - Running All Tests$(RESET)"
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "Starting tests concurrently..."
	@echo ""
	@mkdir -p ../.tmp
	@# Run all three test suites in parallel, capturing output and exit codes
	@( \
		( \
			echo "$(CYAN)[unit]$(RESET) Starting Zig unit tests..." && \
			nix run nixpkgs#zig -- build 2>&1 && \
			nix run nixpkgs#zig -- build test 2>&1 && \
			echo "$(GREEN)[unit]$(RESET) Zig unit tests PASSED" \
		) > ../.tmp/test-unit.log 2>&1; echo $$? > ../.tmp/test-unit.exit & \
		( \
			echo "$(CYAN)[parity]$(RESET) Starting shell parity tests..." && \
			cd harness && bash test-parity.sh 2>&1 && \
			echo "$(GREEN)[parity]$(RESET) Shell parity tests PASSED" \
		) > ../.tmp/test-parity.log 2>&1; echo $$? > ../.tmp/test-parity.exit & \
		( \
			echo "$(CYAN)[browser]$(RESET) Starting browser tests..." && \
			if [ ! -d "browser-test/node_modules" ]; then \
				echo "Installing browser test dependencies..."; \
				cd browser-test && npm install --silent && npx playwright install chromium; \
			else \
				cd browser-test; \
			fi && \
			npm test 2>&1 && \
			echo "$(GREEN)[browser]$(RESET) Browser tests PASSED" \
		) > ../.tmp/test-browser.log 2>&1; echo $$? > ../.tmp/test-browser.exit & \
		wait \
	)
	@echo ""
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)$(BOLD)  Test Results$(RESET)"
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(BOLD)--- Unit Tests ---$(RESET)"
	@cat ../.tmp/test-unit.log 2>/dev/null || echo "No output"
	@echo ""
	@echo "$(BOLD)--- Parity Tests ---$(RESET)"
	@cat ../.tmp/test-parity.log 2>/dev/null || echo "No output"
	@echo ""
	@echo "$(BOLD)--- Browser Tests ---$(RESET)"
	@cat ../.tmp/test-browser.log 2>/dev/null || echo "No output"
	@echo ""
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)$(BOLD)  Summary$(RESET)"
	@echo "$(CYAN)$(BOLD)════════════════════════════════════════════════════════════════$(RESET)"
	@UNIT_EXIT=$$(cat ../.tmp/test-unit.exit 2>/dev/null || echo 1); \
	PARITY_EXIT=$$(cat ../.tmp/test-parity.exit 2>/dev/null || echo 1); \
	BROWSER_EXIT=$$(cat ../.tmp/test-browser.exit 2>/dev/null || echo 1); \
	if [ "$$UNIT_EXIT" = "0" ]; then \
		echo "  $(GREEN)Unit tests:    PASSED$(RESET)"; \
	else \
		echo "  $(RED)Unit tests:    FAILED (exit code $$UNIT_EXIT)$(RESET)"; \
	fi; \
	if [ "$$PARITY_EXIT" = "0" ]; then \
		echo "  $(GREEN)Parity tests:  PASSED$(RESET)"; \
	elif [ "$$PARITY_EXIT" = "2" ]; then \
		echo "  $(YELLOW)Parity tests:  SKIPPED (functions not implemented)$(RESET)"; \
	else \
		echo "  $(RED)Parity tests:  FAILED (exit code $$PARITY_EXIT)$(RESET)"; \
	fi; \
	if [ "$$BROWSER_EXIT" = "0" ]; then \
		echo "  $(GREEN)Browser tests: PASSED$(RESET)"; \
	else \
		echo "  $(RED)Browser tests: FAILED (exit code $$BROWSER_EXIT)$(RESET)"; \
	fi; \
	echo ""; \
	rm -f ../.tmp/test-unit.log ../.tmp/test-unit.exit \
	      ../.tmp/test-parity.log ../.tmp/test-parity.exit \
	      ../.tmp/test-browser.log ../.tmp/test-browser.exit; \
	if [ "$$UNIT_EXIT" != "0" ] || ([ "$$PARITY_EXIT" != "0" ] && [ "$$PARITY_EXIT" != "2" ]) || [ "$$BROWSER_EXIT" != "0" ]; then \
		echo "$(RED)$(BOLD)Some tests FAILED$(RESET)"; \
		exit 1; \
	else \
		echo "$(GREEN)$(BOLD)All tests PASSED$(RESET)"; \
	fi

# Clean build artifacts
clean:
	@echo "$(CYAN)Cleaning build artifacts...$(RESET)"
	@rm -rf zig-out .zig-cache
	@rm -rf browser-test/node_modules
	@rm -f ../.tmp/test-*.log ../.tmp/test-*.exit
	@echo "$(GREEN)Clean complete$(RESET)"

# Help target
help:
	@echo "$(BOLD)Zig CR-SQLite Makefile$(RESET)"
	@echo ""
	@echo "$(BOLD)Test Targets:$(RESET)"
	@echo "  $(CYAN)make test$(RESET)         - Run all tests concurrently (unit + parity + browser)"
	@echo "  $(CYAN)make test-unit$(RESET)    - Run Zig unit tests only"
	@echo "  $(CYAN)make test-parity$(RESET)  - Run shell parity tests only"
	@echo "  $(CYAN)make test-browser$(RESET) - Run Playwright browser tests only"
	@echo ""
	@echo "$(BOLD)Build Targets:$(RESET)"
	@echo "  $(CYAN)make build$(RESET)        - Build the Zig extension"
	@echo "  $(CYAN)make clean$(RESET)        - Clean build artifacts"
	@echo ""
	@echo "$(BOLD)Other:$(RESET)"
	@echo "  $(CYAN)make help$(RESET)         - Show this help"
	@echo ""
	@echo "$(BOLD)Test Suite Details:$(RESET)"
	@echo "  - Unit tests:   Zig build test (in-language unit tests)"
	@echo "  - Parity tests: Shell scripts validating against C test contracts"
	@echo "  - Browser tests: Playwright + sql.js (WASM in real browser)"
