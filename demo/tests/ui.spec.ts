import { test, expect } from '@playwright/test';

test('live interaction recording', async ({ page }) => {
  await page.goto('/page/home');
  await expect(page.getByText(/Beagle Device Panel/i)).toBeVisible();

  // Read temperature
  await page.getByRole('button', { name: /Read temperature/i }).click();
  await expect(page.locator('#value-temp_sensor')).toContainText('°C', { timeout: 5000 });

  // LED on/off
  await page.getByRole('button', { name: /^LED ON$/i }).click();
  await expect(page.locator('#value-led')).toHaveText(/on|off/);
  await page.getByRole('button', { name: /^LED OFF$/i }).click();
  await expect(page.locator('#value-led')).toHaveText(/off/);
});
