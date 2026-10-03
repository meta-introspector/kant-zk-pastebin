#!/usr/bin/env node
// p2p-browser-check.mjs — the p2p client in a real browser, against a deployed
// origin.
//
//   node scripts/p2p-browser-check.mjs https://host/prefix
//
// Loads the p2p page in headless Chromium, fails on any console error or page
// error, then asks the page to plan a multi-chunk artifact with the module it
// actually shipped with. That covers the whole deployed chain: HTML -> module
// graph -> wasm-bindgen glue -> .wasm fetch -> Rust core -> dag-pb CID.
//
// Checks, in a real browser rather than under Node:
//   * the page loads clean (no console/page errors, no failed requests)
//   * the Rust wasm core is the live one, not the JS fallback
//   * a 400 KB artifact plans into 2 leaves under a dag-pb root
//   * that root equals the CID kubo computes for the same bytes
//
// The expected CID was captured from `ipfs add --cid-version=1 --raw-leaves`
// on kubo 0.40.1 over byte[i] = i % 251, so this fails if the deployed build
// ever diverges from real IPFS rather than merely from itself.
//
// Exits 0 only if everything holds.

import { createRequire } from "node:module";
import { mkdirSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const target = process.argv[2];
if (!target) {
  console.error("usage: node scripts/p2p-browser-check.mjs https://host[/prefix]");
  process.exit(2);
}
const base = target.replace(/\/+$/, "");
const p2pUrl = `${base}/p2p.html`;
const shotDir = path.join(root, "data", "browser-check");
mkdirSync(shotDir, { recursive: true });

// Captured from `ipfs add --cid-version=1 --raw-leaves -Q` on kubo 0.40.1.
// PROBE_262145: 262145 bytes of i % 251 — the first size needing a root.
const PROBE_262145 = "bafybeiexg2oqkfnj56l7fcmawswqbijt5shq4b5rg6a546uwpkqqzwjioi";
// ZIP_400K: 400000 bytes of the same xorshift the page below reproduces.
const ZIP_400K = "bafybeih5cpu2cwi4j4k2aqcpipuadf2rnh2e3o5siv3k64ydphq2iu7zqa";

const require = createRequire(import.meta.url);

// Playwright and its downloaded Chromium have to agree on a build number, and
// this repo's copy and the gui2proof copy are not the same version. So the
// module and the browser are both overridable, and launching falls back to a
// system Chromium when the bundled one is not installed.
//
//   PLAYWRIGHT_MODULE=/path/to/node_modules/playwright
//   PLAYWRIGHT_CHROMIUM=/usr/bin/chromium
function loadPlaywright() {
  const candidates = [
    process.env.PLAYWRIGHT_MODULE,
    path.join(root, "node_modules", "playwright"),
  ].filter(Boolean);
  let last;
  for (const c of candidates) {
    try { return require(c); } catch (e) { last = e; }
  }
  throw last;
}
const { chromium } = loadPlaywright();

async function launch() {
  const opts = { headless: true };
  const exe = process.env.PLAYWRIGHT_CHROMIUM;
  if (exe) opts.executablePath = exe;
  try {
    return await chromium.launch(opts);
  } catch (e) {
    // No bundled browser for this build — use whatever Chromium is installed.
    for (const fallback of ["/snap/bin/chromium", "/usr/bin/chromium", "/usr/bin/chromium-browser"]) {
      if (!existsSync(fallback)) continue;
      console.log(`bundled chromium unavailable (${String(e).split("\n")[0]}); using ${fallback}`);
      return chromium.launch({ headless: true, executablePath: fallback });
    }
    throw e;
  }
}

const browser = await launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

const consoleErrors = [];
const pageErrors = [];
const failedRequests = [];
page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
page.on("pageerror", (e) => pageErrors.push(String(e)));
page.on("requestfailed", (r) =>
  failedRequests.push(`${r.url()} ${r.failure()?.errorText ?? "failed"}`));
page.on("response", (r) => {
  if (r.status() >= 400) failedRequests.push(`${r.url()} HTTP ${r.status()}`);
});

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

console.log(`opening ${p2pUrl}`);
const resp = await page.goto(p2pUrl, { waitUntil: "networkidle", timeout: 60_000 });
check("page responds 2xx", resp && resp.ok(), `HTTP ${resp?.status()}`);

// Give the module graph a moment to finish evaluating in the page.
await page.waitForTimeout(2_000);

// Ask the page which core it is running. The page reports this itself.
//
// The import specifier is relative on purpose: the app is served under a path
// prefix on some origins (nginx mounts it at /p2p-relay/), and an absolute
// "/kant-ipfs.mjs" would silently resolve against the host root instead.
const coreReport = await page.evaluate(async () => {
  const out = { wasmLoaded: false, core: "unknown" };
  try {
    const mod = await import("./kant-ipfs.mjs");
    const core = await mod.wasmOnce?.();
    out.wasmLoaded = Boolean(core);
    out.core = core ? (typeof core.wasm_unixfs_cid === "function" ? "wasm" : "wasm-no-unixfs")
                    : "js-fallback";
    out.hasUnixfs = typeof mod.unixfsPlanOf === "function";
  } catch (e) {
    out.error = String(e);
  }
  return out;
});
check("Rust wasm core is live", coreReport.wasmLoaded, JSON.stringify(coreReport));

// Which kernel copy actually won: a fetched file or the embedded fallback.
// Both are fine, but they differ per origin and it is worth knowing.
const kernel = await page.evaluate(async () => {
  try {
    const m = await import("./kant-wasm.mjs");
    const k = await m.loadKernel();
    return { ok: true, source: String(k.source ?? "unknown"), urls: m.KERNEL_URLS.map((u) => u.href) };
  } catch (e) { return { ok: false, err: String(e).slice(0, 160) }; }
});
check("proved kernel loads", kernel.ok, kernel.ok ? kernel.source : kernel.err);
check("wasm core exposes unixfs", coreReport.core === "wasm");

// The real point: a multi-chunk artifact planned inside the browser.
const plan = await page.evaluate(async () => {
  const mod = await import("./kant-ipfs.mjs");
  const mk = (n) => Uint8Array.from({ length: n }, (_, i) => i % 251);
  const p262145 = await mod.unixfsPlanOf(mk(262145));
  const bytes = new Uint8Array(400000);
  let seed = 0x2545f491;
  for (let i = 0; i < bytes.length; i += 1) {
    seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0;
    bytes[i] = seed & 0xff;
  }
  const p400k = await mod.unixfsPlanOf(bytes);
  return {
    small: { root: p262145.root, chunked: p262145.chunked, leaves: p262145.leaves.length },
    big: {
      root: p400k.root,
      chunked: p400k.chunked,
      leaves: p400k.leaves.length,
      total: p400k.leaves.reduce((a, l) => a + l.size, 0),
    },
  };
});

check("262145B plans as 2 leaves", plan.small.leaves === 2 && plan.small.chunked,
  `${plan.small.leaves} leaves`);
check("262145B CID matches kubo", plan.small.root === PROBE_262145, plan.small.root);
check("400000B plans as 2 leaves", plan.big.leaves === 2 && plan.big.chunked,
  `${plan.big.leaves} leaves`);
check("400000B leaves sum to the size", plan.big.total === 400000, `${plan.big.total}`);
check("400000B root matches kubo", plan.big.root === ZIP_400K, plan.big.root);
check("400000B root is a dag-pb CID", plan.big.root.startsWith("bafybei"), plan.big.root);

// No request for the artifact bytes should have been made; this is all local.
check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 3).join(" | "));
check("no page errors", pageErrors.length === 0, pageErrors.slice(0, 3).join(" | "));
check("no failed requests", failedRequests.length === 0, failedRequests.slice(0, 3).join(" | "));

await page.screenshot({ path: path.join(shotDir, "p2p-browser-check.png"), fullPage: true });
await browser.close();

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} browser checks passed`);
console.log(`artifact: ${path.join(shotDir, "p2p-browser-check.png")}`);
if (failed.length) {
  console.error("FAILED:", failed.map((f) => f.name).join(", "));
  process.exit(1);
}
