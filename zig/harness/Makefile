# Test harness for Zig CR-SQLite extension
# Run from zig/harness/ directory
#
# Usage:
#   make test       - Run all tests (parity suite)
#   make test-quick - Run individual test scripts
#   make help       - Show all available targets

.PHONY: all test test-parity test-rowid test-merge test-filters test-e2e test-alter clean help

all: test

# Main test target: runs the comprehensive parity suite
test: test-parity

# Full parity test suite (runs all sub-tests)
test-parity:
	@bash test-parity.sh

# Individual test scripts
test-rowid:
	@bash test-rowid-slab.sh

test-merge:
	@bash test-merge.sh

test-filters:
	@bash test-filters.sh

test-e2e:
	@bash test-e2e-sync.sh

test-alter:
	@bash test-alter.sh

# Run all individual tests (alternative to test-parity)
test-quick: test-rowid test-merge test-filters test-e2e test-alter

clean:
	@echo "Nothing to clean"

help:
	@echo "Zig CR-SQLite Test Harness"
	@echo ""
	@echo "Main targets:"
	@echo "  test          - Run full parity test suite (recommended)"
	@echo "  test-parity   - Same as 'test'"
	@echo ""
	@echo "Individual tests:"
	@echo "  test-rowid    - Rowid slab allocation (changes-vtab-rowid.test.c)"
	@echo "  test-merge    - Merge semantics and rows_impacted (rows-impacted.test.c)"
	@echo "  test-filters  - Filter pushdown (changes-vtab.test.c:testFilters)"
	@echo "  test-e2e      - End-to-end sync (crsqlite.test.c:teste2e)"
	@echo "  test-alter    - Schema alter (crsql_begin_alter/commit_alter)"
	@echo ""
	@echo "Other:"
	@echo "  test-quick    - Run all individual tests (no summary)"
	@echo "  help          - Show this help"
