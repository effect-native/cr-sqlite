/**
 * Shared types and constants for multi-tab CR-SQLite coordination
 *
 * @example
 * ```typescript
 * import { RpcRequest, RpcResponse, PROVIDER_LOCK } from './shared';
 * ```
 */

// Re-export all types
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
} from './rpc-types';

// Re-export helper functions
export {
  createRequest,
  createResultResponse,
  createErrorResponse,
} from './rpc-types';

// Re-export all constants
export {
  LOCK_PREFIX,
  PROVIDER_LOCK,
  CLIENT_LOCK,
  SHARED_WORKER_PATH,
  DEFAULT_DB_NAME,
  RPC_TIMEOUT_MS,
  HEARTBEAT_INTERVAL_MS,
} from './constants';
