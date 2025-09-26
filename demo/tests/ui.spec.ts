import { test, expect } from '@playwright/test';

test('record home page interaction', async ({ page }) => {
  await page.goto('/page/home', { waitUntil: 'domcontentloaded' });
  await expect(page).toHaveTitle(/.+/);            // page rendered
  await page.waitForTimeout(500);                  // intro dwell

  const readTemp = page.getByRole('button', { name: /read temperature/i });
  if (await readTemp.isVisible().catch(() => false)) {
    await readTemp.click();
    await page.waitForTimeout(400);
  }
  const ledOn = page.getByRole('button', { name: /^led on$/i });
  if (await ledOn.isVisible().catch(() => false)) {
    await ledOn.click();
    await page.waitForTimeout(300);
  }
  const ledOff = page.getByRole('button', { name: /^led off$/i });
  if (await ledOff.isVisible().catch(() => false)) {
    await ledOff.click();
    await page.waitForTimeout(300);
  }
  await page.waitForTimeout(700);                  // outro dwell
});

