#!/usr/bin/env node
// scripts/p2p-gui-e2e.mjs — gui2proof e2e for the kant p2p webapp.
//
// Two real Chromium browsers (Xvfb :99) meet in one room through the DEPLOYED
// edge (https://solana.solfunmeme.com/p2p-relay/) — the full production path:
//   nginx TLS → /p2p-relay/ → kant-p2p-relay.service → relay.mjs → room log
// and run the app as a user would: join, publish text, receive + fetch +
// CID-verify, run the proved-kernel experiment, compare room digests.
// Recorded like the kant-e2e pattern: per-step screenshots, JSON timeline,
// and an ffmpeg X11 capture of the shared Xvfb screen.
//
// Usage: node scripts/p2p-gui-e2e.mjs [--base https://solana.solfunmeme.com/p2p-relay] [--ffmpeg]
import { chromium } from "/home/mdupont/projects/arist/gui2lean4/node_modules/playwright/index.mjs";
import { mkdirSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { argv, exit, env } from "node:process";

const args = argv.slice(2);
const BASE = args.includes("--base") ? args[args.indexOf("--base") + 1]
  : "https://solana.solfunmeme.com/p2p-relay";
const ROOM = "gui2proof-" + Math.random().toString(36).slice(2, 8);
const OUT = "e2e-out-p2p";
mkdirSync(OUT, { recursive: true });

const timeline = [];
const note = (step, extra = {}) => {
  timeline.push({ step, ms: Date.now(), ...extra });
  console.log(`[e2e] ${step}`);
};

const LAUNCH = {
  headless: false, // gui2proof style: visible on the Xvfb screen so ffmpeg can record it
  executablePath: process.env.CHROME || "/snap/bin/chromium", // system chromium; playwright's pinned build is absent
  env: { ...process.env, DISPLAY: ":99" },
  args: ["--autoplay-policy=no-user-gesture-required", "--ignore-certificate-errors"],
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// optional screen recording (ffmpeg on the Xvfb display), kant-e2e style
let ffmpeg = null;
if (args.includes("--ffmpeg")) {
  ffmpeg = spawn("ffmpeg", ["-y", "-f", "x11grab", "-video_size", "1600x1000",
    "-i", ":99", "-r", "10", `${OUT}/screen-recording.mp4`], { stdio: "ignore" });
  note("ffmpeg recording started");
}

const deadline = (ms, what) => {
  const t = Date.now() + ms;
  return {
    tick: async () => { if (Date.now() > t) throw new Error(`timeout: ${what}`); await sleep(200); },
  };
};

try {
  const health = await (await fetch(`${BASE}/health`)).json();
  if (!health.ok) { console.error("edge relay not healthy", health); exit(1); }
  note("edge relay healthy", health);

  const browserA = await chromium.launch(LAUNCH);
  const browserB = await chromium.launch(LAUNCH);
  const pageA = await browserA.newPage({ viewport: { width: 780, height: 620 } });
  const pageB = await browserB.newPage({ viewport: { width: 780, height: 620 } });
  for (const [tag, page] of [["A", pageA], ["B", pageB]]) {
    page.on("console", (m) => { if (m.type() === "error") console.log(`[${tag} console.error]`, m.text()); });
    page.on("pageerror", (e) => console.log(`[${tag} pageerror]`, e.message));
  }

  // 1. both open the app
  await pageA.goto(`${BASE}/p2p.html`, { waitUntil: "load" });
  await pageB.goto(`${BASE}/p2p.html`, { waitUntil: "load" });
  note("both browsers loaded p2p.html");
  await pageA.screenshot({ path: `${OUT}/01-a-loaded.png` });

  // 2. join the same room as two peers
  await pageA.fill("#room", ROOM);
  await pageA.fill("#peer", "alice");
  await pageB.fill("#room", ROOM);
  await pageB.fill("#peer", "bob");
  await pageA.click("#join");
  await pageB.click("#join");
  const joined = deadline(15_000, "join status");
  while (!(await pageA.locator("#status .ok").count())) await joined.tick();
  note(`both joined room ${ROOM}`);
  await pageA.screenshot({ path: `${OUT}/02-joined.png` });
  await pageB.screenshot({ path: `${OUT}/02-b-joined.png` });

  // 3. alice publishes text → kzcid record (embedded fallback: no kubo on :5001? probe decides)
  await pageA.fill("#text", `gui2proof artifact ${new Date().toISOString()}`);
  await pageA.click("#pub-text");
  const published = deadline(15_000, "publish status");
  while (!(await pageA.locator("#pub-status .ok").count())) await published.tick();
  const pubLine = await pageA.locator("#pub-status").innerText();
  note(`alice published: ${pubLine.trim()}`);
  await pageA.screenshot({ path: `${OUT}/03-published.png` });

  // 4. bob sees the artifact row and fetches it (CID-verified)
  const row = deadline(20_000, "artifact row on bob");
  while (!(await pageB.locator("#arts tbody tr").count())) await row.tick();
  await pageB.click("#arts tbody tr:first-child [data-act='get']");
  const gotLog = deadline(15_000, "fetch log line");
  let fetchedOk = false;
  while (Date.now() < gotLog.t || true) {
    const txt = await pageB.locator("#log").innerText();
    if (/fetched .* via (room|ipfs)/.test(txt)) { fetchedOk = true; break; }
    if (/fetch failed/.test(txt)) break;
    await sleep(300);
  }
  if (!fetchedOk) { console.error("bob fetch failed"); exit(1); }
  note("bob fetched and CID-verified the artifact");
  await pageB.screenshot({ path: `${OUT}/04-b-fetched.png` });

  // 5. alice runs the proved-kernel experiment over the published CIDs
  await pageA.click("#exp-merge");
  const expOk = deadline(15_000, "merge-cids result");
  let merged = "";
  while (Date.now() < expOk.t + 1) {
    const t = await pageA.locator("#exp-status").innerText();
    if (/merged = \d+/.test(t)) { merged = t.trim(); break; }
    await sleep(300);
  }
  if (!merged) { console.error("experiment did not produce a merged value"); exit(1); }
  note(`experiment: ${merged}`);
  await pageA.screenshot({ path: `${OUT}/05-experiment.png` });

  // 6. room digest agreement between the two peers (same published set)
  await pageA.click("#exp-digest");
  await sleep(1500);
  await pageB.click("#exp-digest");
  const digests = [];
  for (const p of [pageA, pageB]) {
    const t = await p.locator("#exp-status").innerText();
    digests.push(t);
  }
  note(`digests: A=${digests[0].trim()} B=${digests[1].trim()}`);
  await pageA.screenshot({ path: `${OUT}/06-digests.png` });

  const da = /digest = (\d+)/.exec(digests[0])?.[1];
  const dbb = /digest = (\d+)/.exec(digests[1])?.[1];
  if (!da || da !== dbb) { console.error(`digest mismatch: ${digests}`); exit(1); }
  note("room digests agree — both peers hold the same artifact set");

  await browserA.close();
  await browserB.close();
  writeFileSync(`${OUT}/timeline.json`, JSON.stringify({ room: ROOM, base: BASE, timeline }, null, 2));
  console.log("GUI2PROOF E2E PASS");
  exit(0);
} catch (e) {
  console.error("E2E FAILED:", e.message);
  writeFileSync(`${OUT}/timeline.json`, JSON.stringify({ room: ROOM, base: BASE, timeline, error: e.message }, null, 2));
  exit(1);
} finally {
  if (ffmpeg) { ffmpeg.kill("SIGINT"); }
}
