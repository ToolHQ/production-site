import { defineConfig } from '@playwright/test';

const reportsUrl = process.env.REPORTS_URL ?? 'https://reports.dnor.io';

export default defineConfig({
  testDir: '.',
  timeout: 60_000,
  use: {
    baseURL: reportsUrl,
    trace: 'off',
  },
});
