/**
 * Client module for browser tab database access
 *
 * @example
 * ```typescript
 * import { DbClient, createDbClient } from './client';
 *
 * const client = createDbClient({ dbName: 'mydb' });
 * await client.ready;
 * const rows = await client.query('SELECT * FROM users');
 * ```
 */

export { DbClient, createDbClient } from './db-client';
export type { DbClientOptions } from './db-client';
