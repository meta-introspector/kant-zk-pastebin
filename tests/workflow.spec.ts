// Complete Workflow Test - Create, Reply, Search
import { test, expect } from '@playwright/test';

const BASE = 'http://localhost:8090';

test('complete paste workflow', async ({ page }) => {
  // 1. Create a paste
  await page.goto(BASE);
  await page.fill('#c', 'Test content for workflow');
  await page.fill('#t', 'workflow-test');
  await page.fill('#k', 'test, workflow');
  
  // Wait for response
  const responsePromise = page.waitForResponse(resp => resp.url().includes('/paste') && resp.request().method() === 'POST');
  await page.click('#b');
  const response = await responsePromise;
  const data = await response.json();
  const pasteId = data.id;
  console.log('Created paste:', pasteId);
  
  // Navigate to paste
  await page.goto(`${BASE}/paste/${pasteId}`);
  
  // 2. Test reply button
  const replyBtn = page.locator('.reply-btn').first();
  await expect(replyBtn).toHaveAttribute('aria-label');
  await replyBtn.click();
  
  // Should go to home with reply_to
  await page.waitForURL(/\?reply_to=/);
  const replyParam = new URL(page.url()).searchParams.get('reply_to');
  console.log('Reply param:', replyParam);
  
  // Verify reply info shows
  const replyInfo = page.locator('#reply-info');
  await expect(replyInfo).toBeVisible();
  
  // 3. Create reply
  await page.fill('#c', 'This is a reply');
  await page.fill('#t', 'reply-test');
  await page.click('#b');
  await page.waitForURL(/\/paste\//);
  
  // 4. Search for original
  await page.goto(`${BASE}/browse?q=workflow-test`);
  await page.waitForTimeout(500);
  
  // Should find the paste
  const searchResults = page.locator('.paste');
  await expect(searchResults.first()).toBeVisible();
  
  console.log('✅ Complete workflow passed');
});
