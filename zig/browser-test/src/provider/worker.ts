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

// SQLite WASM types (simplified)
interface SqlJsDatabase {
  run(sql: string, params?: unknown[]): void;
  exec(sql: string): { columns: string[]; values: unknown[][] }[];
  close(): void;
}

interface SqlJs {
  Database: new () => SqlJsDatabase;
}

let db: SqlJsDatabase | null = null;
let sqlJs: SqlJs | null = null;

// Request queue for serial execution
const requestQueue: Array<{
  request: RpcRequest;
  resolve: (r: RpcResponse) => void;
}> = [];
let processing = false;

self.onmessage = async (event: MessageEvent<RpcRequest>) => {
  const request = event.data;

  const response = await enqueueRequest(request);
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

async function handleOpen(_dbName: string): Promise<{ success: true }> {
  if (!sqlJs) {
    // Load sql.js - assumes initSqlJs is available globally via script tag
    const initSqlJs = (self as any).initSqlJs;
    if (!initSqlJs) {
      throw new Error('sql.js not loaded');
    }
    sqlJs = await initSqlJs();
  }

  if (db) {
    db.close();
  }

  db = new sqlJs!.Database();
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
