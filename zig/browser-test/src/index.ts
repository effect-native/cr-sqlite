/**
 * CR-SQLite Browser Multi-tab Coordination
 *
 * This module provides the infrastructure for coordinating SQLite database
 * access across multiple browser tabs using SharedWorker and Web Locks API.
 *
 * @example
 * ```typescript
 * import { createDbClient, DbClient } from 'cr-sqlite-browser';
 *
 * const client = createDbClient({ dbName: 'mydb' });
 * await client.ready;
 *
 * // Execute SQL
 * await client.exec('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)');
 *
 * // Query data
 * const rows = await client.query('SELECT * FROM users');
 * ```
 */

// Re-export shared types and constants
export type {
  RequestId,
  ClientId,
  ProviderId,
  OpenRequest,
  CloseRequest,
  ExecRequest,
  QueryRequest,
  PingRequest,
  RpcRequest,
  ResultResponse,
  ErrorResponse,
  RpcResponse,
  ClientConnectMessage,
  ClientDisconnectMessage,
  ProviderElectedMessage,
  ForwardRequestMessage,
  ForwardResponseMessage,
  CoordinatorMessage,
  RpcRequestType,
  RpcResponseType,
  CoordinatorMessageType,
} from './shared';

export {
  createRequest,
  createResultResponse,
  createErrorResponse,
  LOCK_PREFIX,
  PROVIDER_LOCK,
  CLIENT_LOCK,
  SHARED_WORKER_PATH,
  DEFAULT_DB_NAME,
  RPC_TIMEOUT_MS,
  HEARTBEAT_INTERVAL_MS,
} from './shared';

// Re-export client module
export { DbClient, createDbClient } from './client';
export type { DbClientOptions } from './client';
