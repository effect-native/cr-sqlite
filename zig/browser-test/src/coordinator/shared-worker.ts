/// <reference lib="webworker" />

/**
 * SharedWorker Coordinator for Multi-tab Database Access
 *
 * This SharedWorker routes database requests between browser tabs:
 * 1. Accepts connections from multiple tabs
 * 2. Elects one tab as the "provider" (database owner) using Web Locks
 * 3. Routes requests from client tabs to the provider
 * 4. Handles provider failover when a tab closes
 */

import type {
  ClientId,
  ProviderId,
  RpcRequest,
  ForwardRequestMessage,
  ForwardResponseMessage,
} from '../shared/rpc-types';
import { PROVIDER_LOCK, DEFAULT_DB_NAME } from '../shared/constants';

// Declare SharedWorkerGlobalScope types
declare const self: SharedWorkerGlobalScope;

/** Represents a connected client (browser tab) */
interface ClientConnection {
  port: MessagePort;
  clientId: ClientId;
  isProvider: boolean;
}

/** Message sent to client on initial connection */
interface ConnectedMessage {
  type: 'connected';
  clientId: ClientId;
}

/** Message sent to all clients when provider is elected */
interface ProviderElectedNotification {
  type: 'provider-elected';
  providerId: ProviderId;
  isYou: boolean;
}

/** Error message sent when no provider available */
interface NoProviderError {
  type: 'error';
  requestId: string;
  payload: { code: string; message: string };
}

/** All connected clients indexed by their ID */
const clients = new Map<ClientId, ClientConnection>();

/** Current provider tab ID (null if no provider elected) */
let currentProviderId: ClientId | null = null;

/** Pending requests waiting for a provider to be elected */
const pendingRequests: Array<{ clientId: ClientId; request: RpcRequest }> = [];

/**
 * Handle new tab connections to the SharedWorker
 */
self.onconnect = (event: MessageEvent) => {
  const port = event.ports[0];
  const clientId = crypto.randomUUID() as ClientId;

  const connection: ClientConnection = {
    port,
    clientId,
    isProvider: false,
  };

  clients.set(clientId, connection);

  port.onmessage = (msg: MessageEvent) => handleClientMessage(clientId, msg.data);
  port.onmessageerror = () => handleClientDisconnect(clientId);

  port.start();

  // Notify client of their assigned ID
  const connectedMsg: ConnectedMessage = { type: 'connected', clientId };
  port.postMessage(connectedMsg);

  // Attempt provider election for this client
  tryBecomeProvider(clientId);
};

/**
 * Attempt to make a client the database provider using Web Locks
 *
 * Uses Web Locks API with ifAvailable to attempt non-blocking lock acquisition.
 * If the lock is acquired, this client becomes the provider and holds the lock
 * indefinitely (until tab closes).
 */
async function tryBecomeProvider(clientId: ClientId): Promise<void> {
  const client = clients.get(clientId);
  if (!client) return;

  try {
    await navigator.locks.request(
      PROVIDER_LOCK(DEFAULT_DB_NAME),
      { mode: 'exclusive', ifAvailable: true },
      async (lock) => {
        if (lock) {
          // Lock acquired - this client becomes the provider
          electProvider(clientId);

          // Hold lock forever by never resolving
          // Lock is automatically released when tab closes
          await new Promise<void>(() => {
            // Never resolves - holds lock until tab disconnects
          });
        }
        // If lock is null, another tab already has it
      }
    );
  } catch (e) {
    console.error('[SharedWorker] Lock request failed:', e);
  }
}

/**
 * Elect a client as the database provider
 *
 * Updates internal state and notifies all connected clients
 */
function electProvider(clientId: ClientId): void {
  const client = clients.get(clientId);
  if (!client) return;

  currentProviderId = clientId;
  client.isProvider = true;

  console.log('[SharedWorker] Provider elected:', clientId);

  // Notify all clients of the new provider
  for (const [id, conn] of clients) {
    const notification: ProviderElectedNotification = {
      type: 'provider-elected',
      providerId: clientId,
      isYou: id === clientId,
    };
    conn.port.postMessage(notification);
  }

  // Process any pending requests that were waiting for a provider
  processPendingRequests();
}

/**
 * Process requests that were queued while waiting for a provider
 */
function processPendingRequests(): void {
  while (pendingRequests.length > 0) {
    const pending = pendingRequests.shift();
    if (pending) {
      forwardRequestToProvider(pending.clientId, pending.request);
    }
  }
}

/**
 * Handle messages from connected clients
 */
function handleClientMessage(
  clientId: ClientId,
  msg: RpcRequest | ForwardResponseMessage
): void {
  // Check if this is a response from the provider
  if ('type' in msg && msg.type === 'forward-response') {
    handleProviderResponse(msg as ForwardResponseMessage);
    return;
  }

  // Otherwise it's a request from a client
  const request = msg as RpcRequest;

  if (!currentProviderId) {
    // No provider yet - queue the request
    pendingRequests.push({ clientId, request });
    return;
  }

  if (clientId === currentProviderId) {
    // Provider shouldn't be sending requests to itself through coordinator
    console.warn('[SharedWorker] Provider sent request to itself, ignoring');
    return;
  }

  forwardRequestToProvider(clientId, request);
}

/**
 * Forward a client request to the provider tab
 */
function forwardRequestToProvider(clientId: ClientId, request: RpcRequest): void {
  if (!currentProviderId) {
    sendNoProviderError(clientId, request.requestId);
    return;
  }

  const provider = clients.get(currentProviderId);
  if (!provider) {
    sendNoProviderError(clientId, request.requestId);
    return;
  }

  const forwardMsg: ForwardRequestMessage = {
    type: 'forward-request',
    clientId,
    request,
  };

  provider.port.postMessage(forwardMsg);
}

/**
 * Handle response from provider, routing it back to the original client
 */
function handleProviderResponse(msg: ForwardResponseMessage): void {
  const client = clients.get(msg.clientId);
  if (!client) {
    console.warn('[SharedWorker] Response for unknown client:', msg.clientId);
    return;
  }

  // Forward the response to the requesting client
  client.port.postMessage(msg.response);
}

/**
 * Send error to client when no provider is available
 */
function sendNoProviderError(clientId: ClientId, requestId: string): void {
  const client = clients.get(clientId);
  if (!client) return;

  const error: NoProviderError = {
    type: 'error',
    requestId,
    payload: {
      code: 'NO_PROVIDER',
      message: 'No database provider available',
    },
  };

  client.port.postMessage(error);
}

/**
 * Handle client disconnection
 *
 * Removes client from registry and triggers failover if provider disconnected
 */
function handleClientDisconnect(clientId: ClientId): void {
  const client = clients.get(clientId);
  if (!client) return;

  console.log('[SharedWorker] Client disconnected:', clientId);

  const wasProvider = client.isProvider;
  clients.delete(clientId);

  if (wasProvider) {
    currentProviderId = null;
    console.log('[SharedWorker] Provider disconnected, triggering failover');

    // Trigger election for remaining clients
    // The Web Lock is automatically released when the provider tab closes,
    // so remaining clients can compete for the lock
    for (const [id] of clients) {
      tryBecomeProvider(id);
      break; // Only need to trigger one - others will fail ifAvailable
    }
  }
}

// Export for testing
export { clients, currentProviderId, handleClientDisconnect };
