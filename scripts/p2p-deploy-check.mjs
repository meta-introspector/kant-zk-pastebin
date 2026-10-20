#!/usr/bin/env node
// Load the deployed p2p page in a real browser and check the three things
// that only a browser can answer: does the wasm core actually instantiate,
// do the IPFS endpoints resolve same-origin, and does the CID it computes
// match the JS/kubo contract.
import { chromium } from "/home/mdupont/projects/arist/gui2lean4/node_modules/playwright/index.mjs";
import { exit } from "node:process";

const URL_ = process.argv[2] || "https://solana.solfunmeme.com/pastebin-p2p/";

const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROME || "/snap/bin/chromium",
  env: { ...process.env, DISPLAY: undefined },
  args: ["--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"],
});
const page = await browser.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
page.on("console", (m) => { if (m.type() === "error") errors.push(`console: ${m.text()}`); });
page.on("requestfailed", (r) => errors.push(`reqfail: ${r.url()} ${r.failure()?.errorText}`));

await page.goto(URL_, { waitUntil: "networkidle", timeout: 45000 });

// 1. the module graph loaded at all
const mod = await page.evaluate(async () => {
  try {
    const m = await import("./kant-ipfs.mjs");
    return {
      ok: true,
      rpc: m.KUBO_RPC,
      gw: m.GATEWAY,
      sameOrigin: m.KUBO_RPC.startsWith(location.origin),
    };
  } catch (e) { return { ok: false, error: String(e) }; }
});
console.log("module graph :", JSON.stringify(mod));

// 2. the wasm core instantiates and agrees with the JS contract
const wasm = await page.evaluate(async () => {
  try {
    const m = await import("./kant-ipfs.mjs");
    const core = await m.wasmOnce();
    // wasmOnce() swallows load errors and returns null, so a broken wasm
    // is indistinguishable from "fell back to JS" unless we check here.
    if (!core) return { ok: false, loaded: false, error: "wasmOnce() returned null - wasm did NOT load" };
    const probe = new TextEncoder().encode("kant pastebin wasm core probe");
    // cidOf is async and dispatches through the wasm when it is loaded,
    // which is exactly the path the page itself exercises.
    const cid = await m.cidOf(probe);
    const direct = core.wasm_cid_of_bytes(probe);
    return {
      loaded: true,
      ok: typeof cid === "string" && cid === direct && cid.startsWith("bafkrei"),
      cid, direct,
      plan: Array.from(core.wasm_chunk_plan(probe.length)),
    };
  } catch (e) { return { ok: false, loaded: false, error: String(e) }; }
});
console.log("wasm core    :", JSON.stringify(wasm));
const coreStatus = await page.textContent("#core-status").catch(() => null);
console.log("core says    :", JSON.stringify(coreStatus));

// 3. the same-origin IPFS gateway actually resolves a real CID
const gw = await page.evaluate(async () => {
  const CID = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku";
  try {
    const res = await fetch(`/ipfs-gw/ipfs/${CID}`);
    return { status: res.status, ok: res.ok, type: res.headers.get("content-type") };
  } catch (e) { return { error: String(e) }; }
});
console.log("ipfs gateway :", JSON.stringify(gw));

const status = await page.textContent("#ipfs-status").catch(() => null);
console.log("page says    :", JSON.stringify(status));

console.log("\nerrors:", errors.length ? errors.slice(0, 6) : "none");
const good = mod.ok && mod.sameOrigin && wasm.ok && wasm.loaded && gw.ok;
console.log(good ? "P2P PAGE OK" : "P2P PAGE FAILED");
await browser.close();
exit(good ? 0 : 1);