import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    headless: true,
    video: 'on'
  },
  outputDir: 'recordings'
});
