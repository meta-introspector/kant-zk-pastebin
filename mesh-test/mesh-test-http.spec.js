import { test, expect } from '@playwright/test';

test('rust backend mesh endpoints work (local mesh test page via HTTP)', async ({ page }) => {
  // 1. Load the mesh test page over HTTP (to avoid file:// CORS restrictions)
  await page.goto('http://127.0.0.1:8766/mesh-test.html');

  // Wait for page to be ready
  await page.waitForSelector('#load-wasm');
  await page.waitForTimeout(500);

  // 2. Load WASM core
  await page.click('#load-wasm');

  // Wait for WASM to load and enable the buttons
  await page.waitForSelector('#announce-identity:not([disabled])', { timeout: 30000 });
  
  // Check log for WASM loaded message
  const wasmLog = await page.locator('#log').textContent();
  expect(wasmLog).toContain('WASM core loaded successfully');

  // 3. Announce identity to Rust mesh
  await page.click('#announce-identity');
  await page.waitForTimeout(1500);

  // 4. Fetch peers from Rust mesh
  await page.click('#fetch-peers');
  await page.waitForTimeout(1000);

  // 5. Ping peers via Rust mesh
  await page.click('#ping-peers');
  await page.waitForTimeout(1000);

  // 6. Check the log for results
  const log = await page.locator('#log').textContent();
  console.log('Log output:', log);

  // Verify identity announced
  await expect(log).toMatch(/Identity announced/);

  // Verify peers fetched
  await expect(log).toMatch(/Peers from Rust mesh/);

  // Verify ping sent
  await expect(log).toMatch(/Ping to Rust mesh sent/);
});
