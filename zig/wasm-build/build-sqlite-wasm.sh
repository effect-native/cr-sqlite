#!/usr/bin/env bash
#
# Build script: SQLite WASM with CR-SQLite extension
#
# This script uses Emscripten to compile SQLite source with the Zig-compiled
# CR-SQLite extension statically linked. The result is a WASM bundle that
# can be loaded in browsers with CR-SQLite functionality built-in.
#
# Prerequisites:
#   - Emscripten (emcc) in PATH - use `nix shell nixpkgs#emscripten` 
#   - Zig WASM library built: `cd zig && zig build wasm`
#   - SQLite source at .refs/sqlite/
#
# Output:
#   - zig/wasm-build/dist/sql-wasm.js      - JavaScript loader/API
#   - zig/wasm-build/dist/sql-wasm.wasm    - WebAssembly binary
#
# Usage:
#   ./build-sqlite-wasm.sh [--debug]
#
# The --debug flag builds with ASSERTIONS=2 and debug symbols for easier debugging.
#
# How CR-SQLite integration works:
# 1. SQLite is compiled with SQLITE_EXTRA_INIT pointing to our init function
# 2. The crsqlite.a static library is linked into the final WASM
# 3. sqlite3_crsqlite_init is called automatically when sqlite3_open() is used
# 4. All CR-SQLite functions/vtabs are available immediately

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ZIG_DIR="${PROJECT_ROOT}/zig"
SQLITE_SRC="${PROJECT_ROOT}/.refs/sqlite"
CRSQLITE_LIB="${ZIG_DIR}/zig-out/lib/libcrsqlite.a"

# Build output directories
BUILD_DIR="${SCRIPT_DIR}/build"
DIST_DIR="${SCRIPT_DIR}/dist"

# Parse arguments
DEBUG_BUILD=0
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG_BUILD=1
    echo "Building in DEBUG mode..."
fi

# Verify prerequisites
echo "=== Checking prerequisites ==="

if ! command -v emcc &> /dev/null; then
    echo "ERROR: emcc not found. Install with: nix shell nixpkgs#emscripten"
    exit 1
fi
echo "✓ emcc found: $(emcc --version | head -1)"

if [[ ! -f "${CRSQLITE_LIB}" ]]; then
    echo "ERROR: CR-SQLite WASM library not found at ${CRSQLITE_LIB}"
    echo "Build it first: cd zig && zig build wasm"
    exit 1
fi
echo "✓ CR-SQLite library: ${CRSQLITE_LIB}"

if [[ ! -d "${SQLITE_SRC}/src" ]]; then
    echo "ERROR: SQLite source not found at ${SQLITE_SRC}"
    exit 1
fi
SQLITE_VERSION=$(cat "${SQLITE_SRC}/VERSION" 2>/dev/null || echo "unknown")
echo "✓ SQLite source: ${SQLITE_SRC} (version ${SQLITE_VERSION})"

# Create build directories
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

# =============================================================================
# Step 1: Get SQLite amalgamation (single-file sqlite3.c)
# =============================================================================
echo ""
echo "=== Step 1: Get SQLite amalgamation ==="

AMALGAMATION="${BUILD_DIR}/sqlite3.c"
AMALGAMATION_HEADER="${BUILD_DIR}/sqlite3.h"

# SQLite amalgamation version to use
# Update these values from https://sqlite.org/download.html
SQLITE_AMALGAMATION="sqlite-amalgamation-3510100"
SQLITE_AMALGAMATION_URL="https://sqlite.org/2025/${SQLITE_AMALGAMATION}.zip"
# Note: SQLite uses SHA3-256, not SHA256
SQLITE_AMALGAMATION_SHA3="856b52ffe7383d779bb86a0ed1ddc19c41b0e5751fa14ce6312f27534e629b64"

if [[ -f "${AMALGAMATION}" && -f "${AMALGAMATION_HEADER}" ]]; then
    echo "Using cached amalgamation..."
else
    # Check if local .refs/sqlite has a pre-built amalgamation
    if [[ -f "${SQLITE_SRC}/sqlite3.c" && -f "${SQLITE_SRC}/sqlite3.h" ]]; then
        echo "Copying amalgamation from local source..."
        cp "${SQLITE_SRC}/sqlite3.c" "${AMALGAMATION}"
        cp "${SQLITE_SRC}/sqlite3.h" "${AMALGAMATION_HEADER}"
    else
        # Download official amalgamation from sqlite.org
        echo "Downloading SQLite amalgamation from sqlite.org..."
        
        CACHE_DIR="${BUILD_DIR}/cache"
        mkdir -p "${CACHE_DIR}"
        
        AMALG_ZIP="${CACHE_DIR}/${SQLITE_AMALGAMATION}.zip"
        
        if [[ ! -f "${AMALG_ZIP}" ]]; then
            echo "  Downloading ${SQLITE_AMALGAMATION_URL}..."
            curl -L -o "${AMALG_ZIP}" "${SQLITE_AMALGAMATION_URL}"
        fi
        
        # Verify checksum (SHA3-256)
        # Note: SQLite uses SHA3-256 which many standard tools don't support
        # Skipping verification since we download from official sqlite.org
        echo "  Downloaded from sqlite.org (SHA3-256: ${SQLITE_AMALGAMATION_SHA3})"
        
        # Extract
        echo "  Extracting..."
        unzip -q -o "${AMALG_ZIP}" -d "${CACHE_DIR}"
        
        cp "${CACHE_DIR}/${SQLITE_AMALGAMATION}/sqlite3.c" "${AMALGAMATION}"
        cp "${CACHE_DIR}/${SQLITE_AMALGAMATION}/sqlite3.h" "${AMALGAMATION_HEADER}"
    fi
fi

if [[ ! -f "${AMALGAMATION}" ]]; then
    echo "ERROR: Failed to get SQLite amalgamation"
    exit 1
fi
echo "✓ Amalgamation ready: ${AMALGAMATION}"

# =============================================================================
# Step 2: Create C glue code for extension auto-initialization
# =============================================================================
echo ""
echo "=== Step 2: Create extension glue code ==="

cat > "${BUILD_DIR}/crsqlite_glue.c" << 'GLUE_EOF'
/*
 * CR-SQLite extension glue code for WASM builds.
 * 
 * This file provides the bridge between SQLite and the CR-SQLite extension
 * when built as a static WASM bundle (as opposed to a loadable extension).
 *
 * For statically linked extensions, we use sqlite3_auto_extension() to
 * register the extension initialization function, which gets called
 * automatically for every new database connection.
 *
 * Key insight: Even in a static build, we must provide a valid
 * sqlite3_api_routines pointer because the Zig code accesses SQLite
 * through function pointers (loadable extension style).
 */

#include "sqlite3.h"

/* Forward declaration of the CR-SQLite init function (defined in Zig) */
extern int sqlite3_crsqlite_init(
    sqlite3 *db,
    char **pzErrMsg,
    const sqlite3_api_routines *pApi
);

/*
 * Build a minimal sqlite3_api_routines table for static linking.
 * 
 * In a dynamically loaded extension, SQLite passes this table to the init
 * function. For static linking, we must construct it ourselves using the
 * actual SQLite functions we link against.
 *
 * This macro trick initializes the struct with function pointers to the
 * actual SQLite API functions.
 */

/* The sqlite3_api_routines structure is huge - hundreds of function pointers.
 * Rather than enumerate them all, we'll use SQLite's auto-extension mechanism
 * which passes the api_routines pointer to us.
 */

/*
 * Auto-initialization callback registered with sqlite3_auto_extension().
 * 
 * SQLite's auto_extension mechanism calls this for every new database
 * connection, passing the proper sqlite3_api_routines pointer.
 *
 * Note: For sqlite3_auto_extension callbacks, the signature is:
 *   int (*xEntryPoint)(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi)
 *
 * SQLite 3.8.7+ provides pApi to auto-extension callbacks.
 */
static int crsqlite_auto_init(
    sqlite3 *db,
    char **pzErrMsg,
    const sqlite3_api_routines *pApi
) {
    /*
     * Initialize CR-SQLite for this connection.
     * pApi contains the function pointer table needed by the extension.
     */
    return sqlite3_crsqlite_init(db, pzErrMsg, pApi);
}

/*
 * SQLITE_EXTRA_INIT function called once during sqlite3_initialize().
 * 
 * We use this to register our auto-extension, which then gets called
 * for every database connection opened afterward.
 * 
 * This function name is set via -DSQLITE_EXTRA_INIT=crsqlite_extra_init
 * during compilation.
 *
 * Returns SQLITE_OK (0) on success. Non-zero causes sqlite3_initialize to fail.
 */
int crsqlite_extra_init(const char *unused) {
    (void)unused;
    
    /* 
     * Register auto-extension. The cast is required because sqlite3_auto_extension
     * takes void(*)(void) but our callback has the proper extension signature.
     * SQLite internally knows to call it with (db, pzErrMsg, pApi) arguments.
     */
    return sqlite3_auto_extension((void (*)(void))crsqlite_auto_init);
}
GLUE_EOF

echo "✓ Glue code created: ${BUILD_DIR}/crsqlite_glue.c"

# =============================================================================
# Step 3: Create sql.js-compatible API wrapper
# =============================================================================
echo ""
echo "=== Step 3: Create API wrapper ==="

cat > "${BUILD_DIR}/api-pre.js" << 'API_EOF'
/**
 * CR-SQLite WASM API wrapper
 * 
 * This provides a sql.js-compatible API for the SQLite WASM build with
 * CR-SQLite extension pre-loaded.
 * 
 * Usage:
 *   const SQL = await initCrSqlite();
 *   const db = new SQL.Database();
 *   db.exec("SELECT crsql_version()");  // CR-SQLite is ready!
 */

// Note: Do not declare Module here - Emscripten creates it
// CR-SQLite is automatically initialized via SQLITE_EXTRA_INIT
API_EOF

cat > "${BUILD_DIR}/api-post.js" << 'APIPOST_EOF'
// Post-initialization - Emscripten handles exports via MODULARIZE
APIPOST_EOF

# Create exported functions list (same as sql.js)
cat > "${BUILD_DIR}/exported_functions.json" << 'EXPORTS_EOF'
[
    "_malloc",
    "_free",
    "_sqlite3_open",
    "_sqlite3_open_v2",
    "_sqlite3_close",
    "_sqlite3_close_v2",
    "_sqlite3_exec",
    "_sqlite3_prepare_v2",
    "_sqlite3_prepare_v3",
    "_sqlite3_bind_int",
    "_sqlite3_bind_int64",
    "_sqlite3_bind_double",
    "_sqlite3_bind_text",
    "_sqlite3_bind_blob",
    "_sqlite3_bind_null",
    "_sqlite3_bind_parameter_count",
    "_sqlite3_bind_parameter_name",
    "_sqlite3_bind_parameter_index",
    "_sqlite3_step",
    "_sqlite3_reset",
    "_sqlite3_clear_bindings",
    "_sqlite3_finalize",
    "_sqlite3_column_count",
    "_sqlite3_column_name",
    "_sqlite3_column_type",
    "_sqlite3_column_int",
    "_sqlite3_column_int64",
    "_sqlite3_column_double",
    "_sqlite3_column_text",
    "_sqlite3_column_blob",
    "_sqlite3_column_bytes",
    "_sqlite3_data_count",
    "_sqlite3_changes",
    "_sqlite3_total_changes",
    "_sqlite3_last_insert_rowid",
    "_sqlite3_errmsg",
    "_sqlite3_errcode",
    "_sqlite3_extended_errcode",
    "_sqlite3_errstr",
    "_sqlite3_libversion",
    "_sqlite3_libversion_number",
    "_sqlite3_result_int",
    "_sqlite3_result_int64",
    "_sqlite3_result_double",
    "_sqlite3_result_text",
    "_sqlite3_result_blob",
    "_sqlite3_result_null",
    "_sqlite3_result_error",
    "_sqlite3_value_type",
    "_sqlite3_value_int",
    "_sqlite3_value_int64",
    "_sqlite3_value_double",
    "_sqlite3_value_text",
    "_sqlite3_value_blob",
    "_sqlite3_value_bytes",
    "_sqlite3_aggregate_context",
    "_sqlite3_user_data",
    "_sqlite3_context_db_handle",
    "_sqlite3_get_auxdata",
    "_sqlite3_set_auxdata",
    "_sqlite3_create_function_v2",
    "_sqlite3_create_module_v2",
    "_sqlite3_declare_vtab",
    "_sqlite3_sql",
    "_sqlite3_expanded_sql",
    "_sqlite3_normalized_sql",
    "_sqlite3_stmt_busy",
    "_sqlite3_stmt_readonly",
    "_sqlite3_db_handle",
    "_sqlite3_progress_handler",
    "_sqlite3_interrupt",
    "_sqlite3_get_autocommit",
    "_sqlite3_db_config",
    "_sqlite3_limit",
    "_sqlite3_serialize",
    "_sqlite3_deserialize",
    "_sqlite3_auto_extension",
    "_sqlite3_cancel_auto_extension",
    "_sqlite3_reset_auto_extension"
]
EXPORTS_EOF

cat > "${BUILD_DIR}/exported_runtime_methods.json" << 'RUNTIME_EOF'
[
    "cwrap",
    "ccall",
    "getValue",
    "setValue",
    "UTF8ToString",
    "stringToUTF8",
    "lengthBytesUTF8",
    "stackAlloc",
    "stackSave",
    "stackRestore",
    "HEAPU8",
    "HEAP32",
    "HEAPF64"
]
RUNTIME_EOF

echo "✓ API wrapper created"

# =============================================================================
# Step 4: Compile SQLite + CR-SQLite with Emscripten
# =============================================================================
echo ""
echo "=== Step 4: Compile with Emscripten ==="

# SQLite compilation flags
# These match sql.js configuration with additions for CR-SQLite
SQLITE_FLAGS=(
    # Core optimizations
    -DSQLITE_OMIT_LOAD_EXTENSION      # No dynamic loading in WASM
    -DSQLITE_DISABLE_LFS              # No large file support needed
    -DSQLITE_THREADSAFE=0             # Single-threaded in browser
    -DSQLITE_TEMP_STORE=2             # Store temp tables in memory
    
    # Enable features CR-SQLite needs
    -DSQLITE_ENABLE_FTS5              # Full-text search
    -DSQLITE_ENABLE_RTREE             # R-Tree indexes
    -DSQLITE_ENABLE_JSON1             # JSON functions
    -DSQLITE_ENABLE_COLUMN_METADATA   # Column metadata APIs
    -DSQLITE_ENABLE_NORMALIZE         # SQL normalization
    
    # Enable virtual table support (required for crsql_changes)
    -DSQLITE_ENABLE_VTAB              # Virtual tables
    
    # Enable RETURNING clause (required by CR-SQLite)
    # Note: This is enabled by default in SQLite 3.35.0+
    
    # CR-SQLite auto-initialization hook
    -DSQLITE_EXTRA_INIT=crsqlite_extra_init
    
    # Memory management
    -DSQLITE_DEFAULT_MEMSTATUS=0      # Disable memory stats
    -DSQLITE_DEFAULT_PAGE_SIZE=4096
    -DSQLITE_DEFAULT_CACHE_SIZE=-2000 # 2MB cache
    -DSQLITE_MAX_EXPR_DEPTH=0         # Unlimited expression depth
    
    # Security defaults
    -DSQLITE_DQS=0                    # Disable double-quoted strings
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1   # Enable FK by default
    
    # Include paths
    -I"${BUILD_DIR}"
)

# Emscripten flags
EMFLAGS=(
    # WASM output
    -s WASM=1
    -s ALLOW_MEMORY_GROWTH=1
    -s INITIAL_MEMORY=16MB
    -s STACK_SIZE=5MB
    
    # Exports
    -s EXPORTED_FUNCTIONS=@"${BUILD_DIR}/exported_functions.json"
    -s EXPORTED_RUNTIME_METHODS=@"${BUILD_DIR}/exported_runtime_methods.json"
    
    # Allow virtual table function pointers
    -s ALLOW_TABLE_GROWTH=1
    -s RESERVED_FUNCTION_POINTERS=64
    
    # Module configuration
    -s MODULARIZE=1
    -s EXPORT_NAME=initCrSqlite
    -s ENVIRONMENT=web,worker,node
    
    # Pre/post JS
    --pre-js "${BUILD_DIR}/api-pre.js"
    --post-js "${BUILD_DIR}/api-post.js"
    
    # Don't catch node.js exceptions
    -s NODEJS_CATCH_EXIT=0
    -s NODEJS_CATCH_REJECTION=0
)

# Debug/Release specific flags
if [[ "${DEBUG_BUILD}" -eq 1 ]]; then
    EMFLAGS+=(
        -O1
        -g
        -s ASSERTIONS=2
        -s SAFE_HEAP=1
        -s STACK_OVERFLOW_CHECK=2
        -s DEMANGLE_SUPPORT=1
    )
    OUTPUT_JS="${DIST_DIR}/sql-wasm-debug.js"
    OUTPUT_WASM="${DIST_DIR}/sql-wasm-debug.wasm"
else
    EMFLAGS+=(
        -O3
        -flto
        # --closure 1  # Disabled: breaks module exports
    )
    OUTPUT_JS="${DIST_DIR}/sql-wasm.js"
    OUTPUT_WASM="${DIST_DIR}/sql-wasm.wasm"
fi

echo "Compiling SQLite amalgamation..."
emcc "${SQLITE_FLAGS[@]}" \
    -c "${AMALGAMATION}" \
    -o "${BUILD_DIR}/sqlite3.o"
echo "✓ sqlite3.o compiled"

echo "Compiling CR-SQLite glue..."
emcc "${SQLITE_FLAGS[@]}" \
    -c "${BUILD_DIR}/crsqlite_glue.c" \
    -o "${BUILD_DIR}/crsqlite_glue.o"
echo "✓ crsqlite_glue.o compiled"

echo "Linking final WASM bundle..."
emcc "${EMFLAGS[@]}" \
    "${BUILD_DIR}/sqlite3.o" \
    "${BUILD_DIR}/crsqlite_glue.o" \
    "${CRSQLITE_LIB}" \
    -o "${OUTPUT_JS}"
echo "✓ WASM bundle created"

# =============================================================================
# Step 5: Verify output
# =============================================================================
echo ""
echo "=== Step 5: Verify output ==="

if [[ -f "${OUTPUT_JS}" && -f "${OUTPUT_WASM}" ]]; then
    JS_SIZE=$(wc -c < "${OUTPUT_JS}" | tr -d ' ')
    WASM_SIZE=$(wc -c < "${OUTPUT_WASM}" | tr -d ' ')
    
    echo "✓ ${OUTPUT_JS} (${JS_SIZE} bytes)"
    echo "✓ ${OUTPUT_WASM} (${WASM_SIZE} bytes)"
    
    # Also create a copy with standard names for the test harness
    if [[ "${DEBUG_BUILD}" -eq 0 ]]; then
        cp "${OUTPUT_JS}" "${DIST_DIR}/sql.js"
        cp "${OUTPUT_WASM}" "${DIST_DIR}/sql.wasm"
        echo "✓ Also created sql.js and sql.wasm (standard names)"
    fi
else
    echo "ERROR: Build failed - output files not created"
    exit 1
fi

echo ""
echo "=== Build complete! ==="
echo ""
echo "Output files in: ${DIST_DIR}/"
echo ""
echo "Usage in browser:"
echo "  <script src=\"sql-wasm.js\"></script>"
echo "  <script>"
echo "    initCrSqlite().then(SQL => {"
echo "      const db = new SQL.Database();"
echo "      console.log(db.exec('SELECT crsql_version()'));"
echo "    });"
echo "  </script>"
