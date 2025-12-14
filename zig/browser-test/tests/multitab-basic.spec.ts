import { test, expect } from '@playwright/test';

/**
 * Multi-tab database coordination tests.
 * 
 * These tests validate that multiple browser tabs can share a single
 * SQLite database through SharedWorker-based coordination:
 * - Exactly one tab becomes the "provider" (holds actual DB connection)
 * - Other tabs route queries through the coordinator to the provider
 * - Provider failover when the provider tab closes
 * 
 * All tests are skipped until the coordinator infrastructure is bundled.
 */

test.describe('Multi-tab Database Coordination', () => {
  
  test.skip('two tabs can connect to SharedWorker', async ({ browser }) => {
    // Skip until coordinator is bundled
    const context = await browser.newContext();
    const page1 = await context.newPage();
    const page2 = await context.newPage();
    
    await page1.goto('/multitab-test.html');
    await page2.goto('/multitab-test.html');
    
    // Both should connect - status contains "Connected"
    await expect(page1.locator('#status')).toContainText('Connected');
    await expect(page2.locator('#status')).toContainText('Connected');
    
    await context.close();
  });

  test.skip('exactly one tab becomes provider', async ({ browser }) => {
    const context = await browser.newContext();
    const pages = await Promise.all([
      context.newPage(),
      context.newPage(),
      context.newPage(),
    ]);
    
    for (const page of pages) {
      await page.goto('/multitab-test.html');
    }
    
    // Wait for provider election
    await pages[0].waitForTimeout(1000);
    
    const providerCounts = await Promise.all(
      pages.map(p => p.evaluate(() => (window as any).dbClient?.isDbProvider))
    );
    
    const providerCount = providerCounts.filter(Boolean).length;
    expect(providerCount).toBe(1);
    
    await context.close();
  });

  test.skip('non-provider tab can query through coordinator', async ({ browser }) => {
    const context = await browser.newContext();
    const page1 = await context.newPage();
    const page2 = await context.newPage();
    
    await page1.goto('/multitab-test.html');
    await page2.goto('/multitab-test.html');
    
    // Wait for ready
    await page1.waitForFunction(() => (window as any).dbClient?.ready);
    await page2.waitForFunction(() => (window as any).dbClient?.ready);
    
    // Query from both tabs
    const v1 = await page1.evaluate(async () => {
      return (window as any).dbClient.query('SELECT 1 + 1');
    });
    const v2 = await page2.evaluate(async () => {
      return (window as any).dbClient.query('SELECT 2 + 2');
    });
    
    expect(v1).toEqual([[2]]);
    expect(v2).toEqual([[4]]);
    
    await context.close();
  });

  test.skip('write from one tab visible in another', async ({ browser }) => {
    const context = await browser.newContext();
    const page1 = await context.newPage();
    const page2 = await context.newPage();
    
    await page1.goto('/multitab-test.html');
    await page2.goto('/multitab-test.html');
    
    await page1.waitForFunction(() => (window as any).dbClient?.ready);
    await page2.waitForFunction(() => (window as any).dbClient?.ready);
    
    // Tab 1 creates table and inserts
    await page1.evaluate(async () => {
      const client = (window as any).dbClient;
      await client.exec('CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
      await client.exec("INSERT INTO test VALUES (1, 'hello')");
    });
    
    // Tab 2 reads
    const result = await page2.evaluate(async () => {
      return (window as any).dbClient.query('SELECT value FROM test WHERE id = 1');
    });
    
    expect(result).toEqual([['hello']]);
    
    await context.close();
  });
});

// Type declarations for multi-tab test page globals
declare global {
  interface Window {
    dbClient?: {
      ready: Promise<void>;
      isDbProvider: boolean;
      id: string | null;
      query: (sql: string) => Promise<any[][]>;
      exec: (sql: string) => Promise<void>;
    };
  }
}
