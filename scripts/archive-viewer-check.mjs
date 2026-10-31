// Drive the archive viewer in a real browser: open a shared pattern link,
// assert the page re-applies it, then press Split and follow the selection.
//
//   CHROME=/nix/store/.../bin/chromium \
//     node scripts/archive-viewer-check.mjs <base> <session_id> <pattern>
//
// <base> must be the URL the page is served from (its BASE_PATH included), e.g.
// https://solana.solfunmeme.com/pastebin/beta — the page fetches its own
// /archive-pattern/<id> relative to that prefix. CHROME_ARGS is `;`-separated and
// turns `|` into a space, for flags whose value needs one (host-resolver rules).
// Exit code is 0 only when the pattern applied to at least one row and Split landed.
import puppeteer from "puppeteer-core";

const [base, sid, pattern = "src/**/*.rs"] = process.argv.slice(2);
const url = `${base}/browse-archive/${sid}?pattern=${encodeURIComponent(pattern)}`;

const browser = process.env.BROWSER_URL
  ? await puppeteer.connect({ browserURL: process.env.BROWSER_URL, defaultViewport: null })
  : await puppeteer.launch({
      executablePath: process.env.CHROME,
      headless: true,
      args: ["--no-sandbox", "--disable-dev-shm-usage", ...(process.env.CHROME_ARGS ? process.env.CHROME_ARGS.split(";").map((a) => a.replaceAll("|", " ")) : [])],
    });
const page = await browser.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push("pageerror: " + String(e)));
page.on("console", (m) => {
  if (m.type() === "error") errors.push("console: " + m.text());
});

page.on("response", (r) => { if (r.status() >= 400) errors.push(`http ${r.status()} ${r.url()}`); });

try {
  await page.goto(url, { waitUntil: "networkidle2", timeout: 60000 });
  await page.waitForFunction(
    () => /files match/.test(document.getElementById("patternStatus")?.textContent || ""),
    { timeout: 30000 },
  );

  const applied = await page.evaluate(() => ({
    input: document.getElementById("patternInput").value,
    status: document.getElementById("patternStatus").textContent,
    checked: [...document.querySelectorAll(".file-select")].filter((c) => c.checked).map((c) => c.value),
    checkboxCount: document.querySelectorAll(".file-select").length,
  }));
  console.log("URL pattern applied:", JSON.stringify(applied, null, 2));
  if (applied.input !== pattern) {
    throw new Error(`pattern input is ${JSON.stringify(applied.input)}, expected ${JSON.stringify(pattern)}`);
  }
  if (applied.checked.length === 0) {
    throw new Error(`pattern ${JSON.stringify(pattern)} selected no rows`);
  }

  await Promise.all([
    page.waitForNavigation({ waitUntil: "networkidle2", timeout: 90000 }),
    page.click("#splitBtn"),
  ]);
  const landed = page.url();
  const heading = await page.evaluate(() => document.querySelector("h1")?.textContent?.trim() ?? "");
  console.log("after Split ->", landed);
  console.log("landing heading:", heading.slice(0, 120));
  console.log("page errors:", errors.length ? errors : "none");
} finally {
  await browser.close();
}
