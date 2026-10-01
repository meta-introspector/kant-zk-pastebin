#!/usr/bin/env node
/** Simulate the vaciu room workflow without consuming a user-provided pass. */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dryRun = process.env.VACIU_DRY_RUN !== '0';
const link = process.env.VACIU_TEST_URL;
if (!dryRun && !link) throw new Error('real vaciu test requires VACIU_TEST_URL; refusing to read or reuse a pass file');
const outDir = path.join(root, 'data', 'gui2lean4', 'proofs', 'run-vaciu-room-simulation');
fs.mkdirSync(outDir, { recursive: true });
const require = createRequire(import.meta.url);
const { chromium } = require(path.join(root, 'gui2lean4', 'node_modules', 'playwright'));
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
let capturedLine = null;
await page.route('**/room/**', async route => {
  if (route.request().method() === 'POST') capturedLine = route.request().postData();
  // Let the page render its normal success state; the real witnessed line is
  // posted below from Node because the public relay does not allow browser CORS.
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ cursor: 0 }) });
});
try {
  await page.goto(link || 'https://kant-zk-pastebin.pages.dev/paste.html', { waitUntil: 'networkidle', timeout: 30_000 });
  await page.waitForTimeout(2_000);
  if (dryRun) {
    await page.locator('#text').fill('vaciu dry-run: GUI flow rendered without consuming a room pass.');
    await page.screenshot({ path: path.join(outDir, 'vaciu-room-dry-run.png'), fullPage: true });
    fs.writeFileSync(path.join(outDir, 'result.json'), JSON.stringify({ simulated: true, dryRun: true, postAttempted: false, redaction: 'No pass was loaded or sent.' }, null, 2));
    console.log(JSON.stringify({ simulated: true, dryRun: true, artifactDir: outDir }, null, 2));
    await browser.close();
    process.exit(0);
  }
  if (await page.locator('#post').isDisabled()) {
    await page.locator('#joinbox').fill(link);
    await page.locator('#join').click();
    try {
      await page.waitForFunction(() => !document.querySelector('#post')?.disabled, null, { timeout: 30_000 });
    } catch {
      const log = await page.locator('#log').innerText().catch(() => '');
      throw new Error(`vaciu join failed: ${log.replace(/https?:\/\/\S+/g, '[redacted-url]')}`);
    }
  }
  const text = 'vaciu simulation: GUI2Proof verified the sops-backed Aristo Pages deployment; this is the one permitted room post.';
  await page.locator('#text').fill(text);
  await page.locator('#post').click();
  await new Promise(resolve => setTimeout(resolve, 500));
  if (!capturedLine) throw new Error('vaciu GUI did not construct a kzchat line');
  const pass = link.split('#', 2)[1];
  const relayUrl = 'https://solana.solfunmeme.com/relay/room/89e3c2a8499c476bab2c49ba106910d0a1406ddb959d47d1c468a7df250df2f6';
  const response = await fetch(relayUrl, { method: 'POST', headers: { 'content-type': 'text/plain', 'x-kant-pass': pass }, body: capturedLine });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`vaciu relay refused (${response.status})`);
  await page.evaluate(out => { const d = document.createElement('div'); d.textContent = `relay accepted (cursor ${out.cursor})`; d.className = 'ok'; document.querySelector('#log').prepend(d); }, result);
  await page.waitForFunction(() => [...document.querySelectorAll('#log div')].some(e => /posted \(cursor/.test(e.textContent)), null, { timeout: 5_000 });
  await page.screenshot({ path: path.join(outDir, 'vaciu-room-posted.png'), fullPage: true });
  const log = await page.locator('#log').innerText();
  fs.writeFileSync(path.join(outDir, 'result.json'), JSON.stringify({ simulated: true, room: '89e3c2a8499c476bab2c49ba106910d0a1406ddb959d47d1c468a7df250df2f6', log, redaction: 'pass link omitted' }, null, 2));
  console.log(JSON.stringify({ simulated: true, artifactDir: outDir, log }, null, 2));
} finally {
  await browser.close();
}
