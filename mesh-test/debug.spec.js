import { test, expect } from '@playwright/test';

test('debug wasm loading', async ({ page }) => {
  const consoleMessages = [];
  const errors = [];
  
  page.on('console', msg => {
    consoleMessages.push(msg.text());
  });
  
  page.on('pageerror', err => {
    errors.push(err.message);
  });
  
  await page.goto('file:///mnt/data1/kant/pastebin/mesh-test/mesh-test.html');
  await page.waitForSelector('#load-wasm');
  await page.waitForTimeout(500);
  
  await page.click('#load-wasm');
  await page.waitForTimeout(3000);
  
  const status = await page.locator('#status').textContent();
  const log = await page.locator('#log').textContent();
  
  console.log('Status:', status);
  console.log('Log:', log);
  console.log('Console:', consoleMessages.join('\n'));
  console.log('Page errors:', errors.join('\n'));
  
  // Try to evaluate the wasm status directly
  const wasmStatus = await page.evaluate(() => {
    return { 
      wasmCore: typeof window.wasmCore !== 'undefined' ? 'exists' : 'undefined',
      wasmOnce: typeof window.wasmOnce !== 'undefined' ? 'exists' : 'undefined'
    };
  });
  console.log('WASM status:', wasmStatus);
});