import { test, expect } from '@playwright/test';

/**
 * Browser tests for SQLite WASM functionality.
 * 
 * Phase 1: Validates sql.js works correctly in browser environment
 * Phase 2 (future): Will integrate Zig-compiled CR-SQLite extension
 */

test.describe('SQLite WASM in Browser', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to test page and wait for sql.js to initialize
    await page.goto('/test-page.html');
    
    // Wait for sql.js to be ready (max 10 seconds)
    await page.waitForFunction(
      () => window.testState?.ready === true,
      { timeout: 10000 }
    );
  });

  test('sql.js loads and initializes successfully', async ({ page }) => {
    const ready = await page.evaluate(() => window.testState.ready);
    expect(ready).toBe(true);
  });

  test('sqlite_version() returns a valid version string', async ({ page }) => {
    const version = await page.evaluate(() => {
      const db = window.testState.db;
      const result = db.exec('SELECT sqlite_version()');
      return result[0].values[0][0];
    });
    
    // SQLite version is in format like "3.45.0"
    expect(version).toMatch(/^\d+\.\d+\.\d+$/);
  });

  test('creates a table and inserts data', async ({ page }) => {
    const result = await page.evaluate(() => {
      const db = window.testState.db;
      
      // Create table
      db.run('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)');
      
      // Insert data
      db.run("INSERT INTO users (name) VALUES ('Alice')");
      db.run("INSERT INTO users (name) VALUES ('Bob')");
      
      // Query data
      const rows = db.exec('SELECT * FROM users ORDER BY id');
      return rows[0].values;
    });
    
    expect(result).toHaveLength(2);
    expect(result[0][1]).toBe('Alice');
    expect(result[1][1]).toBe('Bob');
  });

  test('handles prepared statements with parameters', async ({ page }) => {
    const result = await page.evaluate(() => {
      const db = window.testState.db;
      
      db.run('CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, value TEXT)');
      
      // Use prepared statement
      const stmt = db.prepare('INSERT INTO items (value) VALUES (?)');
      stmt.run(['item1']);
      stmt.run(['item2']);
      stmt.run(['item3']);
      stmt.free();
      
      // Query back
      const rows = db.exec('SELECT COUNT(*) FROM items');
      return rows[0].values[0][0];
    });
    
    expect(result).toBe(3);
  });

  test('supports transactions', async ({ page }) => {
    const result = await page.evaluate(() => {
      const db = window.testState.db;
      
      db.run('CREATE TABLE IF NOT EXISTS txn_test (id INTEGER PRIMARY KEY, val INTEGER)');
      
      // Begin transaction
      db.run('BEGIN TRANSACTION');
      db.run('INSERT INTO txn_test (val) VALUES (100)');
      db.run('INSERT INTO txn_test (val) VALUES (200)');
      db.run('COMMIT');
      
      // Verify
      const rows = db.exec('SELECT SUM(val) FROM txn_test');
      return rows[0].values[0][0];
    });
    
    expect(result).toBe(300);
  });

  test('handles binary data (blobs)', async ({ page }) => {
    const result = await page.evaluate(() => {
      const db = window.testState.db;
      
      db.run('CREATE TABLE IF NOT EXISTS blobs (id INTEGER PRIMARY KEY, data BLOB)');
      
      // Insert binary data
      const binaryData = new Uint8Array([0x01, 0x02, 0x03, 0x04, 0x05]);
      const stmt = db.prepare('INSERT INTO blobs (data) VALUES (?)');
      stmt.run([binaryData]);
      stmt.free();
      
      // Query back
      const rows = db.exec('SELECT data FROM blobs');
      const retrieved = rows[0].values[0][0];
      
      // Return as array for comparison
      return Array.from(retrieved);
    });
    
    expect(result).toEqual([1, 2, 3, 4, 5]);
  });

  test('executes multiple statements', async ({ page }) => {
    const result = await page.evaluate(() => {
      const db = window.testState.db;
      
      // Execute multiple statements at once
      db.run(`
        CREATE TABLE IF NOT EXISTS multi (id INTEGER PRIMARY KEY, x INTEGER);
        INSERT INTO multi (x) VALUES (1);
        INSERT INTO multi (x) VALUES (2);
        INSERT INTO multi (x) VALUES (3);
      `);
      
      const rows = db.exec('SELECT COUNT(*), SUM(x) FROM multi');
      return {
        count: rows[0].values[0][0],
        sum: rows[0].values[0][1]
      };
    });
    
    expect(result.count).toBe(3);
    expect(result.sum).toBe(6);
  });
});

test.describe('CR-SQLite Extension (Future)', () => {
  test.skip('crsql_version() returns a value', async ({ page }) => {
    // This test will be enabled once Zig WASM extension is integrated
    await page.goto('/test-page.html');
    await page.waitForFunction(() => window.testState?.ready === true);
    
    const version = await page.evaluate(() => {
      const db = window.testState.db;
      const result = db.exec('SELECT crsql_version()');
      return result[0].values[0][0];
    });
    
    expect(version).toBeTruthy();
  });

  test.skip('crsql_as_crr() converts table to CRR', async ({ page }) => {
    // This test will be enabled once Zig WASM extension is integrated
    await page.goto('/test-page.html');
    await page.waitForFunction(() => window.testState?.ready === true);
    
    const success = await page.evaluate(() => {
      const db = window.testState.db;
      db.run('CREATE TABLE IF NOT EXISTS crr_test (id INTEGER PRIMARY KEY, data TEXT)');
      db.run("SELECT crsql_as_crr('crr_test')");
      return true;
    });
    
    expect(success).toBe(true);
  });

  test.skip('crsql_changes virtual table exists', async ({ page }) => {
    // This test will be enabled once Zig WASM extension is integrated
    await page.goto('/test-page.html');
    await page.waitForFunction(() => window.testState?.ready === true);
    
    const hasTable = await page.evaluate(() => {
      const db = window.testState.db;
      const result = db.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='crsql_changes'");
      return result.length > 0 && result[0].values.length > 0;
    });
    
    expect(hasTable).toBe(true);
  });
});

// Type declarations for the test page's global state
declare global {
  interface Window {
    testState: {
      ready: boolean;
      db: any;
      error: Error | null;
      sqljs: any;
    };
  }
}
