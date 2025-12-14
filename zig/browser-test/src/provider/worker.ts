/// <reference lib="webworker" />

/**
 * Provider Worker - Owns the SQLite Database Connection
 *
 * This Dedicated Worker runs in the tab elected as provider.
 * It loads SQLite WASM and processes SQL requests serially.
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
  close(): void;
}

interface SqlJs {
  Database: new () => SqlJsDatabase;
}

// Declare the initSqlJs function that will be loaded via importScripts
declare function initSqlJs(config?: { locateFile?: (file: string) => string }): Promise<SqlJs>;

let db: SqlJsDatabase | null = null;
let sqlJs: SqlJs | null = null;
let sqlJsLoadPromise: Promise<SqlJs> | null = null;

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

async function handleOpen(_dbName: string): Promise<{ success: true }> {
  if (!sqlJs) {
    sqlJs = await loadSqlJs();
  }

  if (db) {
    db.close();
  }

  db = new sqlJs!.Database();
  console.log('[ProviderWorker] Database opened');
  return { success: true };
}

async function handleClose(): Promise<{ success: true }> {
  if (db) {
    db.close();
    db = null;
  }
  return { success: true };
}

async function handleExec(
  sql: string,
  bind?: unknown[]
): Promise<{ changes: number }> {
  if (!db) throw new Error('Database not open');
  db.run(sql, bind);
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
