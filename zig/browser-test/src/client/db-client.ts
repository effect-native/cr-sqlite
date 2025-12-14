/**
 * DbClient - Browser Tab Database Client
 *
 * Provides the client-side API that browser tabs use to access the database
 * through the SharedWorker coordinator.
 */

import {
  RpcRequest,
  RequestId,
  createRequest,
  RPC_TIMEOUT_MS,
  SHARED_WORKER_PATH,
} from '../shared';

export interface DbClientOptions {
  dbName: string;
  coordinatorUrl?: string;
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

  readonly dbName: string;

  constructor(options: DbClientOptions) {
    this.dbName = options.dbName;
    this.readyPromise = new Promise((resolve) => {
      this.resolveReady = resolve;
    });

    this.connect(options.coordinatorUrl);
  }

  private connect(coordinatorUrl?: string) {
    const url = coordinatorUrl || SHARED_WORKER_PATH;
    this.worker = new SharedWorker(url, { type: 'module' });
    this.port = this.worker.port;

    this.port.onmessage = (event) => this.handleMessage(event.data);
    this.port.start();
  }

  private handleMessage(msg: unknown) {
    const message = msg as {
      type: string;
      clientId?: string;
      isYou?: boolean;
      requestId?: RequestId;
      payload?: { result?: unknown; message?: string };
    };

    switch (message.type) {
      case 'connected':
        this.clientId = message.clientId ?? null;
        break;

      case 'provider-elected':
        this.isProvider = message.isYou ?? false;
        this.resolveReady();
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

  async open(): Promise<void> {
    await this.sendRequest(
      createRequest('open', crypto.randomUUID(), { dbName: this.dbName })
    );
  }

  async close(): Promise<void> {
    await this.sendRequest(
      createRequest('close', crypto.randomUUID(), { dbName: this.dbName })
    );
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
    this.port?.close();
    this.worker = null;
    this.port = null;
  }
}

export function createDbClient(options: DbClientOptions): DbClient {
  return new DbClient(options);
}
