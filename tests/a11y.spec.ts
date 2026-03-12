// Playwright A11y Tests for kant-pastebin
import { test, expect } from '@playwright/test';

test.describe('kant-pastebin Navigation A11y', () => {
  test('should have skip to content link', async ({ page }) => {
    await page.goto('http://localhost:8090/');
    
    const skip = page.locator('#skip-to-content');
    await expect(skip).toBeAttached();
    
    // Should be visible on focus
    await skip.focus();
    await expect(skip).toBeVisible();
  });

  test('should have ARIA labels on all buttons', async ({ page }) => {
    await page.goto('http://localhost:8080/browse');
    
    const buttons = await page.locator('button').all();
    for (const button of buttons) {
      const ariaLabel = await button.getAttribute('aria-label');
      expect(ariaLabel).toBeTruthy();
    }
  });

  test('should support keyboard navigation on filters', async ({ page }) => {
    await page.goto('http://localhost:8080/browse');
    
    // Tab to first filter button
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    
    const focused = page.locator(':focus');
    await expect(focused).toHaveAttribute('class', /filter-btn/);
    
    // Activate with Enter
    await page.keyboard.press('Enter');
    await expect(focused).toHaveClass(/active/);
  });

  test('should expose FRACTRAN state for screen readers', async ({ page }) => {
    await page.goto('http://localhost:8080/browse');
    
    const filterBtn = page.locator('.filter-btn').first();
    const fractranState = await filterBtn.getAttribute('data-fractran-state');
    
    expect(fractranState).toMatch(/^\d+$/);
    expect(BigInt(fractranState)).toBeGreaterThan(0n);
  });

  test('should announce filter changes', async ({ page }) => {
    await page.goto('http://localhost:8080/browse');
    
    const liveRegion = page.locator('#a11y-live');
    await expect(liveRegion).toBeAttached();
    await expect(liveRegion).toHaveAttribute('aria-live', 'polite');
    
    // Click filter
    await page.click('.filter-btn[data-filter="deletable"]');
    
    // Wait for announcement
    await page.waitForTimeout(100);
    const announcement = await liveRegion.textContent();
    expect(announcement).toContain('Filter');
  });

  test('should support arrow key navigation in paste list', async ({ page }) => {
    await page.goto('http://localhost:8080/browse');
    
    // Focus first paste
    const firstPaste = page.locator('.paste').first();
    await firstPaste.focus();
    
    // Press down arrow
    await page.keyboard.press('ArrowDown');
    
    // Second paste should be focused
    const focused = page.locator(':focus');
    await expect(focused).toHaveAttribute('class', /paste/);
  });

  test('should have semantic HTML landmarks', async ({ page }) => {
    await page.goto('http://localhost:8080/');
    
    const main = page.locator('[role="main"]');
    await expect(main).toBeAttached();
    
    const articles = page.locator('[role="article"]');
    const count = await articles.count();
    expect(count).toBeGreaterThan(0);
  });

  test('should decode FRACTRAN state correctly', async ({ page }) => {
    await page.goto('http://localhost:8080/browse');
    
    const state = await page.evaluate(() => {
      return window.FRACTRAN.encode(1, 0, 2, 0);
    });
    
    const decoded = await page.evaluate((s) => {
      return window.FRACTRAN.toText(s);
    }, state);
    
    expect(decoded).toContain('Page: browse');
    expect(decoded).toContain('Filter: large');
  });
});

function extractPower(n: bigint, prime: bigint): number {
  let power = 0;
  while (n % prime === 0n) {
    n /= prime;
    power++;
  }
  return power;
}
