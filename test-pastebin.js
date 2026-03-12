#!/usr/bin/env node
// Kant Pastebin Microservice Tests
const puppeteer = require('puppeteer');

const PORT = process.env.TEST_PORT || 9191;
const BASE_URL = `http://localhost:${PORT}`;

(async () => {
  console.log('=== Kant Pastebin Tests ===');
  console.log(`URL: ${BASE_URL}`);
  
  const browser = await puppeteer.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  const results = [];

  try {
    // Test 1: Home Page
    console.log('\n1. Home Page Load');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2' });
    const title = await page.title();
    console.log(`   Title: ${title}`);
    results.push({ test: 'home', pass: title.includes('Kant Pastebin') });

    // Test 2: Form Elements
    console.log('\n2. Form Elements');
    const textarea = await page.$('#content');
    const titleInput = await page.$('#title');
    const button = await page.$('button[type="submit"]');
    const hasForm = textarea && titleInput && button;
    console.log(`   Form: ${hasForm ? '✅' : '❌'}`);
    results.push({ test: 'form', pass: hasForm });

    // Test 3: Create Paste
    console.log('\n3. Create Paste');
    await page.type('#title', 'Test Paste');
    await page.type('#content', 'Test content from automated test');
    await page.click('button[type="submit"]');
    await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 5000 });
    const pasteUrl = page.url();
    const isPastePage = pasteUrl.includes('/paste/');
    console.log(`   URL: ${pasteUrl}`);
    console.log(`   Created: ${isPastePage ? '✅' : '❌'}`);
    results.push({ test: 'create', pass: isPastePage });

    // Test 4: Access Commands
    console.log('\n4. Access Commands');
    const ipfsCmd = await page.$eval('.cmd', el => el.textContent);
    const hasCommands = ipfsCmd && (ipfsCmd.includes('ipfs') || ipfsCmd.includes('No IPFS'));
    console.log(`   Commands: ${hasCommands ? '✅' : '❌'}`);
    results.push({ test: 'commands', pass: hasCommands });

    // Test 5: Browse
    console.log('\n5. Browse Page');
    await page.goto(`${BASE_URL}/browse`, { waitUntil: 'networkidle2' });
    const browseTitle = await page.title();
    const hasBrowse = browseTitle.includes('Browse');
    console.log(`   Browse: ${hasBrowse ? '✅' : '❌'}`);
    results.push({ test: 'browse', pass: hasBrowse });

    // Test 6: OpenAPI
    console.log('\n6. OpenAPI');
    const apiRes = await page.goto(`${BASE_URL}/openapi.json`, { waitUntil: 'networkidle2' });
    const apiJson = await apiRes.json();
    const hasOpenAPI = apiJson.openapi === '3.0.0';
    console.log(`   OpenAPI: ${hasOpenAPI ? '✅' : '❌'}`);
    results.push({ test: 'openapi', pass: hasOpenAPI });

    // Summary
    console.log('\n=== Summary ===');
    const passed = results.filter(r => r.pass).length;
    const total = results.length;
    console.log(`Passed: ${passed}/${total}`);
    
    if (passed === total) {
      console.log('✅ All tests passed!');
      process.exit(0);
    } else {
      console.log('❌ Some tests failed');
      process.exit(1);
    }

  } catch (err) {
    console.error('❌ Test error:', err.message);
    process.exit(1);
  } finally {
    await browser.close();
  }
})();
