/**
 * RPC Protocol Types for Multi-tab CR-SQLite Coordination
 *
 * These types define the message protocol between browser tabs and
 * the SharedWorker coordinator for database access.
 */

/** Unique identifier for tracking request/response pairs */
export type RequestId = string;

/** Client identifier for tab tracking */
export type ClientId = string;

/** Provider identifier (tab that owns the database connection) */
export type ProviderId = string;

// ============================================================================
// Request/Response Types
// ============================================================================

/** Open a database connection */
export interface OpenRequest {
  type: 'open';
  requestId: RequestId;
  payload: { dbName: string };
}

/** Close a database connection */
export interface CloseRequest {
  type: 'close';
  requestId: RequestId;
  payload: { dbName: string };
}

/** Execute SQL (INSERT, UPDATE, DELETE, DDL) */
export interface ExecRequest {
  type: 'exec';
  requestId: RequestId;
  payload: { sql: string; bind?: unknown[] };
}

/** Query SQL (SELECT) */
export interface QueryRequest {
  type: 'query';
  requestId: RequestId;
  payload: { sql: string; bind?: unknown[] };
}

/** Health check */
export interface PingRequest {
  type: 'ping';
  requestId: RequestId;
  payload: Record<string, never>;
}

/** Union of all RPC request types */
export type RpcRequest =
  | OpenRequest
  | CloseRequest
  | ExecRequest
  | QueryRequest
  | PingRequest;

/** Successful response */
export interface ResultResponse {
  type: 'result';
  requestId: RequestId;
  payload: { result: unknown };
}

/** Error response */
export interface ErrorResponse {
  type: 'error';
  requestId: RequestId;
  payload: { code: string; message: string };
}

/** Union of all RPC response types */
export type RpcResponse = ResultResponse | ErrorResponse;

// ============================================================================
// Coordinator Message Types
// ============================================================================

/** New client (tab) connected to coordinator */
export interface ClientConnectMessage {
  type: 'client-connect';
  clientId: ClientId;
}

/** Client (tab) disconnected from coordinator */
export interface ClientDisconnectMessage {
  type: 'client-disconnect';
  clientId: ClientId;
}

/** Provider election completed - this tab owns the database */
export interface ProviderElectedMessage {
  type: 'provider-elected';
  providerId: ProviderId;
}

/** Forward a request from client to provider */
export interface ForwardRequestMessage {
  type: 'forward-request';
  clientId: ClientId;
  request: RpcRequest;
}

/** Forward a response from provider to client */
export interface ForwardResponseMessage {
  type: 'forward-response';
  clientId: ClientId;
  response: RpcResponse;
}

/** Union of all coordinator message types */
export type CoordinatorMessage =
  | ClientConnectMessage
  | ClientDisconnectMessage
  | ProviderElectedMessage
  | ForwardRequestMessage
  | ForwardResponseMessage;

// ============================================================================
// Utility Types
// ============================================================================

/** Extract request type string literals */
export type RpcRequestType = RpcRequest['type'];

/** Extract response type string literals */
export type RpcResponseType = RpcResponse['type'];

/** Extract coordinator message type string literals */
export type CoordinatorMessageType = CoordinatorMessage['type'];

/** Helper to create a typed request */
export function createRequest<T extends RpcRequest['type']>(
  type: T,
  requestId: RequestId,
  payload: Extract<RpcRequest, { type: T }>['payload']
): Extract<RpcRequest, { type: T }> {
  return { type, requestId, payload } as Extract<RpcRequest, { type: T }>;
}

/** Helper to create a result response */
export function createResultResponse(
  requestId: RequestId,
  result: unknown
): ResultResponse {
  return { type: 'result', requestId, payload: { result } };
}

/** Helper to create an error response */
export function createErrorResponse(
  requestId: RequestId,
  code: string,
  message: string
): ErrorResponse {
  return { type: 'error', requestId, payload: { code, message } };
}
