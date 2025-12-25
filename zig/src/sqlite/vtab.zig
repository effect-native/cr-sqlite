//! Writable Virtual Table Module Infrastructure for SQLite
//!
//! This module provides the Zig types and infrastructure needed to implement
//! writable SQLite virtual tables, including `xUpdate` and transaction callbacks.
//!
//! Reference: https://sqlite.org/vtab.html
//!
//! ## Module Version History
//!
//! The `sqlite3_module` struct has evolved over SQLite versions:
//! - **Version 0-1**: Core vtab methods (xCreate through xRename)
//! - **Version 2**: Added xSavepoint, xRelease, xRollbackTo
//! - **Version 3**: Added xShadowName
//! - **Version 4**: Added xIntegrity
//!
//! ## Required vs Optional Callbacks
//!
//! ### Required for ALL virtual tables:
//! - `xConnect` - Establish connection to existing vtab (required)
//! - `xBestIndex` - Query planning (required)
//! - `xDisconnect` - Release connection (required)
//! - `xOpen` - Create cursor (required)
//! - `xClose` - Destroy cursor (required)
//! - `xFilter` - Begin scan with constraints (required)
//! - `xNext` - Advance cursor (required)
//! - `xEof` - Check if cursor at end (required)
//! - `xColumn` - Read column value (required)
//! - `xRowid` - Get current rowid (required)
//!
//! ### Required for WRITABLE virtual tables:
//! - `xUpdate` - INSERT/UPDATE/DELETE operations
//!
//! ### Optional (but recommended for writable vtabs):
//! - `xCreate` - Create new vtab instance (NULL = eponymous-only)
//! - `xDestroy` - Drop vtab and backing store
//! - `xBegin` - Start transaction (required if xCommit is used)
//! - `xSync` - Two-phase commit sync
//! - `xCommit` - Commit transaction
//! - `xRollback` - Rollback transaction
//! - `xFindFunction` - Function overloading
//! - `xRename` - ALTER TABLE RENAME support
//! - `xSavepoint` - Nested transaction savepoint
//! - `xRelease` - Release savepoint
//! - `xRollbackTo` - Rollback to savepoint
//! - `xShadowName` - Shadow table detection
//! - `xIntegrity` - PRAGMA integrity_check support
//!
//! ## Usage Example
//!
//! ```zig
//! const MyVTab = struct {
//!     // Your vtab state here
//!     
//!     pub fn update(vtab: *VTab, argc: c_int, argv: [*c]?*Value, rowid: *i64) c_int {
//!         // Handle INSERT/UPDATE/DELETE
//!         return SQLITE_OK;
//!     }
//! };
//! 
//! // Create module with writable callbacks
//! const module = Module.init(.{
//!     .xUpdate = MyVTab.update,
//!     .xBegin = MyVTab.begin,
//!     .xCommit = MyVTab.commit,
//!     .xRollback = MyVTab.rollback,
//! });
//! ```

const std = @import("std");
const builtin = @import("builtin");

// Logging disabled: std.log uses std.io.getStdErr() which crashes when called from
// a dynamically loaded shared library on Linux. The Zig runtime isn't properly
// initialized in that context, causing segfaults.
const log = struct {
    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        _ = fmt;
        _ = args;
    }
};

// =============================================================================
// SQLite C ABI Type Definitions
// =============================================================================

/// SQLite result codes
pub const SQLITE_OK = 0;
pub const SQLITE_ERROR = 1;
pub const SQLITE_INTERNAL = 2;
pub const SQLITE_PERM = 3;
pub const SQLITE_ABORT = 4;
pub const SQLITE_BUSY = 5;
pub const SQLITE_LOCKED = 6;
pub const SQLITE_NOMEM = 7;
pub const SQLITE_READONLY = 8;
pub const SQLITE_INTERRUPT = 9;
pub const SQLITE_IOERR = 10;
pub const SQLITE_CORRUPT = 11;
pub const SQLITE_NOTFOUND = 12;
pub const SQLITE_FULL = 13;
pub const SQLITE_CANTOPEN = 14;
pub const SQLITE_PROTOCOL = 15;
pub const SQLITE_EMPTY = 16;
pub const SQLITE_SCHEMA = 17;
pub const SQLITE_TOOBIG = 18;
pub const SQLITE_CONSTRAINT = 19;
pub const SQLITE_MISMATCH = 20;
pub const SQLITE_MISUSE = 21;
pub const SQLITE_NOLFS = 22;
pub const SQLITE_AUTH = 23;
pub const SQLITE_FORMAT = 24;
pub const SQLITE_RANGE = 25;
pub const SQLITE_NOTADB = 26;
pub const SQLITE_NOTICE = 27;
pub const SQLITE_WARNING = 28;
pub const SQLITE_ROW = 100;
pub const SQLITE_DONE = 101;

/// Index constraint operator codes from sqlite3.h
pub const SQLITE_INDEX_CONSTRAINT_EQ = 2;
pub const SQLITE_INDEX_CONSTRAINT_GT = 4;
pub const SQLITE_INDEX_CONSTRAINT_LE = 8;
pub const SQLITE_INDEX_CONSTRAINT_LT = 16;
pub const SQLITE_INDEX_CONSTRAINT_GE = 32;
pub const SQLITE_INDEX_CONSTRAINT_MATCH = 64;
pub const SQLITE_INDEX_CONSTRAINT_LIKE = 65;
pub const SQLITE_INDEX_CONSTRAINT_GLOB = 66;
pub const SQLITE_INDEX_CONSTRAINT_REGEXP = 67;
pub const SQLITE_INDEX_CONSTRAINT_NE = 68;
pub const SQLITE_INDEX_CONSTRAINT_ISNOT = 69;
pub const SQLITE_INDEX_CONSTRAINT_ISNOTNULL = 70;
pub const SQLITE_INDEX_CONSTRAINT_ISNULL = 71;
pub const SQLITE_INDEX_CONSTRAINT_IS = 72;
pub const SQLITE_INDEX_CONSTRAINT_LIMIT = 73;
pub const SQLITE_INDEX_CONSTRAINT_OFFSET = 74;
pub const SQLITE_INDEX_CONSTRAINT_FUNCTION = 150;

/// Index scan flags
pub const SQLITE_INDEX_SCAN_UNIQUE = 1;

// =============================================================================
// SQLite C ABI Struct Definitions
// =============================================================================

/// Opaque pointer types from SQLite C API
pub const sqlite3 = opaque {};
pub const sqlite3_context = opaque {};
pub const sqlite3_value = opaque {};

/// sqlite3_vtab - Base structure for virtual table instances
///
/// Virtual table implementations typically embed this as the first field
/// of their own structure to allow pointer casting.
///
/// Fields:
/// - pModule: Pointer to the sqlite3_module (set by SQLite core)
/// - nRef: Reference count (managed by SQLite core, do not modify)
/// - zErrMsg: Error message text (allocated via sqlite3_malloc, freed by core)
pub const VTab = extern struct {
    pModule: ?*const Module,
    nRef: c_int,
    zErrMsg: [*c]u8,
};

/// sqlite3_vtab_cursor - Base structure for virtual table cursors
///
/// Virtual table implementations typically embed this as the first field
/// of their cursor structure to allow pointer casting.
///
/// Fields:
/// - pVtab: Pointer back to the virtual table instance
pub const VTabCursor = extern struct {
    pVtab: ?*VTab,
};

/// sqlite3_index_constraint - WHERE clause constraint info (input to xBestIndex)
pub const IndexConstraint = extern struct {
    iColumn: c_int,
    op: u8,
    usable: u8,
    iTermOffset: c_int,
};

/// sqlite3_index_orderby - ORDER BY clause info (input to xBestIndex)
pub const IndexOrderBy = extern struct {
    iColumn: c_int,
    desc: u8,
};

/// sqlite3_index_constraint_usage - Constraint usage info (output from xBestIndex)
pub const IndexConstraintUsage = extern struct {
    argvIndex: c_int,
    omit: u8,
};

/// sqlite3_index_info - Query planning information structure
///
/// Passed to xBestIndex for query optimization. Contains:
/// - Inputs: nConstraint, aConstraint, nOrderBy, aOrderBy, colUsed
/// - Outputs: aConstraintUsage, idxNum, idxStr, needToFreeIdxStr,
///            orderByConsumed, estimatedCost, estimatedRows, idxFlags
pub const IndexInfo = extern struct {
    // Inputs
    nConstraint: c_int,
    aConstraint: [*c]IndexConstraint,
    nOrderBy: c_int,
    aOrderBy: [*c]IndexOrderBy,
    // Outputs
    aConstraintUsage: [*c]IndexConstraintUsage,
    idxNum: c_int,
    idxStr: [*c]u8,
    needToFreeIdxStr: c_int,
    orderByConsumed: c_int,
    estimatedCost: f64,
    // SQLite 3.8.2+
    estimatedRows: i64,
    // SQLite 3.9.0+
    idxFlags: c_int,
    // SQLite 3.10.0+
    colUsed: u64,
};

// =============================================================================
// Function Pointer Type Definitions
// =============================================================================

/// xCreate/xConnect callback type
pub const XCreateFn = *const fn (
    db: ?*sqlite3,
    pAux: ?*anyopaque,
    argc: c_int,
    argv: [*c]const [*c]const u8,
    ppVTab: [*c]?*VTab,
    pzErr: [*c][*c]u8,
) callconv(.c) c_int;

/// xBestIndex callback type
pub const XBestIndexFn = *const fn (
    pVTab: ?*VTab,
    pIndexInfo: ?*IndexInfo,
) callconv(.c) c_int;

/// xDisconnect/xDestroy callback type
pub const XDisconnectFn = *const fn (pVTab: ?*VTab) callconv(.c) c_int;

/// xOpen callback type
pub const XOpenFn = *const fn (
    pVTab: ?*VTab,
    ppCursor: [*c]?*VTabCursor,
) callconv(.c) c_int;

/// xClose callback type
pub const XCloseFn = *const fn (pCursor: ?*VTabCursor) callconv(.c) c_int;

/// xFilter callback type
pub const XFilterFn = *const fn (
    pCursor: ?*VTabCursor,
    idxNum: c_int,
    idxStr: [*c]const u8,
    argc: c_int,
    argv: [*c]?*sqlite3_value,
) callconv(.c) c_int;

/// xNext callback type
pub const XNextFn = *const fn (pCursor: ?*VTabCursor) callconv(.c) c_int;

/// xEof callback type
pub const XEofFn = *const fn (pCursor: ?*VTabCursor) callconv(.c) c_int;

/// xColumn callback type
pub const XColumnFn = *const fn (
    pCursor: ?*VTabCursor,
    pCtx: ?*sqlite3_context,
    n: c_int,
) callconv(.c) c_int;

/// xRowid callback type
pub const XRowidFn = *const fn (
    pCursor: ?*VTabCursor,
    pRowid: *i64,
) callconv(.c) c_int;

/// xUpdate callback type - REQUIRED FOR WRITABLE VTABS
///
/// The xUpdate method handles INSERT, UPDATE, and DELETE operations:
///
/// - DELETE: argc=1, argv[0]=rowid to delete
/// - INSERT: argc>1, argv[0]=NULL, argv[1]=new rowid (or NULL for auto),
///           argv[2..] = column values
/// - UPDATE: argc>1, argv[0]=old rowid, argv[1]=new rowid,
///           argv[2..] = new column values
///
/// For INSERT with NULL rowid, implementation must set *pRowid to the
/// generated rowid (used by sqlite3_last_insert_rowid()).
pub const XUpdateFn = *const fn (
    pVTab: ?*VTab,
    argc: c_int,
    argv: [*c]?*sqlite3_value,
    pRowid: *i64,
) callconv(.c) c_int;

/// xBegin callback type - Start a transaction
///
/// If xBegin is not defined, xCommit will not be called.
/// Virtual table transactions do not nest.
pub const XBeginFn = *const fn (pVTab: ?*VTab) callconv(.c) c_int;

/// xSync callback type - Two-phase commit sync
pub const XSyncFn = *const fn (pVTab: ?*VTab) callconv(.c) c_int;

/// xCommit callback type - Commit a transaction
pub const XCommitFn = *const fn (pVTab: ?*VTab) callconv(.c) c_int;

/// xRollback callback type - Rollback a transaction
pub const XRollbackFn = *const fn (pVTab: ?*VTab) callconv(.c) c_int;

/// xFindFunction callback type
pub const XFindFunctionFn = *const fn (
    pVTab: ?*VTab,
    nArg: c_int,
    zName: [*c]const u8,
    pxFunc: *?*const fn (?*sqlite3_context, c_int, [*c]?*sqlite3_value) callconv(.c) void,
    ppArg: *?*anyopaque,
) callconv(.c) c_int;

/// xRename callback type
pub const XRenameFn = *const fn (
    pVTab: ?*VTab,
    zNew: [*c]const u8,
) callconv(.c) c_int;

/// xSavepoint callback type (version 2+)
pub const XSavepointFn = *const fn (pVTab: ?*VTab, n: c_int) callconv(.c) c_int;

/// xRelease callback type (version 2+)
pub const XReleaseFn = *const fn (pVTab: ?*VTab, n: c_int) callconv(.c) c_int;

/// xRollbackTo callback type (version 2+)
pub const XRollbackToFn = *const fn (pVTab: ?*VTab, n: c_int) callconv(.c) c_int;

/// xShadowName callback type (version 3+)
pub const XShadowNameFn = *const fn (zName: [*c]const u8) callconv(.c) c_int;

/// xIntegrity callback type (version 4+)
pub const XIntegrityFn = *const fn (
    pVTab: ?*VTab,
    zSchema: [*c]const u8,
    zTabName: [*c]const u8,
    mFlags: c_int,
    pzErr: [*c][*c]u8,
) callconv(.c) c_int;

// =============================================================================
// sqlite3_module Structure Definition
// =============================================================================

/// sqlite3_module - Virtual table module definition
///
/// This structure defines all the methods for a virtual table implementation.
/// It must match the exact layout of SQLite's C `sqlite3_module` struct for
/// ABI compatibility.
///
/// The struct layout is versioned via iVersion:
/// - iVersion 0-1: Fields through xRename
/// - iVersion 2: Adds xSavepoint, xRelease, xRollbackTo
/// - iVersion 3: Adds xShadowName
/// - iVersion 4: Adds xIntegrity
pub const Module = extern struct {
    /// Module version number (currently 0-4)
    iVersion: c_int = 0,

    // =========================================================================
    // Version 0-1 Methods (Core vtab functionality)
    // =========================================================================

    /// Create a new virtual table instance.
    /// Called for CREATE VIRTUAL TABLE statements.
    /// Set to NULL for eponymous-only virtual tables.
    /// Set equal to xConnect for eponymous virtual tables.
    xCreate: ?XCreateFn = null,

    /// Connect to an existing virtual table instance.
    /// Called when database connection attaches to schema.
    /// REQUIRED for all virtual tables.
    xConnect: ?XCreateFn = null,

    /// Determine the best index/query plan.
    /// Called during sqlite3_prepare() to optimize queries.
    /// REQUIRED for all virtual tables.
    xBestIndex: ?XBestIndexFn = null,

    /// Disconnect from a virtual table.
    /// Releases the connection but not the backing store.
    /// REQUIRED for all virtual tables.
    xDisconnect: ?XDisconnectFn = null,

    /// Destroy a virtual table and its backing store.
    /// Called for DROP TABLE statements.
    xDestroy: ?XDisconnectFn = null,

    /// Open a cursor for reading/writing.
    /// REQUIRED for all virtual tables.
    xOpen: ?XOpenFn = null,

    /// Close a cursor.
    /// REQUIRED for all virtual tables.
    xClose: ?XCloseFn = null,

    /// Begin a filtered scan.
    /// REQUIRED for all virtual tables.
    xFilter: ?XFilterFn = null,

    /// Advance cursor to next row.
    /// REQUIRED for all virtual tables.
    xNext: ?XNextFn = null,

    /// Check if cursor is at end of results.
    /// REQUIRED for all virtual tables.
    xEof: ?XEofFn = null,

    /// Get column value at current cursor position.
    /// REQUIRED for all virtual tables.
    xColumn: ?XColumnFn = null,

    /// Get rowid at current cursor position.
    /// REQUIRED for all virtual tables.
    xRowid: ?XRowidFn = null,

    // =========================================================================
    // Writable Virtual Table Methods
    // =========================================================================

    /// Handle INSERT, UPDATE, and DELETE operations.
    /// REQUIRED for writable virtual tables.
    /// Set to NULL for read-only virtual tables.
    xUpdate: ?XUpdateFn = null,

    // =========================================================================
    // Transaction Methods
    // =========================================================================

    /// Begin a transaction on this virtual table.
    /// If xBegin is NULL, xCommit will not be called.
    xBegin: ?XBeginFn = null,

    /// Two-phase commit sync.
    /// Called before xCommit on all vtabs in a transaction.
    xSync: ?XSyncFn = null,

    /// Commit a transaction.
    xCommit: ?XCommitFn = null,

    /// Rollback a transaction.
    xRollback: ?XRollbackFn = null,

    // =========================================================================
    // Optional Methods
    // =========================================================================

    /// Find overloaded function implementations.
    xFindFunction: ?XFindFunctionFn = null,

    /// Handle ALTER TABLE RENAME.
    xRename: ?XRenameFn = null,

    // =========================================================================
    // Version 2+ Methods (Savepoint support)
    // =========================================================================

    /// Create a savepoint.
    xSavepoint: ?XSavepointFn = null,

    /// Release a savepoint.
    xRelease: ?XReleaseFn = null,

    /// Rollback to a savepoint.
    xRollbackTo: ?XRollbackToFn = null,

    // =========================================================================
    // Version 3+ Methods
    // =========================================================================

    /// Check if a table name is a shadow table.
    /// Used for SQLITE_DBCONFIG_DEFENSIVE.
    xShadowName: ?XShadowNameFn = null,

    // =========================================================================
    // Version 4+ Methods (SQLite 3.44.0+)
    // =========================================================================

    /// Integrity check for PRAGMA integrity_check.
    xIntegrity: ?XIntegrityFn = null,
};

// =============================================================================
// Stub Implementations for Testing/Scaffolding
// =============================================================================

/// Stub xCreate/xConnect that declares a simple schema.
/// For testing purposes only - replace with actual implementation.
pub fn stubConnect(
    db: ?*sqlite3,
    pAux: ?*anyopaque,
    argc: c_int,
    argv: [*c]const [*c]const u8,
    ppVTab: [*c]?*VTab,
    pzErr: [*c][*c]u8,
) callconv(.c) c_int {
    _ = db;
    _ = pAux;
    _ = argc;
    _ = argv;
    _ = pzErr;

    log.debug("stubConnect called", .{});

    // In a real implementation:
    // 1. Allocate VTab (or subclass) via sqlite3_malloc
    // 2. Call sqlite3_declare_vtab(db, schema)
    // 3. Initialize any state
    // 4. Set *ppVTab to the new vtab

    ppVTab.* = null;
    return SQLITE_ERROR; // Stub - not fully implemented
}

/// Stub xBestIndex that returns a basic plan.
pub fn stubBestIndex(pVTab: ?*VTab, pIndexInfo: ?*IndexInfo) callconv(.c) c_int {
    _ = pVTab;

    log.debug("stubBestIndex called", .{});

    if (pIndexInfo) |info| {
        // Set a high cost to indicate this is a fallback plan
        info.estimatedCost = 1000000.0;
        info.estimatedRows = 1000;
    }

    return SQLITE_OK;
}

/// Stub xDisconnect that does nothing.
pub fn stubDisconnect(pVTab: ?*VTab) callconv(.c) c_int {
    _ = pVTab;
    log.debug("stubDisconnect called", .{});
    return SQLITE_OK;
}

/// Stub xOpen that creates a minimal cursor.
pub fn stubOpen(pVTab: ?*VTab, ppCursor: [*c]?*VTabCursor) callconv(.c) c_int {
    _ = pVTab;
    log.debug("stubOpen called", .{});

    // In a real implementation:
    // 1. Allocate cursor via sqlite3_malloc
    // 2. Initialize cursor state
    // 3. Set *ppCursor

    ppCursor.* = null;
    return SQLITE_ERROR; // Stub - not fully implemented
}

/// Stub xClose.
pub fn stubClose(pCursor: ?*VTabCursor) callconv(.c) c_int {
    _ = pCursor;
    log.debug("stubClose called", .{});
    return SQLITE_OK;
}

/// Stub xFilter.
pub fn stubFilter(
    pCursor: ?*VTabCursor,
    idxNum: c_int,
    idxStr: [*c]const u8,
    argc: c_int,
    argv: [*c]?*sqlite3_value,
) callconv(.c) c_int {
    _ = pCursor;
    _ = idxNum;
    _ = idxStr;
    _ = argc;
    _ = argv;
    log.debug("stubFilter called", .{});
    return SQLITE_OK;
}

/// Stub xNext.
pub fn stubNext(pCursor: ?*VTabCursor) callconv(.c) c_int {
    _ = pCursor;
    log.debug("stubNext called", .{});
    return SQLITE_OK;
}

/// Stub xEof - always returns true (no data).
pub fn stubEof(pCursor: ?*VTabCursor) callconv(.c) c_int {
    _ = pCursor;
    log.debug("stubEof called", .{});
    return 1; // Always at EOF
}

/// Stub xColumn.
pub fn stubColumn(
    pCursor: ?*VTabCursor,
    pCtx: ?*sqlite3_context,
    n: c_int,
) callconv(.c) c_int {
    _ = pCursor;
    _ = pCtx;
    log.debug("stubColumn called for column {}", .{n});
    return SQLITE_OK;
}

/// Stub xRowid.
pub fn stubRowid(pCursor: ?*VTabCursor, pRowid: *i64) callconv(.c) c_int {
    _ = pCursor;
    pRowid.* = 0;
    log.debug("stubRowid called", .{});
    return SQLITE_OK;
}

/// Stub xUpdate - logs the operation and returns OK.
/// This is a placeholder for the actual merge logic.
///
/// Operation types based on argc and argv[0]:
/// - argc == 1: DELETE (argv[0] is rowid to delete)
/// - argc > 1, argv[0] is NULL: INSERT
/// - argc > 1, argv[0] is not NULL: UPDATE
pub fn stubUpdate(
    pVTab: ?*VTab,
    argc: c_int,
    argv: [*c]?*sqlite3_value,
    pRowid: *i64,
) callconv(.c) c_int {
    _ = pVTab;
    _ = argv;

    log.debug("stubUpdate called with argc={}", .{argc});

    if (argc == 1) {
        log.debug("  -> DELETE operation", .{});
    } else if (argc > 1) {
        // argv[0] == NULL means INSERT, otherwise UPDATE
        log.debug("  -> INSERT or UPDATE operation", .{});
    }

    // For INSERT, we should set the generated rowid
    pRowid.* = 0;

    return SQLITE_OK;
}

/// Stub xBegin - start transaction.
pub fn stubBegin(pVTab: ?*VTab) callconv(.c) c_int {
    _ = pVTab;
    log.debug("stubBegin called - transaction started", .{});
    return SQLITE_OK;
}

/// Stub xSync - two-phase commit sync.
pub fn stubSync(pVTab: ?*VTab) callconv(.c) c_int {
    _ = pVTab;
    log.debug("stubSync called", .{});
    return SQLITE_OK;
}

/// Stub xCommit - commit transaction.
pub fn stubCommit(pVTab: ?*VTab) callconv(.c) c_int {
    _ = pVTab;
    log.debug("stubCommit called - transaction committed", .{});
    return SQLITE_OK;
}

/// Stub xRollback - rollback transaction.
pub fn stubRollback(pVTab: ?*VTab) callconv(.c) c_int {
    _ = pVTab;
    log.debug("stubRollback called - transaction rolled back", .{});
    return SQLITE_OK;
}

// =============================================================================
// Module Construction Helpers
// =============================================================================

/// Configuration for creating a writable virtual table module.
pub const WritableModuleConfig = struct {
    /// Module version (default 2 for savepoint support)
    version: c_int = 2,

    // Required callbacks
    xConnect: ?XCreateFn = null,
    xBestIndex: ?XBestIndexFn = null,
    xDisconnect: ?XDisconnectFn = null,
    xOpen: ?XOpenFn = null,
    xClose: ?XCloseFn = null,
    xFilter: ?XFilterFn = null,
    xNext: ?XNextFn = null,
    xEof: ?XEofFn = null,
    xColumn: ?XColumnFn = null,
    xRowid: ?XRowidFn = null,

    // Writable vtab callbacks
    xUpdate: ?XUpdateFn = null,

    // Optional callbacks
    xCreate: ?XCreateFn = null,
    xDestroy: ?XDisconnectFn = null,
    xBegin: ?XBeginFn = null,
    xSync: ?XSyncFn = null,
    xCommit: ?XCommitFn = null,
    xRollback: ?XRollbackFn = null,
    xFindFunction: ?XFindFunctionFn = null,
    xRename: ?XRenameFn = null,
    xSavepoint: ?XSavepointFn = null,
    xRelease: ?XReleaseFn = null,
    xRollbackTo: ?XRollbackToFn = null,
    xShadowName: ?XShadowNameFn = null,
    xIntegrity: ?XIntegrityFn = null,
};

/// Create a Module struct from a configuration.
pub fn createModule(config: WritableModuleConfig) Module {
    return .{
        .iVersion = config.version,
        .xCreate = config.xCreate,
        .xConnect = config.xConnect,
        .xBestIndex = config.xBestIndex,
        .xDisconnect = config.xDisconnect,
        .xDestroy = config.xDestroy,
        .xOpen = config.xOpen,
        .xClose = config.xClose,
        .xFilter = config.xFilter,
        .xNext = config.xNext,
        .xEof = config.xEof,
        .xColumn = config.xColumn,
        .xRowid = config.xRowid,
        .xUpdate = config.xUpdate,
        .xBegin = config.xBegin,
        .xSync = config.xSync,
        .xCommit = config.xCommit,
        .xRollback = config.xRollback,
        .xFindFunction = config.xFindFunction,
        .xRename = config.xRename,
        .xSavepoint = config.xSavepoint,
        .xRelease = config.xRelease,
        .xRollbackTo = config.xRollbackTo,
        .xShadowName = config.xShadowName,
        .xIntegrity = config.xIntegrity,
    };
}

/// Create a stub module for testing with all stubs wired up.
pub fn createStubModule() Module {
    return createModule(.{
        .version = 2,
        .xCreate = stubConnect,
        .xConnect = stubConnect,
        .xBestIndex = stubBestIndex,
        .xDisconnect = stubDisconnect,
        .xDestroy = stubDisconnect,
        .xOpen = stubOpen,
        .xClose = stubClose,
        .xFilter = stubFilter,
        .xNext = stubNext,
        .xEof = stubEof,
        .xColumn = stubColumn,
        .xRowid = stubRowid,
        .xUpdate = stubUpdate,
        .xBegin = stubBegin,
        .xSync = stubSync,
        .xCommit = stubCommit,
        .xRollback = stubRollback,
    });
}

// =============================================================================
// Tests
// =============================================================================

test "Module struct has correct size and layout" {
    // The Module struct should match SQLite's sqlite3_module layout.
    // Version 4 has: iVersion + 24 function pointers = 25 fields
    // - Version 0-1: xCreate through xRename (19 methods)
    // - Version 2: +xSavepoint, xRelease, xRollbackTo (3 methods)
    // - Version 3: +xShadowName (1 method)
    // - Version 4: +xIntegrity (1 method)
    const expected_field_count = 25;

    const info = @typeInfo(Module);
    try std.testing.expectEqual(expected_field_count, info.@"struct".fields.len);

    // Verify it's an extern struct (C ABI compatible)
    try std.testing.expect(info.@"struct".layout == .@"extern");
}

test "VTab struct has correct layout" {
    const info = @typeInfo(VTab);
    try std.testing.expect(info.@"struct".layout == .@"extern");
    try std.testing.expectEqual(@as(usize, 3), info.@"struct".fields.len);
}

test "VTabCursor struct has correct layout" {
    const info = @typeInfo(VTabCursor);
    try std.testing.expect(info.@"struct".layout == .@"extern");
    try std.testing.expectEqual(@as(usize, 1), info.@"struct".fields.len);
}

test "createStubModule produces valid module" {
    const module = createStubModule();

    try std.testing.expectEqual(@as(c_int, 2), module.iVersion);
    try std.testing.expect(module.xConnect != null);
    try std.testing.expect(module.xBestIndex != null);
    try std.testing.expect(module.xDisconnect != null);
    try std.testing.expect(module.xOpen != null);
    try std.testing.expect(module.xClose != null);
    try std.testing.expect(module.xFilter != null);
    try std.testing.expect(module.xNext != null);
    try std.testing.expect(module.xEof != null);
    try std.testing.expect(module.xColumn != null);
    try std.testing.expect(module.xRowid != null);
    try std.testing.expect(module.xUpdate != null);
    try std.testing.expect(module.xBegin != null);
    try std.testing.expect(module.xSync != null);
    try std.testing.expect(module.xCommit != null);
    try std.testing.expect(module.xRollback != null);
}

test "stub callbacks return expected values" {
    // Test stubBestIndex
    var index_info = std.mem.zeroes(IndexInfo);
    const best_index_result = stubBestIndex(null, &index_info);
    try std.testing.expectEqual(SQLITE_OK, best_index_result);

    // Test stubDisconnect
    try std.testing.expectEqual(SQLITE_OK, stubDisconnect(null));

    // Test stubEof returns 1 (at EOF)
    try std.testing.expectEqual(@as(c_int, 1), stubEof(null));

    // Test stubBegin
    try std.testing.expectEqual(SQLITE_OK, stubBegin(null));

    // Test stubCommit
    try std.testing.expectEqual(SQLITE_OK, stubCommit(null));

    // Test stubRollback
    try std.testing.expectEqual(SQLITE_OK, stubRollback(null));

    // Test stubUpdate
    var rowid: i64 = 0;
    try std.testing.expectEqual(SQLITE_OK, stubUpdate(null, 1, undefined, &rowid));
}

test "IndexInfo struct has expected fields" {
    const info = @typeInfo(IndexInfo);
    try std.testing.expect(info.@"struct".layout == .@"extern");

    // Check we have all the key fields using comptime iteration
    const has_nConstraint = comptime blk: {
        for (info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "nConstraint")) break :blk true;
        }
        break :blk false;
    };
    const has_estimatedCost = comptime blk: {
        for (info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "estimatedCost")) break :blk true;
        }
        break :blk false;
    };
    const has_colUsed = comptime blk: {
        for (info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "colUsed")) break :blk true;
        }
        break :blk false;
    };

    try std.testing.expect(has_nConstraint);
    try std.testing.expect(has_estimatedCost);
    try std.testing.expect(has_colUsed);
}
