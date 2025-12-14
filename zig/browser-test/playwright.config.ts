import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  retries: 0,
  use: {
    headless: true,
    viewport: { width: 1280, height: 720 },
    ignoreHTTPSErrors: true,
  },
  webServer: {
    command: 'npx serve fixtures -l 3456',
    port: 3456,
    reuseExistingServer: !process.env.CI,
    timeout: 30000,
  },
});
