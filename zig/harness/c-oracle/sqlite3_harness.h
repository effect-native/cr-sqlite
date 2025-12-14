/**
 * Wrapper header to intercept sqlite3_open calls
 * Force-included via -include before any other headers
 * 
 * We also define SQLITE_CORE (in Makefile) so that sqlite3ext.h doesn't
 * remap functions through sqlite3_api pointer. This lets tests call
 * sqlite3 functions directly while we intercept sqlite3_open.
 */
#ifndef SQLITE3_HARNESS_H
#define SQLITE3_HARNESS_H

#include "sqlite3.h"

#ifndef ZIG_CRSQLITE_PATH
#error "ZIG_CRSQLITE_PATH must be defined"
#endif

// Declare harness_open (defined in harness.c)
int harness_open(const char *filename, sqlite3 **ppDb);

// Override sqlite3_open to auto-load extension
#define sqlite3_open(path, db) harness_open(path, db)

#endif /* SQLITE3_HARNESS_H */
