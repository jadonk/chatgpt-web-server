import { test, expect } from '@playwright/test';

test.use({
  ignoreHTTPSErrors: true,
});

test('record home page interaction', async ({ page }) => {
  await page.goto('http://localhost:3000/page/home', { waitUntil: 'domcontentloaded' });
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
  const ledToggle = page.getByRole('button', { name: /toggle led/i });
  if (await ledToggle.isVisible().catch(() => false)) {
    await ledToggle.click();
    await page.waitForTimeout(300);
    await ledToggle.click();
    await page.waitForTimeout(300);
  }
  const refreshTemp = page.getByRole('button', { name: /refresh temp/i });
  if (await refreshTemp.isVisible().catch(() => false)) {
    await refreshTemp.click();
    await page.waitForTimeout(300);
    await refreshTemp.click();
    await page.waitForTimeout(300);
  }
  await page.waitForTimeout(700);                  // outro dwell
});

