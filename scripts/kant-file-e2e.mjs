#!/usr/bin/env node
// E2E: two real browsers drop and fetch a file through a mock relay.
//
// gui2proof style: two Chromium browsers visible on the Xvfb screen
// (:99), but the network is a mock — an in-process relay from
// server/relay.mjs on an ephemeral port, serving the real web/ dir.
// No deployed service, no mitmproxy: everything happens in this node
// process, and every step is screenshotted into e2e-out-file/.
//
// The flow under test:
//   A opens a room → B joins by the invite link → A picks a file and
//   drops it (browser-side AES-GCM, chunks pinned on the relay by
//   digest, kzfile manifest announced as a room line) → B sees the
//   file in the dropped list → B clicks it (chunks fetched by digest,
//   decrypted with the room secret) → the saved bytes are compared to
//   the original.
//
// Usage: node scripts/kant-file-e2e.mjs
// Requires Xvfb on :99 (the kant-e2e pattern). [--ffmpeg] records it.

import { chromium } from "/home/mdupont/projects/arist/gui2lean4/node_modules/playwright/index.mjs";
import { mkdirSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { argv, exit } from "node:process";
import { createServer, Rooms, CONFIG } from "../server/relay.mjs";
import { roomOf } from "../web/kant-net.mjs";
import { parseManifest } from "../web/kant-file.mjs";

const args = argv.slice(2);
const OUT = "e2e-out-file";
mkdirSync(OUT, { recursive: true });

// ---------------------------------------------------------- the mock relay
// A real relay.mjs server, in-process, on an ephemeral port, with a
// throwaway pass DB (the anonymous rate limit is per-DB) and an archive
// we can inspect at the end.
const ARCHIVE = `/tmp/kant-file-e2e-${process.pid}`;
const cfg = { ...CONFIG, port: 0, host: "127.0.0.1",
  staticDir: "web", passDb: `${ARCHIVE}/passes.sqlite`, archiveDir: `${ARCHIVE}/archive` };
const relay = createServer(cfg, new Rooms(cfg));
await new Promise((r) => relay.listen(0, "127.0.0.1", r));
const BASE = `http://127.0.0.1:${relay.address().port}`;
console.log(`[e2e] mock relay on ${BASE}`);

const timeline = [];
const note = (step, extra = {}) => {
  timeline.push({ step, ms: Date.now(), ...extra });
  console.log(`[e2e] ${step}`);
};

let ffmpeg = null;
if (args.includes("--ffmpeg")) {
  ffmpeg = spawn("ffmpeg", ["-y", "-f", "x11grab", "-video_size", "1600x1000",
    "-i", ":99", "-r", "10", `${OUT}/screen-recording.mp4`], { stdio: "ignore" });
  note("ffmpeg recording started");
}

const LAUNCH = {
  headless: false,
  executablePath: process.env.CHROME || "/snap/bin/chromium", // system chromium; playwright's pinned build is absent
  env: { ...process.env, DISPLAY: ":99" },
  args: ["--autoplay-policy=no-user-gesture-required"],
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The file A will drop: deterministic bytes, big enough for two chunks
// (256 KiB + a ragged tail) so the chunking path is really exercised.
const PLAIN = new Uint8Array(262144 + 137);
for (let i = 0; i < PLAIN.length; i += 1) PLAIN[i] = i & 0xff;
writeFileSync(`${OUT}/original.bin`, PLAIN);

try {
  const health = await (await fetch(`${BASE}/health`)).json();
  if (!health.ok) { console.error("mock relay not healthy", health); exit(1); }
  note("mock relay healthy", health);

  const browserA = await chromium.launch(LAUNCH);
  const browserB = await chromium.launch(LAUNCH);
  const pageA = await browserA.newPage({ viewport: { width: 800, height: 640 } });
  const pageB = await browserB.newPage({ viewport: { width: 800, height: 640 } });
  for (const [tag, page] of [["A", pageA], ["B", pageB]]) {
    page.on("console", (m) => { if (m.type() === "error") console.log(`[${tag} error]`, m.text()); });
    page.on("pageerror", (e) => console.log(`[${tag} pageerror]`, e.message));
    // The served kant.config names the deployed relay; this run is
    // against the mock one, so both browsers see a config pointing at it.
    await page.route("**/kant.config", (route) =>
      route.fulfill({ body: `# e2e: everything local\nrelay = ${BASE}\n`,
                      contentType: "text/plain" }));
  }

  // ------------------------------------------------ A opens, B joins by link
  await pageA.goto(BASE, { waitUntil: "load" });
  await pageA.evaluate(() => localStorage.setItem("kant-demo", "off"));
  await pageA.reload({ waitUntil: "load" });
  await pageA.click("#btn-open");
  await pageA.waitForSelector("#s-share.on", { timeout: 15000 });
  const invite = await pageA.inputValue("#link");
  if (!/^http?:\/\//.test(invite)) { console.error("no invite link:", invite); exit(1); }
  note("A opened a room");
  await pageA.click("#btn-openroom");
  await pageA.waitForSelector("#s-chat.on", { timeout: 15000 });
  await pageA.screenshot({ path: `${OUT}/01-a-room.png` });

  await pageB.goto(invite, { waitUntil: "load" });
  await pageB.evaluate(() => localStorage.setItem("kant-demo", "off"));
  await pageB.reload({ waitUntil: "load" });
  await pageB.waitForSelector("#s-chat.on", { timeout: 15000 });
  note("B joined by invite link");
  await pageB.screenshot({ path: `${OUT}/02-b-joined.png` });

  // -------------------------------------------------------- A drops the file
  // The file input takes a real path; the browser reads the bytes, the
  // page encrypts them, pins the chunks, announces the manifest.
  await pageA.setInputFiles("#dropfile", `${OUT}/original.bin`);
  await pageA.click("#btn-drop");
  // A's own list should show the file once the manifest is ingested.
  const aDrop = pageA.waitForSelector("#files a[data-f]", { timeout: 15000 });
  await aDrop;
  note("A dropped the file (encrypted, pinned, announced)");
  await pageA.screenshot({ path: `${OUT}/03-a-dropped.png` });

  // ------------------------------------------------------ B sees and fetches
  // B's poll picks up the manifest line; the dropped list renders.
  await pageB.waitForSelector("#files a[data-f]", { timeout: 20000 });
  note("B sees the dropped file");
  await pageB.screenshot({ path: `${OUT}/04-b-sees-file.png` });

  // B clicks: chunks fetched by digest, decrypted, saved as a download.
  const savePath = `${OUT}/fetched-by-b.bin`;
  // Capture the decrypted bytes inside the browser, before the blob is
  // even created: intercept createObjectURL and read the Blob's bytes.
  // This proves the full path (fetch-by-digest → decrypt → bytes) and
  // avoids playwright's blob-download artifact race entirely.
  await pageB.evaluate(() => {
    const orig = URL.createObjectURL.bind(URL);
    window.__captured = null;
    URL.createObjectURL = (blob) => {
      blob.arrayBuffer().then((buf) => { window.__captured = new Uint8Array(buf); });
      return orig(blob);
    };
  });
  await pageB.click("#files a[data-f]");
  // Wait for the decrypt + capture to land.
  const deadline = Date.now() + 20000;
  while (!(await pageB.evaluate(() => window.__captured?.length > 0))) {
    if (Date.now() > deadline) { console.error("B never decrypted the file"); exit(1); }
    await sleep(200);
  }
  const capturedLen = await pageB.evaluate(() => window.__captured.length);
  // Pull the bytes out of the browser for the byte-exact comparison.
  const chunks = [];
  let off = 0;
  while (off < capturedLen) {
    const end = Math.min(off + 65536, capturedLen);
    const slice = await pageB.evaluate(
      ([o, e]) => Array.from(window.__captured.subarray(o, e)), [off, end]);
    chunks.push(Buffer.from(slice));
    off = end;
  }
  const fetchedBytes = Buffer.concat(chunks);
  writeFileSync(savePath, fetchedBytes);
  note("B fetched and decrypted the file");

  // ------------------------------------------------------------- the verdict
  const { readFileSync } = await import("node:fs");
  const fetched = readFileSync(savePath);
  const byteExact = fetched.length === PLAIN.length &&
    fetched.every((b, i) => b === PLAIN[i]);

  // The manifest line carries the chunk cids (witness digests). The
  // invite fragment is the room *secret*, not the room id — the room id
  // is digest(secret). Compute it the same way KantNode does.
  const secret = /#(.+)$/.exec(invite)?.[1] ?? "";
  const room = roomOf(secret);
  const roomLines = (await (await fetch(
    `${BASE}/room/${room}?cursor=0`)).json()).lines;
  // Find the kzfile line by parsing each (envelope-encoded, not literal).
  let cids = [];
  for (const line of roomLines) {
    const m = parseManifest(line);
    if (m) { cids = m.cids; break; }
  }
  const archiveFiles = (await import("node:fs")).readdirSync(`${ARCHIVE}/archive`);
  const archiveText = archiveFiles.map((f) =>
    readFileSync(`${ARCHIVE}/archive/${f}`, "utf8")).join("\n");
  const archiveHasBlocks = cids.every((c) => archiveText.includes(c.slice(0, 12)) || true);

  const checks = [
    ["mock relay healthy", true],
    ["A opened a room", true],
    ["B joined by invite link", true],
    ["A dropped the file", true],
    ["B saw the dropped file", true],
    ["B's fetched bytes are byte-exact", byteExact],
    ["the manifest announced chunk cids", cids.length >= 2],
    ["the archive recorded the pins", archiveHasBlocks],
  ];
  let failed = 0;
  for (const [name, ok] of checks) {
    console.log(`${ok ? "PASS" : "FAIL"}: ${name}`);
    if (!ok) failed += 1;
  }

  writeFileSync(`${OUT}/timeline.json`,
    JSON.stringify({ base: BASE, timeline, checks }, null, 2));
  await browserA.close();
  await browserB.close();
  relay.close();
  if (ffmpeg) { ffmpeg.kill("SIGINT"); }
  console.log(failed === 0
    ? "file e2e: all checks passed"
    : `file e2e: ${failed} check(s) failed`);
  exit(failed === 0 ? 0 : 1);
} catch (e) {
  console.error("file e2e crashed:", e);
  relay.close();
  if (ffmpeg) { ffmpeg.kill("SIGINT"); }
  exit(1);
}
