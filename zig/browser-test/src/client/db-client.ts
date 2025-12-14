/**
 * DbClient - Browser Tab Database Client
 *
 * Provides the client-side API that browser tabs use to access the database
 * through the SharedWorker coordinator.
 *
 * When elected as provider, this client spawns a dedicated worker to handle
 * database operations and routes requests from other tabs.
 */

import {
  RpcRequest,
  RpcResponse,
  RequestId,
  createRequest,
  createErrorResponse,
  RPC_TIMEOUT_MS,
  SHARED_WORKER_PATH,
  PROVIDER_LOCK,
} from '../shared';

export interface DbClientOptions {
  dbName: string;
  coordinatorUrl?: string;
  providerWorkerUrl?: string;
}

export class DbClient {
  private worker: SharedWorker | null = null;
  private port: MessagePort | null = null;
  private clientId: string | null = null;
  private isProvider = false;
  private pendingRequests = new Map<
    RequestId,
    {
      resolve: (result: unknown) => void;
      reject: (error: Error) => void;
    }
  >();
  private readyPromise: Promise<void>;
  private resolveReady!: () => void;

  // Provider-specific state
  private providerWorker: Worker | null = null;
  private providerWorkerUrl: string;
  private providerPendingRequests = new Map<
    RequestId,
    { clientId: string; requestId: RequestId }
  >();

  // Track whether database has been opened (for failover recovery)
  private databaseOpened = false;

  // Provider polling interval (for detecting provider loss)
  private providerPollInterval: ReturnType<typeof setInterval> | null = null;
  private static readonly PROVIDER_POLL_INTERVAL_MS = 1000;

  readonly dbName: string;

  constructor(options: DbClientOptions) {
    this.dbName = options.dbName;
    this.providerWorkerUrl = options.providerWorkerUrl || './provider.js';
    this.readyPromise = new Promise((resolve) => {
      this.resolveReady = resolve;
    });

    this.connect(options.coordinatorUrl);
  }

  private connect(coordinatorUrl?: string) {
    const url = coordinatorUrl || SHARED_WORKER_PATH;
    console.log('[DbClient] Connecting to SharedWorker:', url);
    this.worker = new SharedWorker(url, { type: 'module' });
    this.port = this.worker.port;

    this.port.onmessage = (event) => this.handleMessage(event.data);
    this.port.start();

    // Register unload handler to notify SharedWorker when tab closes
    this.handleBeforeUnload = () => {
      console.log('[DbClient] Tab closing, sending disconnect message');
      this.port?.postMessage({ type: 'disconnect' });
    };
    globalThis.addEventListener('beforeunload', this.handleBeforeUnload);
    // Also use pagehide which is more reliable on mobile
    globalThis.addEventListener('pagehide', this.handleBeforeUnload);
  }

  private handleBeforeUnload: () => void = () => {};

  private handleMessage(msg: unknown) {
    const message = msg as {
      type: string;
      clientId?: string;
      isYou?: boolean;
      providerId?: string;
      requestId?: RequestId;
      request?: RpcRequest;
      payload?: { result?: unknown; message?: string };
    };

    console.log('[DbClient] Received message:', message.type, message);

    switch (message.type) {
      case 'connected':
        this.clientId = message.clientId ?? null;
        console.log('[DbClient] Connected with ID:', this.clientId);
        break;

      case 'provider-elected':
        this.isProvider = message.isYou ?? false;
        console.log('[DbClient] Provider elected. Am I provider?', this.isProvider);
        if (this.isProvider) {
          this.initializeProviderWorker();
          this.stopProviderPolling();
        } else {
          // Start polling in case provider dies without sending disconnect
          this.startProviderPolling();
        }
        this.resolveReady();
        break;

      case 'try-become-provider':
        console.log('[DbClient] Asked to try becoming provider');
        this.tryAcquireProviderLock();
        break;

      case 'forward-request':
        // Only provider should receive this
        if (this.isProvider && message.clientId && message.request) {
          this.handleForwardedRequest(message.clientId, message.request);
        }
        break;

      case 'result':
      case 'error': {
        if (!message.requestId) break;
        const pending = this.pendingRequests.get(message.requestId);
        if (pending) {
          this.pendingRequests.delete(message.requestId);
          if (message.type === 'result') {
            pending.resolve(message.payload?.result);
          } else {
            pending.reject(new Error(message.payload?.message ?? 'Unknown error'));
          }
        }
        break;
      }
    }
  }

  /**
   * Start polling for provider lock availability.
   * This handles the case where the provider dies without sending a disconnect message.
   */
  private startProviderPolling() {
    if (this.providerPollInterval) return; // Already polling

    console.log('[DbClient] Starting provider polling');
    this.providerPollInterval = setInterval(() => {
      if (!this.isProvider) {
        this.tryAcquireProviderLock();
      }
    }, DbClient.PROVIDER_POLL_INTERVAL_MS);
  }

  /**
   * Stop polling for provider lock availability.
   */
  private stopProviderPolling() {
    if (this.providerPollInterval) {
      console.log('[DbClient] Stopping provider polling');
      clearInterval(this.providerPollInterval);
      this.providerPollInterval = null;
    }
  }

  /**
   * Attempt to acquire the provider Web Lock.
   * If successful, notify the coordinator that we are now the provider.
   * The lock is held for the lifetime of the tab - when the tab closes,
   * the browser automatically releases the lock.
   */
  private async tryAcquireProviderLock() {
    const lockName = PROVIDER_LOCK(this.dbName);
    console.log('[DbClient] Trying to acquire provider lock:', lockName);

    try {
      await navigator.locks.request(
        lockName,
        { mode: 'exclusive', ifAvailable: true },
        async (lock) => {
          if (lock) {
            console.log('[DbClient] Acquired provider lock!');
            // Notify SharedWorker that we are now the provider
            this.port?.postMessage({ type: 'became-provider' });

            // Hold the lock indefinitely by never resolving
            // The lock is automatically released when the tab closes
            await new Promise<void>(() => {
              // Never resolves - holds lock until tab closes
            });
          } else {
            console.log('[DbClient] Provider lock not available');
            // Another tab already has the lock - we'll receive provider-elected message
          }
        }
      );
    } catch (e) {
      console.error('[DbClient] Failed to acquire provider lock:', e);
    }
  }

  /**
   * Initialize the dedicated worker for database operations (provider only)
   */
  private initializeProviderWorker() {
    console.log('[DbClient] Initializing provider worker:', this.providerWorkerUrl);
    this.providerWorker = new Worker(this.providerWorkerUrl, { type: 'module' });

    this.providerWorker.onmessage = (event: MessageEvent<RpcResponse>) => {
      console.log('[DbClient] Provider worker response:', event.data?.type, event.data?.requestId);
      this.handleProviderWorkerResponse(event.data);
    };

    this.providerWorker.onerror = (error) => {
      console.error('[DbClient] Provider worker error:', error);
    };

    // If database was previously opened, re-open it for failover recovery
    // This ensures the new provider can serve queries immediately
    if (this.databaseOpened) {
      console.log('[DbClient] Re-opening database after failover:', this.dbName);
      // Need to wait for worker to be ready before sending open request
      // Use a small delay to ensure worker message handler is set up
      setTimeout(() => {
        this.sendRequestToLocalWorker(
          createRequest('open', crypto.randomUUID(), { dbName: this.dbName })
        ).catch((e) => {
          console.error('[DbClient] Failed to re-open database after failover:', e);
        });
      }, 0);
    }
  }

  /**
   * Handle a forwarded request from another tab (provider only)
   */
  private handleForwardedRequest(clientId: string, request: RpcRequest) {
    console.log('[DbClient] Handling forwarded request from', clientId, ':', request.type);

    if (!this.providerWorker) {
      // Worker not ready, send error back
      const errorResponse: RpcResponse = createErrorResponse(
        request.requestId,
        'PROVIDER_NOT_READY',
        'Provider worker not initialized'
      );
      this.sendForwardResponse(clientId, errorResponse);
      return;
    }

    // Track this request so we know which client to respond to
    this.providerPendingRequests.set(request.requestId, {
      clientId,
      requestId: request.requestId,
    });

    // Forward to provider worker
    this.providerWorker.postMessage(request);
  }

  /**
   * Handle response from provider worker and route back to client
   */
  private handleProviderWorkerResponse(response: RpcResponse) {
    // First check if this is a local request (from this tab)
    const localPending = this.localPendingRequests.get(response.requestId);
    if (localPending) {
      this.localPendingRequests.delete(response.requestId);
      if (response.type === 'result') {
        localPending.resolve(response.payload.result);
      } else {
        localPending.reject(new Error(response.payload.message));
      }
      return;
    }

    // Otherwise it's a forwarded request from another tab
    const forwardedPending = this.providerPendingRequests.get(response.requestId);
    if (!forwardedPending) {
      console.warn('[DbClient] Response for unknown request:', response.requestId);
      return;
    }

    this.providerPendingRequests.delete(response.requestId);
    this.sendForwardResponse(forwardedPending.clientId, response);
  }

  /**
   * Send a response back to the coordinator for routing to the original client
   */
  private sendForwardResponse(clientId: string, response: RpcResponse) {
    console.log('[DbClient] Sending forward-response for client', clientId);
    this.port?.postMessage({
      type: 'forward-response',
      clientId,
      response,
    });
  }

  get ready(): Promise<void> {
    return this.readyPromise;
  }

  get isDbProvider(): boolean {
    return this.isProvider;
  }

  get id(): string | null {
    return this.clientId;
  }

  private async sendRequest<T>(request: RpcRequest): Promise<T> {
    await this.ready;

    // If we're the provider, handle the request locally via our worker
    if (this.isProvider) {
      return this.sendRequestToLocalWorker<T>(request);
    }

    // Otherwise, send to SharedWorker for routing to the provider
    return new Promise((resolve, reject) => {
      this.pendingRequests.set(request.requestId, {
        resolve: resolve as (result: unknown) => void,
        reject,
      });
      this.port?.postMessage(request);

      // Timeout after configured duration
      setTimeout(() => {
        if (this.pendingRequests.has(request.requestId)) {
          this.pendingRequests.delete(request.requestId);
          reject(new Error('Request timeout'));
        }
      }, RPC_TIMEOUT_MS);
    });
  }

  // Track local requests (when we are the provider) - maps requestId to resolve/reject
  private localPendingRequests = new Map<
    RequestId,
    {
      resolve: (result: unknown) => void;
      reject: (error: Error) => void;
    }
  >();

  /**
   * Send request directly to local provider worker (when we are the provider)
   */
  private sendRequestToLocalWorker<T>(request: RpcRequest): Promise<T> {
    return new Promise((resolve, reject) => {
      if (!this.providerWorker) {
        reject(new Error('Provider worker not initialized'));
        return;
      }

      console.log('[DbClient] Sending local request:', request.type, request.requestId);

      // Track this request
      this.localPendingRequests.set(request.requestId, {
        resolve: resolve as (result: unknown) => void,
        reject,
      });

      this.providerWorker.postMessage(request);

      // Timeout
      setTimeout(() => {
        if (this.localPendingRequests.has(request.requestId)) {
          this.localPendingRequests.delete(request.requestId);
          reject(new Error('Request timeout'));
        }
      }, RPC_TIMEOUT_MS);
    });
  }

  async open(): Promise<void> {
    await this.sendRequest(
      createRequest('open', crypto.randomUUID(), { dbName: this.dbName })
    );
    this.databaseOpened = true;
  }

  async close(): Promise<void> {
    await this.sendRequest(
      createRequest('close', crypto.randomUUID(), { dbName: this.dbName })
    );
    this.databaseOpened = false;
  }

  async exec(sql: string, bind?: unknown[]): Promise<{ changes: number }> {
    return this.sendRequest(
      createRequest('exec', crypto.randomUUID(), { sql, bind })
    );
  }

  async query(sql: string, bind?: unknown[]): Promise<unknown[][]> {
    const result = await this.sendRequest<{ rows: unknown[][] }>(
      createRequest('query', crypto.randomUUID(), { sql, bind })
    );
    return result.rows;
  }

  async ping(): Promise<{ pong: boolean; timestamp: number }> {
    return this.sendRequest(
      createRequest('ping', crypto.randomUUID(), {})
    );
  }

  disconnect() {
    // Stop provider polling
    this.stopProviderPolling();
    // Remove unload listeners
    globalThis.removeEventListener('beforeunload', this.handleBeforeUnload);
    globalThis.removeEventListener('pagehide', this.handleBeforeUnload);
    // Notify SharedWorker
    this.port?.postMessage({ type: 'disconnect' });
    this.port?.close();
    this.worker = null;
    this.port = null;
  }
}

export function createDbClient(options: DbClientOptions): DbClient {
  return new DbClient(options);
}
