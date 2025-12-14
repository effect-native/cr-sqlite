/**
 * Oracle Test Harness
 * Runs original CR-SQLite C tests against the Zig-built extension
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sqlite3.h"

#ifndef ZIG_CRSQLITE_PATH
#error "ZIG_CRSQLITE_PATH must be defined"
#endif

// Override sqlite3_open to auto-load the Zig extension
static int harness_open(const char *filename, sqlite3 **ppDb) {
    int rc = sqlite3_open(filename, ppDb);
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

// crsql_close shim
int crsql_close(sqlite3 *db) {
    sqlite3_exec(db, "SELECT crsql_finalize()", NULL, NULL, NULL);
    return sqlite3_close(db);
}

// Macro to redirect sqlite3_open
#define sqlite3_open(path, db) harness_open(path, db)

// Test suite declarations
extern void crsqlChangesVtabRowidTestSuite(void);
extern void crsqlChangesVtabTestSuite(void);
extern void rowsImpactedTestSuite(void);
extern void crsqlIsCrrTestSuite(void);

#define SUITE(N) if (strcmp(suite, "all") == 0 || strcmp(suite, N) == 0)

int main(int argc, char *argv[]) {
    char *suite = argc > 1 ? argv[1] : "all";
    
    printf("=== CR-SQLite Oracle Test Harness ===\n");
    printf("Extension: %s\n", ZIG_CRSQLITE_PATH);
    printf("Suite: %s\n\n", suite);
    
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
    SUITE("is_crr") crsqlIsCrrTestSuite();
    
    printf("\n=== Tests Complete ===\n");
    return 0;
}
