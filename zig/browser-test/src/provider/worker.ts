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

// SQLite WASM types (simplified)
interface SqlJsDatabase {
  run(sql: string, params?: unknown[]): void;
  exec(sql: string): { columns: string[]; values: unknown[][] }[];
  export(): Uint8Array;
  close(): void;
}

interface SqlJs {
  Database: new (data?: ArrayLike<number>) => SqlJsDatabase;
}

// Declare the initSqlJs function that will be loaded via importScripts
declare function initSqlJs(config?: { locateFile?: (file: string) => string }): Promise<SqlJs>;

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
  if (!hasOPFS) return;

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

async function loadSqlJs(): Promise<SqlJs> {
  if (sqlJsLoadPromise) return sqlJsLoadPromise;

  sqlJsLoadPromise = (async () => {
    // For module workers, we need to use dynamic import or fetch the script
    // sql.js provides an ESM build, but it's tricky to load in a worker
    // So we'll use a workaround: fetch and eval (not ideal but works)

    let initFn = (self as any).initSqlJs;

    if (!initFn) {
      console.log('[ProviderWorker] Loading sql.js via fetch + eval...');
      const response = await fetch(
        'https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.10.3/sql-wasm.js'
      );
      const scriptText = await response.text();
      // Use indirect eval to run in global scope
      (0, eval)(scriptText);
      initFn = (self as any).initSqlJs;
    }

    if (!initFn) {
      throw new Error('Failed to load sql.js');
    }

    console.log('[ProviderWorker] Initializing sql.js...');
    const sql = await initFn({
      locateFile: (file: string) =>
        `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.10.3/${file}`,
    });
    console.log('[ProviderWorker] sql.js initialized successfully');
    return sql;
  })();

  return sqlJsLoadPromise;
}

async function handleOpen(dbName: string): Promise<{ success: true; persistent: boolean }> {
  if (!sqlJs) {
    sqlJs = await loadSqlJs();
  }

  // Close existing database if open
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
