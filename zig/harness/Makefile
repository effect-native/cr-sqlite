# Test harness for Zig CR-SQLite extension
# Run from zig/harness/ directory

.PHONY: all test test-rowid clean help

all: test

test: test-rowid

test-rowid:
	@bash test-rowid-slab.sh

clean:
	@echo "Nothing to clean"

help:
	@echo "Available targets:"
	@echo "  test-rowid  - Run rowid slab allocation tests"
	@echo "  test        - Run all tests (alias for test-rowid)"
	@echo "  help        - Show this help"
