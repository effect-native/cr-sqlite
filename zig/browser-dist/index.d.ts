/**
 * @effect-native/libcrsql-browser - CR-SQLite for browsers with multi-tab support
 *
 * This package provides CRDT-based SQLite replication for browser environments,
 * with automatic multi-tab coordination via SharedWorker.
 */

/** Configuration options for DbClient */
export interface DbClientOptions {
  /** Database name (default: "default") */
  dbName: string;
  /** URL to the coordinator SharedWorker (default: "./coordinator.js") */
  coordinatorUrl?: string;
  /** URL to the provider Worker (default: "./provider.js") */
  providerWorkerUrl?: string;
}

/** Row returned from SQL queries */
export interface SqlRow {
  [column: string]: unknown;
}

/** Result of an exec() call */
export interface ExecResult {
  /** Rows returned from the query */
  rows: SqlRow[];
  /** Number of rows changed (for INSERT/UPDATE/DELETE) */
  changes: number;
}

/** Result of a run() call */
export interface RunResult {
  /** Number of rows changed */
  changes: number;
  /** Last inserted row ID */
  lastInsertRowId: number;
}

/**
 * Database client for browser environments.
 *
 * Automatically handles multi-tab coordination - one tab becomes the "provider"
 * that owns the actual database connection, while other tabs proxy requests
 * through SharedWorker.
 *
 * @example
 * ```typescript
 * import { DbClient } from '@effect-native/libcrsql-browser';
 *
 * const db = new DbClient({ dbName: 'myapp' });
 * await db.ready();
 *
 * // Create a CRDT-enabled table
 * await db.exec(`
 *   CREATE TABLE IF NOT EXISTS todos (id TEXT PRIMARY KEY, title TEXT, done INTEGER);
 *   SELECT crsql_as_crr('todos');
 * `);
 *
 * // Query data
 * const todos = await db.exec('SELECT * FROM todos');
 * console.log(todos.rows);
 *
 * // Get changes for sync
 * const changes = await db.getChanges(0n);
 * ```
 */
export declare class DbClient {
  /** The database name */
  readonly dbName: string;

  /** Whether this client is the provider (owns the database connection) */
  readonly isProvider: boolean;

  /** Unique client ID assigned by the coordinator */
  readonly clientId: string | null;

  /**
   * Create a new database client.
   * @param options - Configuration options
   */
  constructor(options: DbClientOptions);

  /**
   * Wait for the client to be ready (connected and provider elected).
   * @returns Promise that resolves when ready
   */
  ready(): Promise<void>;

  /**
   * Execute SQL and return results.
   * @param sql - SQL statement(s) to execute
   * @param params - Optional bind parameters
   * @returns Query results with rows and changes count
   */
  exec(sql: string, params?: unknown[]): Promise<ExecResult>;

  /**
   * Execute SQL without returning results (for INSERT/UPDATE/DELETE).
   * @param sql - SQL statement to execute
   * @param params - Optional bind parameters
   * @returns Changes count and last insert row ID
   */
  run(sql: string, params?: unknown[]): Promise<RunResult>;

  /**
   * Get CR-SQLite changes since a given version.
   * @param sinceVersion - Database version to get changes since (bigint)
   * @returns Array of change records for sync
   */
  getChanges(sinceVersion: bigint): Promise<CRSQLiteChange[]>;

  /**
   * Apply CR-SQLite changes from another database.
   * @param changes - Array of change records to apply
   */
  applyChanges(changes: CRSQLiteChange[]): Promise<void>;

  /**
   * Get the current database version.
   * @returns Current version as bigint
   */
  getVersion(): Promise<bigint>;

  /**
   * Close the database connection.
   * Only effective if this client is the provider.
   */
  close(): Promise<void>;
}

/**
 * CR-SQLite change record for sync.
 * Represents a single change to be replicated.
 */
export interface CRSQLiteChange {
  /** Table name */
  table: string;
  /** Primary key value(s) */
  pk: unknown;
  /** Column name that changed */
  cid: string;
  /** New value */
  val: unknown;
  /** Column version */
  col_version: bigint;
  /** Database version when change occurred */
  db_version: bigint;
  /** Site ID that made the change */
  site_id: Uint8Array;
  /** Causal length */
  cl: bigint;
  /** Sequence number */
  seq: bigint;
}

/** Constants used by the multi-tab system */
export declare const LOCK_PREFIX: string;
export declare const PROVIDER_LOCK: (dbName: string) => string;
export declare const CLIENT_LOCK: (clientId: string) => string;
export declare const SHARED_WORKER_PATH: string;
export declare const DEFAULT_DB_NAME: string;
export declare const RPC_TIMEOUT_MS: number;
export declare const HEARTBEAT_INTERVAL_MS: number;

/** Default export is the DbClient class */
export default DbClient;
