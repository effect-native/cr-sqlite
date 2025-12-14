/**
 * Oracle Test Harness
 * Runs original CR-SQLite C tests against the Zig-built extension
 * 
 * This harness intercepts sqlite3_open calls to auto-load the Zig extension.
 * We compile with -DSQLITE_CORE so that sqlite3ext.h doesn't remap functions
 * through sqlite3_api pointer, allowing tests to use direct sqlite3 calls.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Include sqlite3.h BEFORE our macro redefinition takes effect
#include "sqlite3.h"

#ifndef ZIG_CRSQLITE_PATH
#error "ZIG_CRSQLITE_PATH must be defined"
#endif

// Keep a reference to the real sqlite3_open before any macros
static int (*real_sqlite3_open)(const char *, sqlite3 **) = sqlite3_open;

// harness_open - loads the Zig extension after opening db
// Exported so test files can use it via the sqlite3_open macro
int harness_open(const char *filename, sqlite3 **ppDb) {
    int rc = real_sqlite3_open(filename, ppDb);
    if (rc != SQLITE_OK) return rc;
    
    sqlite3_db_config(*ppDb, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 1, NULL);
    
    char *errmsg = NULL;
    rc = sqlite3_load_extension(*ppDb, ZIG_CRSQLITE_PATH, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to load extension: %s\n", errmsg ? errmsg : "unknown");
        sqlite3_free(errmsg);
        sqlite3_close(*ppDb);
        *ppDb = NULL;
        return rc;
    }
    return SQLITE_OK;
}

// crsql_close shim - calls crsql_finalize before closing
int crsql_close(sqlite3 *db) {
    sqlite3_exec(db, "SELECT crsql_finalize()", NULL, NULL, NULL);
    return sqlite3_close(db);
}

// Test suite declarations
extern void crsqlChangesVtabRowidTestSuite(void);
extern void crsqlChangesVtabTestSuite(void);
extern void rowsImpactedTestSuite(void);

#define SUITE(N) if (strcmp(suite, "all") == 0 || strcmp(suite, N) == 0)

int main(int argc, char *argv[]) {
    char *suite = argc > 1 ? argv[1] : "all";
    
    printf("=== CR-SQLite Oracle Test Harness ===\n");
    printf("Extension: %s\n", ZIG_CRSQLITE_PATH);
    printf("Suite: %s\n\n", suite);
    fflush(stdout);
    
    // Verify extension loads
    sqlite3 *probe = NULL;
    if (harness_open(":memory:", &probe) != SQLITE_OK) {
        fprintf(stderr, "FATAL: Cannot load extension\n");
        return 1;
    }
    crsql_close(probe);
    
    SUITE("rowid") crsqlChangesVtabRowidTestSuite();
    SUITE("vtab") crsqlChangesVtabTestSuite();
    SUITE("rows_impacted") rowsImpactedTestSuite();
    
    printf("\n=== Tests Complete ===\n");
    return 0;
}
