# C Test Oracle Harness
# Runs original CR-SQLite C tests against the Zig-built extension

CC := gcc
CFLAGS := -std=c99 -g -Wall -Wno-unused-function

# SQLite paths - use nix sqlite which has load_extension enabled
# System macOS sqlite has SQLITE_OMIT_LOAD_EXTENSION
SQLITE_DEV := $(shell nix eval nixpkgs\#sqlite.dev.outPath --raw 2>/dev/null)
SQLITE_LIB := $(shell nix eval nixpkgs\#sqlite.out.outPath --raw 2>/dev/null)
SQLITE_CFLAGS := -I$(SQLITE_DEV)/include
SQLITE_LIBS := -L$(SQLITE_LIB)/lib -lsqlite3 -Wl,-rpath,$(SQLITE_LIB)/lib

# Paths
CORE_SRC := ../../../core/src
ZIG_OUT := ../../zig-out/lib

# Extension path (platform-specific)
ifeq ($(shell uname -s),Darwin)
    EXT_PATH ?= $(ZIG_OUT)/libcrsqlite.dylib
else
    EXT_PATH ?= $(ZIG_OUT)/libcrsqlite.so
endif

# Test source files 
# Excluded:
#   - ext-data.test.c: uses internal structs (crsql_ExtData)
#   - is-crr.test.c: calls internal crsql_is_crr() function
TEST_SRCS := \
    $(CORE_SRC)/changes-vtab-rowid.test.c \
    $(CORE_SRC)/changes-vtab.test.c \
    $(CORE_SRC)/rows-impacted.test.c \
    $(CORE_SRC)/crsqlite.test.c \
    $(CORE_SRC)/sandbox.test.c \
    $(CORE_SRC)/rs-fract.test.c

HARNESS_SRC := harness.c

.PHONY: all test clean check-ext

all: crsql-oracle-test

check-ext:
	@test -f $(EXT_PATH) || (echo "Error: Extension not found at $(EXT_PATH). Run 'cd ../.. && zig build' first." && exit 1)

# Define SQLITE_CORE to prevent sqlite3ext.h from remapping functions through sqlite3_api
# This lets tests use direct sqlite3_* calls while we intercept sqlite3_open
crsql-oracle-test: $(HARNESS_SRC) $(TEST_SRCS) sqlite3_harness.h check-ext
	$(CC) $(CFLAGS) $(SQLITE_CFLAGS) \
	    -I. -I$(CORE_SRC) \
	    -DSQLITE_CORE \
	    -include sqlite3_harness.h \
	    -DZIG_CRSQLITE_PATH=\"$(EXT_PATH)\" \
	    $(HARNESS_SRC) $(TEST_SRCS) \
	    $(SQLITE_LIBS) -o $@

test: crsql-oracle-test
	./crsql-oracle-test

test-suite-%: crsql-oracle-test
	./crsql-oracle-test $*

clean:
	rm -f crsql-oracle-test
