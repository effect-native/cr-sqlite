// src/shared/rpc-types.ts
function createRequest(type, requestId, payload) {
  return { type, requestId, payload };
}
function createResultResponse(requestId, result) {
  return { type: "result", requestId, payload: { result } };
}
function createErrorResponse(requestId, code, message) {
  return { type: "error", requestId, payload: { code, message } };
}

// src/shared/constants.ts
var LOCK_PREFIX = "crsqlite:";
var PROVIDER_LOCK = (dbName) => `${LOCK_PREFIX}provider:${dbName}`;
var CLIENT_LOCK = (clientId) => `${LOCK_PREFIX}client:${clientId}`;
var SHARED_WORKER_PATH = "/shared-worker.js";
var DEFAULT_DB_NAME = "default";
var RPC_TIMEOUT_MS = 3e4;
var HEARTBEAT_INTERVAL_MS = 5e3;

// src/client/db-client.ts
var DbClient = class _DbClient {
  worker = null;
  port = null;
  clientId = null;
  isProvider = false;
  pendingRequests = /* @__PURE__ */ new Map();
  readyPromise;
  resolveReady;
  // Provider-specific state
  providerWorker = null;
  providerWorkerUrl;
  providerPendingRequests = /* @__PURE__ */ new Map();
  // Track whether database has been opened (for failover recovery)
  databaseOpened = false;
  // Provider polling interval (for detecting provider loss)
  providerPollInterval = null;
  static PROVIDER_POLL_INTERVAL_MS = 1e3;
  dbName;
  constructor(options) {
    this.dbName = options.dbName;
    this.providerWorkerUrl = options.providerWorkerUrl || "./provider.js";
    this.readyPromise = new Promise((resolve) => {
      this.resolveReady = resolve;
    });
    this.connect(options.coordinatorUrl);
  }
  connect(coordinatorUrl) {
    const url = coordinatorUrl || SHARED_WORKER_PATH;
    console.log("[DbClient] Connecting to SharedWorker:", url);
    this.worker = new SharedWorker(url, { type: "module" });
    this.port = this.worker.port;
    this.port.onmessage = (event) => this.handleMessage(event.data);
    this.port.start();
    this.handleBeforeUnload = () => {
      console.log("[DbClient] Tab closing, sending disconnect message");
      this.port?.postMessage({ type: "disconnect" });
    };
    globalThis.addEventListener("beforeunload", this.handleBeforeUnload);
    globalThis.addEventListener("pagehide", this.handleBeforeUnload);
  }
  handleBeforeUnload = () => {
  };
  handleMessage(msg) {
    const message = msg;
    console.log("[DbClient] Received message:", message.type, message);
    switch (message.type) {
      case "connected":
        this.clientId = message.clientId ?? null;
        console.log("[DbClient] Connected with ID:", this.clientId);
        break;
      case "provider-elected":
        this.isProvider = message.isYou ?? false;
        console.log("[DbClient] Provider elected. Am I provider?", this.isProvider);
        if (this.isProvider) {
          this.initializeProviderWorker();
          this.stopProviderPolling();
        } else {
          this.startProviderPolling();
        }
        this.resolveReady();
        break;
      case "try-become-provider":
        console.log("[DbClient] Asked to try becoming provider");
        this.tryAcquireProviderLock();
        break;
      case "forward-request":
        if (this.isProvider && message.clientId && message.request) {
          this.handleForwardedRequest(message.clientId, message.request);
        }
        break;
      case "result":
      case "error": {
        if (!message.requestId) break;
        const pending = this.pendingRequests.get(message.requestId);
        if (pending) {
          this.pendingRequests.delete(message.requestId);
          if (message.type === "result") {
            pending.resolve(message.payload?.result);
          } else {
            pending.reject(new Error(message.payload?.message ?? "Unknown error"));
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
  startProviderPolling() {
    if (this.providerPollInterval) return;
    console.log("[DbClient] Starting provider polling");
    this.providerPollInterval = setInterval(() => {
      if (!this.isProvider) {
        this.tryAcquireProviderLock();
      }
    }, _DbClient.PROVIDER_POLL_INTERVAL_MS);
  }
  /**
   * Stop polling for provider lock availability.
   */
  stopProviderPolling() {
    if (this.providerPollInterval) {
      console.log("[DbClient] Stopping provider polling");
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
  async tryAcquireProviderLock() {
    const lockName = PROVIDER_LOCK(this.dbName);
    console.log("[DbClient] Trying to acquire provider lock:", lockName);
    try {
      await navigator.locks.request(
        lockName,
        { mode: "exclusive", ifAvailable: true },
        async (lock) => {
          if (lock) {
            console.log("[DbClient] Acquired provider lock!");
            this.port?.postMessage({ type: "became-provider" });
            await new Promise(() => {
            });
          } else {
            console.log("[DbClient] Provider lock not available");
          }
        }
      );
    } catch (e) {
      console.error("[DbClient] Failed to acquire provider lock:", e);
    }
  }
  /**
   * Initialize the dedicated worker for database operations (provider only)
   */
  initializeProviderWorker() {
    console.log("[DbClient] Initializing provider worker:", this.providerWorkerUrl);
    this.providerWorker = new Worker(this.providerWorkerUrl, { type: "module" });
    this.providerWorker.onmessage = (event) => {
      console.log("[DbClient] Provider worker response:", event.data?.type, event.data?.requestId);
      this.handleProviderWorkerResponse(event.data);
    };
    this.providerWorker.onerror = (error) => {
      console.error("[DbClient] Provider worker error:", error);
    };
    if (this.databaseOpened) {
      console.log("[DbClient] Re-opening database after failover:", this.dbName);
      setTimeout(() => {
        this.sendRequestToLocalWorker(
          createRequest("open", crypto.randomUUID(), { dbName: this.dbName })
        ).catch((e) => {
          console.error("[DbClient] Failed to re-open database after failover:", e);
        });
      }, 0);
    }
  }
  /**
   * Handle a forwarded request from another tab (provider only)
   */
  handleForwardedRequest(clientId, request) {
    console.log("[DbClient] Handling forwarded request from", clientId, ":", request.type);
    if (!this.providerWorker) {
      const errorResponse = createErrorResponse(
        request.requestId,
        "PROVIDER_NOT_READY",
        "Provider worker not initialized"
      );
      this.sendForwardResponse(clientId, errorResponse);
      return;
    }
    this.providerPendingRequests.set(request.requestId, {
      clientId,
      requestId: request.requestId
    });
    this.providerWorker.postMessage(request);
  }
  /**
   * Handle response from provider worker and route back to client
   */
  handleProviderWorkerResponse(response) {
    const localPending = this.localPendingRequests.get(response.requestId);
    if (localPending) {
      this.localPendingRequests.delete(response.requestId);
      if (response.type === "result") {
        localPending.resolve(response.payload.result);
      } else {
        localPending.reject(new Error(response.payload.message));
      }
      return;
    }
    const forwardedPending = this.providerPendingRequests.get(response.requestId);
    if (!forwardedPending) {
      console.warn("[DbClient] Response for unknown request:", response.requestId);
      return;
    }
    this.providerPendingRequests.delete(response.requestId);
    this.sendForwardResponse(forwardedPending.clientId, response);
  }
  /**
   * Send a response back to the coordinator for routing to the original client
   */
  sendForwardResponse(clientId, response) {
    console.log("[DbClient] Sending forward-response for client", clientId);
    this.port?.postMessage({
      type: "forward-response",
      clientId,
      response
    });
  }
  get ready() {
    return this.readyPromise;
  }
  get isDbProvider() {
    return this.isProvider;
  }
  get id() {
    return this.clientId;
  }
  async sendRequest(request) {
    await this.ready;
    if (this.isProvider) {
      return this.sendRequestToLocalWorker(request);
    }
    return new Promise((resolve, reject) => {
      this.pendingRequests.set(request.requestId, {
        resolve,
        reject
      });
      this.port?.postMessage(request);
      setTimeout(() => {
        if (this.pendingRequests.has(request.requestId)) {
          this.pendingRequests.delete(request.requestId);
          reject(new Error("Request timeout"));
        }
      }, RPC_TIMEOUT_MS);
    });
  }
  // Track local requests (when we are the provider) - maps requestId to resolve/reject
  localPendingRequests = /* @__PURE__ */ new Map();
  /**
   * Send request directly to local provider worker (when we are the provider)
   */
  sendRequestToLocalWorker(request) {
    return new Promise((resolve, reject) => {
      if (!this.providerWorker) {
        reject(new Error("Provider worker not initialized"));
        return;
      }
      console.log("[DbClient] Sending local request:", request.type, request.requestId);
      this.localPendingRequests.set(request.requestId, {
        resolve,
        reject
      });
      this.providerWorker.postMessage(request);
      setTimeout(() => {
        if (this.localPendingRequests.has(request.requestId)) {
          this.localPendingRequests.delete(request.requestId);
          reject(new Error("Request timeout"));
        }
      }, RPC_TIMEOUT_MS);
    });
  }
  async open() {
    await this.sendRequest(
      createRequest("open", crypto.randomUUID(), { dbName: this.dbName })
    );
    this.databaseOpened = true;
  }
  async close() {
    await this.sendRequest(
      createRequest("close", crypto.randomUUID(), { dbName: this.dbName })
    );
    this.databaseOpened = false;
  }
  async exec(sql, bind) {
    return this.sendRequest(
      createRequest("exec", crypto.randomUUID(), { sql, bind })
    );
  }
  async query(sql, bind) {
    const result = await this.sendRequest(
      createRequest("query", crypto.randomUUID(), { sql, bind })
    );
    return result.rows;
  }
  async ping() {
    return this.sendRequest(
      createRequest("ping", crypto.randomUUID(), {})
    );
  }
  disconnect() {
    this.stopProviderPolling();
    globalThis.removeEventListener("beforeunload", this.handleBeforeUnload);
    globalThis.removeEventListener("pagehide", this.handleBeforeUnload);
    this.port?.postMessage({ type: "disconnect" });
    this.port?.close();
    this.worker = null;
    this.port = null;
  }
};
function createDbClient(options) {
  return new DbClient(options);
}
export {
  CLIENT_LOCK,
  DEFAULT_DB_NAME,
  DbClient,
  HEARTBEAT_INTERVAL_MS,
  LOCK_PREFIX,
  PROVIDER_LOCK,
  RPC_TIMEOUT_MS,
  SHARED_WORKER_PATH,
  createDbClient,
  createErrorResponse,
  createRequest,
  createResultResponse
};
//# sourceMappingURL=crsql-multitab.js.map
