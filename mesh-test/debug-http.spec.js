import { test, expect } from '@playwright/test';

test('debug wasm loading over HTTP', async ({ page }) => {
  const consoleMessages = [];
  const errors = [];
  
  page.on('console', msg => {
    consoleMessages.push(msg.text());
  });
  
  page.on('pageerror', err => {
    errors.push(err.message);
  });
  
  await page.goto('http://127.0.0.1:8766/mesh-test.html');
  await page.waitForSelector('#load-wasm');
  await page.waitForTimeout(500);
  
  await page.click('#load-wasm');
  await page.waitForTimeout(5000);
  
  const status = await page.locator('#status').textContent();
  const log = await page.locator('#log').textContent();
  
  console.log('Status:', status);
  console.log('Log:', log);
  console.log('Console:', consoleMessages.join('\n'));
  console.log('Page errors:', errors.join('\n'));
});
