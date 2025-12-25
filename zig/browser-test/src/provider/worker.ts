/// <reference lib="webworker" />

/**
 * Provider Worker - Owns the SQLite Database Connection
 *
 * This Dedicated Worker runs in the tab elected as provider.
 * It loads SQLite WASM and processes SQL requests serially.
 * 
 * Storage Strategy:
 * - Uses OPFS (Origin Private File System) for persistent storage when available
 * - Falls back to in-memory storage when OPFS is unavailable
 * - Database is persisted to OPFS after each write operation
 */

import {
  RpcRequest,
  RpcResponse,
  createResultResponse,
  createErrorResponse,
} from '../shared/rpc-types';

console.log('[ProviderWorker] Starting...');

// SQLite WASM types (simplified sql.js-compatible interface)
interface SqlJsDatabase {
  run(sql: string, params?: unknown[]): void;
  exec(sql: string): { columns: string[]; values: unknown[][] }[];
  export(): Uint8Array;
  close(): void;
}

interface SqlJs {
  Database: new (data?: ArrayLike<number>) => SqlJsDatabase;
}

// Emscripten module interface (raw C API)
interface EmscriptenModule {
  _malloc(size: number): number;
  _free(ptr: number): void;
  getValue(ptr: number, type: string): number;
  setValue(ptr: number, value: number, type: string): void;
  UTF8ToString(ptr: number): string;
  stringToUTF8(str: string, ptr: number, maxLen: number): void;
  lengthBytesUTF8(str: string): number;
  HEAPU8: Uint8Array;
  
  // SQLite C API exports
  _sqlite3_open(filename: number, ppDb: number): number;
  _sqlite3_close_v2(db: number): number;
  _sqlite3_prepare_v2(db: number, sql: number, nByte: number, ppStmt: number, pzTail: number): number;
  _sqlite3_step(stmt: number): number;
  _sqlite3_finalize(stmt: number): number;
  _sqlite3_reset(stmt: number): number;
  _sqlite3_column_count(stmt: number): number;
  _sqlite3_column_name(stmt: number, N: number): number;
  _sqlite3_column_type(stmt: number, N: number): number;
  _sqlite3_column_int(stmt: number, N: number): number;
  _sqlite3_column_double(stmt: number, N: number): number;
  _sqlite3_column_text(stmt: number, N: number): number;
  _sqlite3_column_blob(stmt: number, N: number): number;
  _sqlite3_column_bytes(stmt: number, N: number): number;
  _sqlite3_errmsg(db: number): number;
  _sqlite3_bind_int(stmt: number, idx: number, value: number): number;
  _sqlite3_bind_double(stmt: number, idx: number, value: number): number;
  _sqlite3_bind_text(stmt: number, idx: number, value: number, nBytes: number, destructor: number): number;
  _sqlite3_bind_blob(stmt: number, idx: number, value: number, nBytes: number, destructor: number): number;
  _sqlite3_bind_null(stmt: number, idx: number): number;
  _sqlite3_serialize(db: number, schema: number, pSize: number, flags: number): number;
  _sqlite3_deserialize(db: number, schema: number, data: number, size: bigint, bufSize: bigint, flags: number): number;
}

// Declare the initCrSqlite function that will be loaded from local sql-wasm.js
declare function initCrSqlite(config?: { locateFile?: (file: string) => string }): Promise<EmscriptenModule>;

// SQLite constants
const SQLITE_OK = 0;
const SQLITE_ROW = 100;
const SQLITE_DONE = 101;
const SQLITE_INTEGER = 1;
const SQLITE_FLOAT = 2;
const SQLITE_TEXT = 3;
const SQLITE_BLOB = 4;
const SQLITE_NULL = 5;
const SQLITE_TRANSIENT = -1;

/**
 * sql.js-compatible Database wrapper around raw Emscripten SQLite module.
 * Provides the same API as sql.js Database class.
 */
class CrSqliteDatabase implements SqlJsDatabase {
  private mod: EmscriptenModule;
  private dbPtr: number;
  
  constructor(mod: EmscriptenModule, data?: ArrayLike<number>) {
    this.mod = mod;
    
    // Allocate pointer for db handle
    const ppDb = mod._malloc(4);
    
    // Open in-memory database
    const filenamePtr = mod._malloc(9);
    mod.stringToUTF8(':memory:', filenamePtr, 9);
    const rc = mod._sqlite3_open(filenamePtr, ppDb);
    mod._free(filenamePtr);
    
    if (rc !== SQLITE_OK) {
      mod._free(ppDb);
      throw new Error(`Failed to open database: rc=${rc}`);
    }
    
    this.dbPtr = mod.getValue(ppDb, 'i32');
    mod._free(ppDb);
    
    // If initial data provided, deserialize it
    if (data && data.length > 0) {
      this.deserialize(data);
    }
  }
  
  private deserialize(data: ArrayLike<number>): void {
    const { mod, dbPtr } = this;
    
    console.log('[CrSqliteDatabase.deserialize] Deserializing', data.length, 'bytes');
    
    // Allocate buffer in WASM memory
    const size = data.length;
    const dataPtr = mod._malloc(size);
    
    // Copy data to WASM memory
    for (let i = 0; i < size; i++) {
      mod.HEAPU8[dataPtr + i] = data[i];
    }
    
    // Schema name "main"
    const schemaPtr = mod._malloc(5);
    mod.stringToUTF8('main', schemaPtr, 5);
    
    // SQLITE_DESERIALIZE_FREEONCLOSE = 1, SQLITE_DESERIALIZE_RESIZEABLE = 2
    const flags = 1 | 2;
    // sqlite3_deserialize expects sqlite3_int64 (BigInt) for size parameters
    const rc = mod._sqlite3_deserialize(dbPtr, schemaPtr, dataPtr, BigInt(size), BigInt(size), flags);
    mod._free(schemaPtr);
    
    if (rc !== SQLITE_OK) {
      mod._free(dataPtr);
      console.error('[CrSqliteDatabase.deserialize] Failed with rc:', rc);
      throw new Error(`Failed to deserialize database: rc=${rc}`);
    }
    console.log('[CrSqliteDatabase.deserialize] Successfully deserialized');
    // Note: dataPtr is freed by SQLite due to FREEONCLOSE flag
  }
  
  run(sql: string, params?: unknown[]): void {
    this.execInternal(sql, params, false);
  }
  
  exec(sql: string): { columns: string[]; values: unknown[][] }[] {
    return this.execInternal(sql, undefined, true);
  }
  
  private execInternal(sql: string, params: unknown[] | undefined, returnResults: boolean): { columns: string[]; values: unknown[][] }[] {
    const { mod, dbPtr } = this;
    const results: { columns: string[]; values: unknown[][] }[] = [];
    
    // Allocate SQL string
    const sqlLen = mod.lengthBytesUTF8(sql) + 1;
    const sqlPtr = mod._malloc(sqlLen);
    mod.stringToUTF8(sql, sqlPtr, sqlLen);
    
    // Allocate statement and tail pointers
    const ppStmt = mod._malloc(4);
    const pzTail = mod._malloc(4);
    
    let currentSqlPtr = sqlPtr;
    
    try {
      // Process all statements in the SQL string
      while (true) {
        const rc = mod._sqlite3_prepare_v2(dbPtr, currentSqlPtr, -1, ppStmt, pzTail);
        
        if (rc !== SQLITE_OK) {
          const errMsg = mod.UTF8ToString(mod._sqlite3_errmsg(dbPtr));
          throw new Error(`SQLite prepare error: ${errMsg}`);
        }
        
        const stmtPtr = mod.getValue(ppStmt, 'i32');
        
        if (stmtPtr === 0) {
          // No more statements
          break;
        }
        
        try {
          // Bind parameters if provided (only for first statement)
          if (params && results.length === 0) {
            this.bindParams(stmtPtr, params);
          }
          
          // Get column info
          const colCount = mod._sqlite3_column_count(stmtPtr);
          const columns: string[] = [];
          
          if (returnResults && colCount > 0) {
            for (let i = 0; i < colCount; i++) {
              const namePtr = mod._sqlite3_column_name(stmtPtr, i);
              columns.push(namePtr ? mod.UTF8ToString(namePtr) : `col${i}`);
            }
          }
          
          const values: unknown[][] = [];
          
          // Execute and fetch rows
          let stepRc: number;
          while ((stepRc = mod._sqlite3_step(stmtPtr)) === SQLITE_ROW) {
            if (returnResults && colCount > 0) {
              const row: unknown[] = [];
              for (let i = 0; i < colCount; i++) {
                row.push(this.getColumnValue(stmtPtr, i));
              }
              values.push(row);
            }
          }
          
          if (stepRc !== SQLITE_DONE) {
            const errMsg = mod.UTF8ToString(mod._sqlite3_errmsg(dbPtr));
            throw new Error(`SQLite step error: ${errMsg}`);
          }
          
          if (returnResults && colCount > 0) {
            results.push({ columns, values });
          }
        } finally {
          mod._sqlite3_finalize(stmtPtr);
        }
        
        // Move to next statement
        const tailPtr = mod.getValue(pzTail, 'i32');
        if (tailPtr === 0 || tailPtr === currentSqlPtr) {
          break;
        }
        
        // Check if remaining SQL is just whitespace
        const remaining = mod.UTF8ToString(tailPtr).trim();
        if (!remaining) {
          break;
        }
        
        currentSqlPtr = tailPtr;
      }
    } finally {
      mod._free(sqlPtr);
      mod._free(ppStmt);
      mod._free(pzTail);
    }
    
    return results;
  }
  
  private bindParams(stmtPtr: number, params: unknown[]): void {
    const { mod } = this;
    
    for (let i = 0; i < params.length; i++) {
      const param = params[i];
      const idx = i + 1; // SQLite bind indices are 1-based
      let rc: number;
      
      if (param === null || param === undefined) {
        rc = mod._sqlite3_bind_null(stmtPtr, idx);
      } else if (typeof param === 'number') {
        if (Number.isInteger(param)) {
          rc = mod._sqlite3_bind_int(stmtPtr, idx, param);
        } else {
          rc = mod._sqlite3_bind_double(stmtPtr, idx, param);
        }
      } else if (typeof param === 'string') {
        const len = mod.lengthBytesUTF8(param);
        const ptr = mod._malloc(len + 1);
        mod.stringToUTF8(param, ptr, len + 1);
        rc = mod._sqlite3_bind_text(stmtPtr, idx, ptr, len, SQLITE_TRANSIENT);
        mod._free(ptr);
      } else if (param instanceof Uint8Array || param instanceof ArrayBuffer) {
        const bytes = param instanceof ArrayBuffer ? new Uint8Array(param) : param;
        const ptr = mod._malloc(bytes.length);
        mod.HEAPU8.set(bytes, ptr);
        rc = mod._sqlite3_bind_blob(stmtPtr, idx, ptr, bytes.length, SQLITE_TRANSIENT);
        mod._free(ptr);
      } else {
        // Convert to string
        const str = String(param);
        const len = mod.lengthBytesUTF8(str);
        const ptr = mod._malloc(len + 1);
        mod.stringToUTF8(str, ptr, len + 1);
        rc = mod._sqlite3_bind_text(stmtPtr, idx, ptr, len, SQLITE_TRANSIENT);
        mod._free(ptr);
      }
      
      if (rc !== SQLITE_OK) {
        throw new Error(`Failed to bind parameter ${idx}: rc=${rc}`);
      }
    }
  }
  
  private getColumnValue(stmtPtr: number, colIdx: number): unknown {
    const { mod } = this;
    const type = mod._sqlite3_column_type(stmtPtr, colIdx);
    
    switch (type) {
      case SQLITE_INTEGER:
        return mod._sqlite3_column_int(stmtPtr, colIdx);
      case SQLITE_FLOAT:
        return mod._sqlite3_column_double(stmtPtr, colIdx);
      case SQLITE_TEXT: {
        const ptr = mod._sqlite3_column_text(stmtPtr, colIdx);
        return ptr ? mod.UTF8ToString(ptr) : null;
      }
      case SQLITE_BLOB: {
        const ptr = mod._sqlite3_column_blob(stmtPtr, colIdx);
        const size = mod._sqlite3_column_bytes(stmtPtr, colIdx);
        if (ptr && size > 0) {
          return new Uint8Array(mod.HEAPU8.buffer, ptr, size).slice();
        }
        return null;
      }
      case SQLITE_NULL:
      default:
        return null;
    }
  }
  
  export(): Uint8Array {
    const { mod, dbPtr } = this;
    
    // Schema name "main"
    const schemaPtr = mod._malloc(5);
    mod.stringToUTF8('main', schemaPtr, 5);
    
    // Allocate size output pointer (sqlite3_int64 = 8 bytes)
    const pSize = mod._malloc(8);
    // Initialize to 0
    mod.setValue(pSize, 0, 'i32');
    mod.setValue(pSize + 4, 0, 'i32');
    
    // Serialize with no special flags
    const dataPtr = mod._sqlite3_serialize(dbPtr, schemaPtr, pSize, 0);
    mod._free(schemaPtr);
    
    if (dataPtr === 0) {
      mod._free(pSize);
      console.log('[CrSqliteDatabase.export] sqlite3_serialize returned null, database may be empty');
      // Return empty database header for empty databases
      return new Uint8Array(0);
    }
    
    // Read size as two 32-bit parts (little-endian on most platforms)
    const sizeLow = mod.getValue(pSize, 'i32');
    const sizeHigh = mod.getValue(pSize + 4, 'i32');
    mod._free(pSize);
    
    // For practical purposes, databases > 2GB are unlikely in browser
    const size = sizeLow; // Ignore high bits for now
    console.log('[CrSqliteDatabase.export] Serialized', size, 'bytes');
    
    if (size <= 0) {
      console.log('[CrSqliteDatabase.export] Invalid size, returning empty');
      mod._free(dataPtr);
      return new Uint8Array(0);
    }
    
    // Copy data out
    const result = new Uint8Array(size);
    result.set(new Uint8Array(mod.HEAPU8.buffer, dataPtr, size));
    
    // Free serialized data (allocated by sqlite3_serialize)
    mod._free(dataPtr);
    
    return result;
  }
  
  close(): void {
    const { mod, dbPtr } = this;
    if (dbPtr) {
      mod._sqlite3_close_v2(dbPtr);
      this.dbPtr = 0;
    }
  }
}

/**
 * Create a sql.js-compatible wrapper around the raw Emscripten module.
 */
function createSqlJsWrapper(mod: EmscriptenModule): SqlJs {
  return {
    Database: class Database implements SqlJsDatabase {
      private impl: CrSqliteDatabase;
      
      constructor(data?: ArrayLike<number>) {
        this.impl = new CrSqliteDatabase(mod, data);
      }
      
      run(sql: string, params?: unknown[]): void {
        this.impl.run(sql, params);
      }
      
      exec(sql: string): { columns: string[]; values: unknown[][] }[] {
        return this.impl.exec(sql);
      }
      
      export(): Uint8Array {
        return this.impl.export();
      }
      
      close(): void {
        this.impl.close();
      }
    }
  };
}

let db: SqlJsDatabase | null = null;
let sqlJs: SqlJs | null = null;
let sqlJsLoadPromise: Promise<SqlJs> | null = null;

// OPFS state
let currentDbName: string | null = null;
let opfsFileHandle: FileSystemFileHandle | null = null;
let useOPFS = false;

// Check for OPFS support in this worker context
function checkOPFSSupport(): boolean {
  try {
    return (
      typeof navigator !== 'undefined' &&
      'storage' in navigator &&
      typeof navigator.storage.getDirectory === 'function'
    );
  } catch {
    return false;
  }
}

const hasOPFS = checkOPFSSupport();
console.log('[ProviderWorker] OPFS support:', hasOPFS);

/**
 * Load database data from OPFS file.
 * Returns the database bytes if file exists and has content, null otherwise.
 */
async function loadFromOPFS(dbName: string): Promise<Uint8Array | null> {
  if (!hasOPFS) return null;

  try {
    const root = await navigator.storage.getDirectory();
    const fileName = `${dbName}.sqlite3`;
    
    // Try to get existing file
    try {
      const fileHandle = await root.getFileHandle(fileName, { create: false });
      const file = await fileHandle.getFile();
      
      if (file.size === 0) {
        console.log('[ProviderWorker] OPFS file exists but is empty');
        return null;
      }
      
      const buffer = await file.arrayBuffer();
      console.log(`[ProviderWorker] Loaded ${buffer.byteLength} bytes from OPFS`);
      return new Uint8Array(buffer);
    } catch (e) {
      // File doesn't exist yet
      if (e instanceof DOMException && e.name === 'NotFoundError') {
        console.log('[ProviderWorker] No existing OPFS file found');
        return null;
      }
      throw e;
    }
  } catch (e) {
    console.error('[ProviderWorker] Error loading from OPFS:', e);
    return null;
  }
}

/**
 * Save database data to OPFS file.
 */
async function saveToOPFS(dbName: string, data: Uint8Array): Promise<void> {
  if (!hasOPFS) {
    console.log('[ProviderWorker] OPFS not available, skipping save');
    return;
  }

  if (!data || data.byteLength === 0) {
    console.warn('[ProviderWorker] Refusing to save empty database to OPFS');
    return;
  }

  try {
    const root = await navigator.storage.getDirectory();
    const fileName = `${dbName}.sqlite3`;
    const fileHandle = await root.getFileHandle(fileName, { create: true });
    
    // Use createWritable for atomic writes
    const writable = await fileHandle.createWritable();
    // Cast to Blob to satisfy TypeScript's strict ArrayBufferLike checking
    await writable.write(new Blob([data as unknown as BlobPart]));
    await writable.close();
    
    console.log(`[ProviderWorker] Saved ${data.byteLength} bytes to OPFS`);
  } catch (e) {
    console.error('[ProviderWorker] Error saving to OPFS:', e);
    // Don't throw - this is a best-effort persistence
  }
}

/**
 * Get or create the OPFS file handle for the current database.
 */
async function getOPFSFileHandle(dbName: string): Promise<FileSystemFileHandle | null> {
  if (!hasOPFS) return null;

  try {
    const root = await navigator.storage.getDirectory();
    const fileName = `${dbName}.sqlite3`;
    return await root.getFileHandle(fileName, { create: true });
  } catch (e) {
    console.error('[ProviderWorker] Error getting OPFS file handle:', e);
    return null;
  }
}

// Request queue for serial execution
const requestQueue: Array<{
  request: RpcRequest;
  resolve: (r: RpcResponse) => void;
}> = [];
let processing = false;

self.onmessage = async (event: MessageEvent<RpcRequest>) => {
  console.log('[ProviderWorker] Received request:', event.data?.type);
  const request = event.data;

  const response = await enqueueRequest(request);
  console.log('[ProviderWorker] Sending response:', response.type);
  self.postMessage(response);
};

async function enqueueRequest(request: RpcRequest): Promise<RpcResponse> {
  return new Promise((resolve) => {
    requestQueue.push({ request, resolve });
    processQueue();
  });
}

async function processQueue() {
  if (processing || requestQueue.length === 0) return;
  processing = true;

  while (requestQueue.length > 0) {
    const { request, resolve } = requestQueue.shift()!;
    try {
      const result = await handleRequest(request);
      resolve(createResultResponse(request.requestId, result));
    } catch (e) {
      resolve(
        createErrorResponse(
          request.requestId,
          'QUERY_ERROR',
          e instanceof Error ? e.message : String(e)
        )
      );
    }
  }

  processing = false;
}

async function handleRequest(request: RpcRequest): Promise<unknown> {
  switch (request.type) {
    case 'open':
      return handleOpen(request.payload.dbName);
    case 'close':
      return handleClose();
    case 'exec':
      return handleExec(request.payload.sql, request.payload.bind);
    case 'query':
      return handleQuery(request.payload.sql, request.payload.bind);
    case 'ping':
      return { pong: true, timestamp: Date.now() };
    default:
      throw new Error(`Unknown request type: ${(request as any).type}`);
  }
}

/**
 * Resolve a sibling file URL relative to this worker's location.
 * The worker is loaded from e.g. /fixtures/provider.js, so sibling files
 * like sql-wasm.js and sql-wasm.wasm are in the same directory.
 */
function resolveSiblingUrl(filename: string): string {
  // self.location.href gives us the full URL of this worker script
  const workerUrl = self.location.href;
  // Replace the last path segment with the sibling filename
  const baseUrl = workerUrl.substring(0, workerUrl.lastIndexOf('/') + 1);
  return baseUrl + filename;
}

async function loadSqlJs(): Promise<SqlJs> {
  if (sqlJsLoadPromise) return sqlJsLoadPromise;

  sqlJsLoadPromise = (async () => {
    // Load our bundled CR-SQLite WASM (not vanilla sql.js from CDN)
    // The sql-wasm.js file exports initCrSqlite function

    let initFn = (self as any).initCrSqlite;

    if (!initFn) {
      const sqlWasmUrl = resolveSiblingUrl('sql-wasm.js');
      console.log('[ProviderWorker] Loading CR-SQLite WASM from:', sqlWasmUrl);
      const response = await fetch(sqlWasmUrl);
      if (!response.ok) {
        throw new Error(`Failed to fetch sql-wasm.js: ${response.status} ${response.statusText}`);
      }
      const scriptText = await response.text();
      // Use indirect eval to run in global scope
      (0, eval)(scriptText);
      initFn = (self as any).initCrSqlite;
    }

    if (!initFn) {
      throw new Error('Failed to load CR-SQLite WASM (initCrSqlite not found)');
    }

    console.log('[ProviderWorker] Initializing CR-SQLite...');
    const mod = await initFn({
      // Locate the .wasm file relative to this worker
      locateFile: (file: string) => resolveSiblingUrl(file),
    });
    console.log('[ProviderWorker] CR-SQLite module loaded, creating sql.js-compatible wrapper...');
    
    // Wrap the raw Emscripten module in a sql.js-compatible interface
    const sqlJsWrapper = createSqlJsWrapper(mod);
    console.log('[ProviderWorker] CR-SQLite initialized successfully');
    return sqlJsWrapper;
  })();

  return sqlJsLoadPromise;
}

async function handleOpen(dbName: string): Promise<{ success: true; persistent: boolean }> {
  if (!sqlJs) {
    sqlJs = await loadSqlJs();
  }

  // If database is already open with the same name, just return success
  // This handles the case where multiple tabs call open() - we don't want to
  // reload from OPFS and lose in-memory changes
  if (db && currentDbName === dbName) {
    console.log('[ProviderWorker] Database already open:', dbName);
    return { success: true, persistent: useOPFS };
  }

  // Close existing database if switching to a different name
  if (db) {
    // Save current database before closing
    if (useOPFS && currentDbName) {
      try {
        const data = db.export();
        await saveToOPFS(currentDbName, data);
      } catch (e) {
        console.error('[ProviderWorker] Error saving before close:', e);
      }
    }
    db.close();
    db = null;
  }

  currentDbName = dbName;
  useOPFS = false;
  opfsFileHandle = null;

  // Try to load existing database from OPFS
  const existingData = await loadFromOPFS(dbName);
  
  if (existingData) {
    try {
      db = new sqlJs!.Database(existingData);
      useOPFS = true;
      opfsFileHandle = await getOPFSFileHandle(dbName);
      console.log('[ProviderWorker] Database opened from OPFS (persistent)');
      return { success: true, persistent: true };
    } catch (e) {
      console.error('[ProviderWorker] Error opening database from OPFS data:', e);
      // Fall through to create new database
    }
  }

  // Create new database
  db = new sqlJs!.Database();
  
  // Try to set up OPFS persistence for new database
  if (hasOPFS) {
    opfsFileHandle = await getOPFSFileHandle(dbName);
    if (opfsFileHandle) {
      useOPFS = true;
      // Save initial empty database to OPFS
      try {
        const data = db.export();
        await saveToOPFS(dbName, data);
      } catch (e) {
        console.error('[ProviderWorker] Error saving initial database:', e);
        useOPFS = false;
        opfsFileHandle = null;
      }
    }
  }

  console.log(`[ProviderWorker] Database opened (${useOPFS ? 'persistent' : 'in-memory'})`);
  return { success: true, persistent: useOPFS };
}

async function handleClose(): Promise<{ success: true }> {
  if (db) {
    // Save to OPFS before closing
    if (useOPFS && currentDbName) {
      try {
        const data = db.export();
        await saveToOPFS(currentDbName, data);
        console.log('[ProviderWorker] Database saved to OPFS before close');
      } catch (e) {
        console.error('[ProviderWorker] Error saving before close:', e);
      }
    }
    db.close();
    db = null;
  }
  
  // Reset OPFS state
  currentDbName = null;
  useOPFS = false;
  opfsFileHandle = null;
  
  return { success: true };
}

async function handleExec(
  sql: string,
  bind?: unknown[]
): Promise<{ changes: number }> {
  if (!db) throw new Error('Database not open');
  db.run(sql, bind);
  
  // Persist to OPFS after write operations
  // We check if this looks like a write operation to avoid unnecessary saves
  const sqlUpper = sql.trim().toUpperCase();
  const isWrite = sqlUpper.startsWith('INSERT') ||
                  sqlUpper.startsWith('UPDATE') ||
                  sqlUpper.startsWith('DELETE') ||
                  sqlUpper.startsWith('CREATE') ||
                  sqlUpper.startsWith('DROP') ||
                  sqlUpper.startsWith('ALTER');
  
  if (isWrite && useOPFS && currentDbName) {
    try {
      const data = db.export();
      await saveToOPFS(currentDbName, data);
    } catch (e) {
      console.error('[ProviderWorker] Error persisting after exec:', e);
      // Don't throw - query succeeded, persistence is best-effort
    }
  }
  
  return { changes: 0 }; // sql.js doesn't expose changes count easily
}

async function handleQuery(
  sql: string,
  _bind?: unknown[]
): Promise<{ rows: unknown[][] }> {
  if (!db) throw new Error('Database not open');
  // Note: sql.js exec() doesn't support bind params directly;
  // would need to use prepare() for parameterized queries
  const results = db.exec(sql);
  if (results.length === 0) return { rows: [] };
  return { rows: results[0].values };
}

export { db, requestQueue };
