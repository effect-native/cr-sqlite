# C Test Oracle Harness
# Runs original CR-SQLite C tests against the Zig-built extension

CC := gcc
CFLAGS := -std=c99 -g -Wall -Wno-unused-function

# System SQLite (must support load_extension)
SQLITE_CFLAGS := $(shell pkg-config --cflags sqlite3 2>/dev/null || echo "")
SQLITE_LIBS := $(shell pkg-config --libs sqlite3 2>/dev/null || echo "-lsqlite3")

# Paths
CORE_SRC := ../../../core/src
ZIG_OUT := ../../zig-out/lib

# Extension path (platform-specific)
ifeq ($(shell uname -s),Darwin)
    EXT_PATH ?= $(ZIG_OUT)/libcrsqlite.dylib
else
    EXT_PATH ?= $(ZIG_OUT)/libcrsqlite.so
endif

# Test source files (exclude ext-data.test.c - uses internal structs)
TEST_SRCS := \
    $(CORE_SRC)/changes-vtab-rowid.test.c \
    $(CORE_SRC)/changes-vtab.test.c \
    $(CORE_SRC)/rows-impacted.test.c \
    $(CORE_SRC)/is-crr.test.c

HARNESS_SRC := harness.c

.PHONY: all test clean check-ext

all: crsql-oracle-test

check-ext:
	@test -f $(EXT_PATH) || (echo "Error: Extension not found at $(EXT_PATH). Run 'cd ../.. && zig build' first." && exit 1)

crsql-oracle-test: $(HARNESS_SRC) $(TEST_SRCS) check-ext
	$(CC) $(CFLAGS) $(SQLITE_CFLAGS) \
	    -I$(CORE_SRC) \
	    -DZIG_CRSQLITE_PATH=\"$(EXT_PATH)\" \
	    $(HARNESS_SRC) $(TEST_SRCS) \
	    $(SQLITE_LIBS) -o $@

test: crsql-oracle-test
	./crsql-oracle-test

test-suite-%: crsql-oracle-test
	./crsql-oracle-test $*

clean:
	rm -f crsql-oracle-test
