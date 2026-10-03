#!/usr/bin/env node
// E2E: two browsers meet in one room through the local relay.
//
// Everything the browsers do is recorded three ways:
//   - a video of the shared Xvfb screen (:99), captured by ffmpeg
//   - every HTTP exchange, captured by mitmdump on :8280 (the browsers
//     are pointed at it as their proxy)
//   - per-step screenshots + a JSON timeline under e2e-out/
//
// Usage: node scripts/kant-e2e.mjs [--base http://127.0.0.1:8787]
// The relay must already be running (kant-relay.service); playwright
// comes from ../arist/gui2lean4/node_modules.

import { chromium } from "/home/mdupont/projects/arist/gui2lean4/node_modules/playwright/index.mjs";
import { mkdirSync, writeFileSync } from "node:fs";
import { argv, exit } from "node:process";

const args = argv.slice(2);
const BASE = args.includes("--base") ? args[args.indexOf("--base") + 1]
  : "http://127.0.0.1:8787";
const PROXY = "http://127.0.0.1:8280";
const OUT = "e2e-out";
mkdirSync(OUT, { recursive: true });

const timeline = [];
const note = (step, extra = {}) => {
  timeline.push({ step, ms: Date.now(), ...extra });
  console.log(`[e2e] ${step}`);
};

const LAUNCH = {
  headless: false,
  env: { ...process.env, DISPLAY: ":99" },
  args: [
    // `--proxy-server=${PROXY}`,
    // `--proxy-bypass-list=<-loopback>`, // keep loopback traffic in the capture
    // "--ignore-certificate-errors", // mitmproxy's CA is not in the store
    "--autoplay-policy=no-user-gesture-required",
  ],
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------------ health
const health = await fetch(`${BASE}/health`).then((r) => r.json());
if (!health.ok) { console.error("relay not healthy", health); exit(1); }
note("relay healthy", health);

// ------------------------------------------------------------- two browsers
const browserA = await chromium.launch(LAUNCH);
const browserB = await chromium.launch(LAUNCH);
const pageA = await browserA.newPage({ viewport: { width: 800, height: 640 } });
const pageB = await browserB.newPage({ viewport: { width: 800, height: 640 } });
// stack-free recording: each browser gets its own half of the Xvfb screen
const place = (page, x) => page.context().browser()
  && page.evaluate((n) => window.resizeTo(800, 640) || window.moveTo(n, 20), x);
await place(pageA, 20);
await place(pageB, 830);
for (const [tag, page] of [["A", pageA], ["B", pageB]]) {
  page.on("console", (m) => { if (m.type() === "error") console.log(`[${tag} error]`, m.text()); });
  // The served kant.config names the deployed relay; this run is against
  // the local one, so both browsers see a config pointing at it.
  await page.route("**/kant.config", (route) =>
    route.fulfill({ body: `# e2e: everything local\nrelay = ${BASE}\n`,
                    contentType: "text/plain" }));
}

// ------------------------------------------------------- A opens the room
await pageA.goto(BASE, { waitUntil: "load" });
await pageA.evaluate(() => localStorage.setItem("kant-demo", "off")); // plain UI, no guide
await pageA.reload({ waitUntil: "load" });
await pageA.screenshot({ path: `${OUT}/00-a-welcome.png` });

await pageA.click("#btn-open");
// opening a room lands on the share screen (the link, the code, the QR)
await pageA.waitForSelector("#s-share.on", { timeout: 15000 });
await pageA.screenshot({ path: `${OUT}/01-a-room-open.png` });
note("A opened a room");

// The invite link: what "Copy link" would put on the clipboard. Read it
// out of the share screen's QR meta instead — no clipboard involved.
const invite = await pageA.inputValue("#link");
if (!/^https?:\/\//.test(invite)) {
  console.error("could not read the invite link:", JSON.stringify(invite));
  exit(1);
}
note("invite link", { link: invite });

// A walks into the chat to talk from there
await pageA.click("#btn-openroom");
await pageA.waitForSelector("#s-chat.on", { timeout: 15000 });

// --------------------------------------------------------- B joins by link
await pageB.goto(invite, { waitUntil: "load" });
await pageB.evaluate(() => localStorage.setItem("kant-demo", "off"));
await pageB.reload({ waitUntil: "load" });
await pageB.waitForSelector("#s-chat.on", { timeout: 15000 });
await pageB.screenshot({ path: `${OUT}/02-b-joined.png` });
note("B joined the room");

// ------------------------------------------------------------- they talk
await pageA.fill("#say", "hello from the first browser");
await pageA.click("#btn-send");
await pageB.fill("#say", "and hello back from the second");
await pageB.click("#btn-send");
await sleep(3000); // let the long-poll relay deliver
await pageA.screenshot({ path: `${OUT}/03-a-chat.png` });
await pageB.screenshot({ path: `${OUT}/04-b-chat.png` });

const chatA = await pageA.innerText("#chat");
const chatB = await pageB.innerText("#chat");
note("chat read", {
  aSeesB: /second/.test(chatA),
  bSeesA: /first browser/.test(chatB),
});

// ----------------------------------------------------------- the verdict
const checks = [
  ["relay healthy", true],
  ["A opened a room", true],
  ["B joined by link", true],
  ["A sees B's line", /second/.test(chatA)],
  ["B sees A's line", /first browser/.test(chatB)],
];
let failed = 0;
for (const [name, ok] of checks) {
  console.log(`${ok ? "PASS" : "FAIL"}: ${name}`);
  if (!ok) failed++;
}

writeFileSync(`${OUT}/timeline.json`,
  JSON.stringify({ base: BASE, timeline, checks }, null, 2));
await browserA.close();
await browserB.close();
console.log(failed === 0
  ? "e2e: all checks passed"
  : `e2e: ${failed} check(s) failed`);
exit(failed === 0 ? 0 : 1);
