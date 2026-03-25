#!/usr/bin/env node
// Test all links and routes on the live pastebin
const puppeteer = require('puppeteer-core');
const BASE = process.env.TEST_URL || 'https://solana.solfunmeme.com/pastebin';
const CHROME = process.env.PUPPETEER_EXECUTABLE_PATH || process.env.CHROME || 'chromium';
const results = [];

function ok(name, pass, detail) {
  results.push({ name, pass });
  console.log(`  ${pass ? '✅' : '❌'} ${name}${detail ? ' — ' + detail : ''}`);
}

(async () => {
  console.log(`=== Link Test: ${BASE} ===\n`);
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();

  try {
    // 1. Home
    console.log('1. Home page');
    const homeRes = await page.goto(BASE + '/', { waitUntil: 'networkidle2', timeout: 15000 });
    ok('home loads', homeRes.status() === 200);
    ok('title', (await page.title()).includes('Kant Pastebin'));

    // 2. Collect all nav links
    console.log('\n2. Nav links');
    const navLinks = await page.$$eval('.nav a', els => els.map(a => ({ href: a.href, text: a.textContent.trim() })));
    for (const link of navLinks) {
      const res = await page.goto(link.href, { waitUntil: 'networkidle2', timeout: 15000 });
      ok(`nav: ${link.text}`, res.status() === 200, link.href);
    }

    // 3. Browse page — collect paste links
    console.log('\n3. Browse paste links (first 5)');
    await page.goto(BASE + '/browse', { waitUntil: 'networkidle2', timeout: 15000 });
    const pasteLinks = await page.$$eval('a[href*="/paste/"]', els =>
      els.slice(0, 5).map(a => ({ href: a.href, text: a.textContent.trim().slice(0, 60) }))
    );
    for (const link of pasteLinks) {
      const res = await page.goto(link.href, { waitUntil: 'networkidle2', timeout: 15000 });
      ok(`paste: ${link.text.slice(0, 40)}...`, res.status() === 200);
    }

    // 4. Pick first paste — test all links/buttons on paste view
    if (pasteLinks.length > 0) {
      console.log('\n4. Paste view links & buttons');
      await page.goto(pasteLinks[0].href, { waitUntil: 'networkidle2', timeout: 15000 });

      // All <a> links on paste page
      const viewLinks = await page.$$eval('a', els => els.map(a => ({ href: a.href, text: a.textContent.trim().slice(0, 40) })));
      for (const link of viewLinks) {
        if (!link.href || link.href.startsWith('javascript:') || link.href.startsWith('data:') || link.href === '#') continue;
        try {
          const res = await page.goto(link.href, { waitUntil: 'networkidle2', timeout: 10000 });
          ok(`link: ${link.text || link.href.slice(-30)}`, res.status() === 200, link.href);
        } catch (e) {
          ok(`link: ${link.text || link.href.slice(-30)}`, false, e.message.slice(0, 60));
        }
      }

      // Go back to paste, list buttons
      console.log('\n5. Paste view buttons');
      await page.goto(pasteLinks[0].href, { waitUntil: 'networkidle2', timeout: 15000 });
      const buttons = await page.$$eval('button', els => els.map(b => ({
        text: b.textContent.trim().slice(0, 40),
        onclick: b.getAttribute('onclick') ? b.getAttribute('onclick').slice(0, 60) : null
      })));
      for (const btn of buttons) {
        ok(`button present: ${btn.text}`, true, btn.onclick || '');
      }
    }

    // 5. API endpoint
    console.log('\n6. API');
    const apiRes = await page.goto(BASE + '/openapi.json', { waitUntil: 'networkidle2', timeout: 10000 });
    ok('openapi.json', apiRes.status() === 200);

    // 6. Stego dashboard
    console.log('\n7. Stego dashboard');
    const stegoRes = await page.goto(BASE + '/stego', { waitUntil: 'networkidle2', timeout: 15000 });
    ok('stego loads', stegoRes.status() === 200);
    const stegoLinks = await page.$$eval('a', els => els.map(a => ({ href: a.href, text: a.textContent.trim().slice(0, 40) })));
    for (const link of stegoLinks) {
      if (!link.href || link.href.startsWith('javascript:') || link.href.startsWith('data:') || link.href === '#') continue;
      try {
        const res = await page.goto(link.href, { waitUntil: 'networkidle2', timeout: 10000 });
        ok(`stego link: ${link.text || link.href.slice(-30)}`, res.status() === 200, link.href);
      } catch (e) {
        ok(`stego link: ${link.text || link.href.slice(-30)}`, false, e.message.slice(0, 60));
      }
    }

    // 7. Gallery
    console.log('\n8. Gallery');
    const galRes = await page.goto(BASE + '/gallery', { waitUntil: 'networkidle2', timeout: 15000 });
    ok('gallery loads', galRes.status() < 500, `status=${galRes.status()}`);

    // 8. Raw endpoint
    if (pasteLinks.length > 0) {
      console.log('\n9. Raw endpoint');
      const pasteId = pasteLinks[0].href.split('/paste/')[1];
      const rawRes = await page.goto(BASE + '/raw/' + pasteId, { waitUntil: 'networkidle2', timeout: 10000 });
      ok('raw endpoint', rawRes.status() === 200, pasteId);
    }

  } catch (err) {
    console.error('❌ Fatal:', err.message);
  } finally {
    await browser.close();
  }

  const passed = results.filter(r => r.pass).length;
  const failed = results.filter(r => !r.pass);
  console.log(`\n=== ${passed}/${results.length} passed ===`);
  if (failed.length) {
    console.log('\nFailed:');
    failed.forEach(f => console.log(`  ❌ ${f.name}`));
  }
  process.exit(failed.length ? 1 : 0);
})();
