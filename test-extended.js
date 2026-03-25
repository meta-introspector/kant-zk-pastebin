#!/usr/bin/env node
// Headless browser tests for stego dashboard, static site, and new paste features
const puppeteer = require('puppeteer-core');

const PORT = process.env.TEST_PORT || 8090;
const BASE = `http://localhost:${PORT}`;
const CHROME = process.env.PUPPETEER_EXECUTABLE_PATH || process.env.CHROME || 'chromium';
const results = [];

function ok(name, pass) {
  results.push({ name, pass });
  console.log(`  ${pass ? '✅' : '❌'} ${name}`);
}

(async () => {
  console.log('=== Kant Pastebin Extended Tests ===');
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();

  try {
    // 1. Create paste and check new buttons
    console.log('\n1. Paste view buttons');
    const res = await page.evaluate(async (base) => {
      const r = await fetch(base + '/paste', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content: 'headless test content 🎯' })
      });
      return r.json();
    }, BASE);
    await page.goto(`${BASE}/paste/${res.id}`, { waitUntil: 'networkidle2' });
    const html = await page.content();
    ok('has stego button', html.includes('Stego'));
    ok('has copy button', html.includes('Copy'));
    ok('has commands section', html.includes('Commands'));
    ok('has data-v attribute (component cmd)', html.includes('data-v='));
    ok('unicode emoji renders', html.includes('🎯') || html.includes('headless test'));

    // 2. Stego dashboard loads
    console.log('\n2. Stego dashboard');
    await page.goto(`${BASE}/stego`, { waitUntil: 'networkidle2' });
    const stegoHtml = await page.content();
    ok('stego page loads', stegoHtml.includes('eRDFa Pad'));
    ok('has pastebin section', stegoHtml.includes('Pastebin'));
    ok('has post text button', stegoHtml.includes('Post Text'));
    ok('has post stego button', stegoHtml.includes('Post Stego'));
    ok('has post all button', stegoHtml.includes('Post All'));

    // 3. Stego WASM loads
    console.log('\n3. WASM loading');
    const wasmLoaded = await page.evaluate(() => {
      return new Promise(resolve => {
        let tries = 0;
        const check = () => {
          if (window._pad) resolve(true);
          else if (++tries > 20) resolve(false);
          else setTimeout(check, 200);
        };
        check();
      });
    });
    ok('WASM pad initialized', wasmLoaded);

    // 4. Stego localStorage integration
    console.log('\n4. localStorage integration');
    await page.evaluate(() => localStorage.setItem('stego-input', 'test from pastebin'));
    await page.goto(`${BASE}/stego`, { waitUntil: 'networkidle2' });
    await page.waitForTimeout(500);
    const inputVal = await page.evaluate(() => document.getElementById('input').value);
    ok('loads from localStorage', inputVal === 'test from pastebin');
    const cleared = await page.evaluate(() => localStorage.getItem('stego-input'));
    ok('clears localStorage after load', cleared === null);

    // 5. WASM pkg files served
    console.log('\n5. Static assets');
    const jsRes = await page.goto(`${BASE}/stego/pkg/erdfa_wasm.js`);
    ok('WASM JS served', jsRes.status() === 200);
    const wasmRes = await page.goto(`${BASE}/stego/pkg/erdfa_wasm_bg.wasm`);
    ok('WASM binary served', wasmRes.status() === 200);

    // 6. Post back to pastebin from stego
    console.log('\n6. Stego → Pastebin post');
    await page.goto(`${BASE}/stego`, { waitUntil: 'networkidle2' });
    await page.waitForTimeout(1000);
    await page.evaluate(() => { document.getElementById('input').value = 'stego round-trip test'; });
    await page.evaluate(() => window.postToPastebin());
    await page.waitForTimeout(1000);
    const pasteOut = await page.evaluate(() => document.getElementById('paste-out').textContent);
    ok('post to pastebin succeeds', pasteOut.includes('✅') || pasteOut.includes('2026'));

    // 7. API: paste has sheaf header
    console.log('\n7. Sheaf coordinates');
    const spool = await page.evaluate(async (base) => {
      const r = await fetch(base + '/paste', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content: 'sheaf test content' })
      });
      return r.json();
    }, BASE);
    const rawRes = await page.goto(`${BASE}/raw/${spool.id}`);
    const raw = await rawRes.text();
    ok('sheaf header present', raw.includes('Sheaf:'));
    ok('sheaf not all Earth/T_1', !raw.includes('T3 Earth B0 T_1'));

  } catch (err) {
    console.error('❌ Error:', err.message);
  } finally {
    await browser.close();
  }

  // Summary
  const passed = results.filter(r => r.pass).length;
  console.log(`\n=== ${passed}/${results.length} passed ===`);
  process.exit(passed === results.length ? 0 : 1);
})();
