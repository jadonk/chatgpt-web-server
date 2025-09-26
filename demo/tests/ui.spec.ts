import { test, expect } from '@playwright/test';

test('record home page interaction', async ({ page }) => {
  await page.goto('/page/home', { waitUntil: 'domcontentloaded' });

  // Small dwell so the first frame isn't blank
  await page.waitForTimeout(500);

  // If your demo buttons are present, interact with them.
  const readTemp = page.getByRole('button', { name: /read temperature/i });
  if (await readTemp.isVisible().catch(() => false)) {
    await readTemp.click();
    await page.waitForTimeout(500);
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

  // Short outro dwell ensures a clean tail frame
  await page.waitForTimeout(800);
});
