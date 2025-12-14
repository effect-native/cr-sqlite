/**
 * Constants for Multi-tab CR-SQLite Coordination
 *
 * Defines lock names and prefixes used by Web Locks API
 * for coordinating database access across browser tabs.
 */

/** Prefix for all CR-SQLite related locks */
export const LOCK_PREFIX = 'crsqlite:';

/** Lock name for the database provider (tab that owns the connection) */
export const PROVIDER_LOCK = (dbName: string): string =>
  `${LOCK_PREFIX}provider:${dbName}`;

/** Lock name for client registration */
export const CLIENT_LOCK = (clientId: string): string =>
  `${LOCK_PREFIX}client:${clientId}`;

/** SharedWorker script path */
export const SHARED_WORKER_PATH = '/shared-worker.js';

/** Default database name when none specified */
export const DEFAULT_DB_NAME = 'default';

/** Timeout for RPC requests (milliseconds) */
export const RPC_TIMEOUT_MS = 30_000;

/** Heartbeat interval for connection health (milliseconds) */
export const HEARTBEAT_INTERVAL_MS = 5_000;
