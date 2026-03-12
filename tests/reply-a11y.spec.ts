// Minimal A11y Test - Reply Button Keyboard Navigation
import { test, expect } from '@playwright/test';

test('reply button keyboard navigation works', async ({ page }) => {
  await page.goto('http://localhost:8090/paste/20260309_153124_untitled_this_symmetry_structural_mathematical_content');
  
  // Find reply button
  const replyBtn = page.locator('.reply-btn').first();
  
  // Check ARIA
  await expect(replyBtn).toHaveAttribute('aria-label');
  await expect(replyBtn).toHaveAttribute('tabindex', '0');
  
  // Test keyboard activation
  await replyBtn.focus();
  await page.keyboard.press('Enter');
  
  // Should navigate to home with reply_to param
  await page.waitForURL(/\?reply_to=/);
  expect(page.url()).toContain('reply_to=');
});
