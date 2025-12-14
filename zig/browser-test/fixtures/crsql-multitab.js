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
var DbClient = class {
  worker = null;
  port = null;
  clientId = null;
  isProvider = false;
  pendingRequests = /* @__PURE__ */ new Map();
  readyPromise;
  resolveReady;
  dbName;
  constructor(options) {
    this.dbName = options.dbName;
    this.readyPromise = new Promise((resolve) => {
      this.resolveReady = resolve;
    });
    this.connect(options.coordinatorUrl);
  }
  connect(coordinatorUrl) {
    const url = coordinatorUrl || SHARED_WORKER_PATH;
    this.worker = new SharedWorker(url, { type: "module" });
    this.port = this.worker.port;
    this.port.onmessage = (event) => this.handleMessage(event.data);
    this.port.start();
  }
  handleMessage(msg) {
    const message = msg;
    switch (message.type) {
      case "connected":
        this.clientId = message.clientId ?? null;
        break;
      case "provider-elected":
        this.isProvider = message.isYou ?? false;
        this.resolveReady();
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
  async open() {
    await this.sendRequest(
      createRequest("open", crypto.randomUUID(), { dbName: this.dbName })
    );
  }
  async close() {
    await this.sendRequest(
      createRequest("close", crypto.randomUUID(), { dbName: this.dbName })
    );
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
