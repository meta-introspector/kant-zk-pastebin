#!/usr/bin/env node
// file-browser-check.mjs — the file-drop layer in a real browser.
//
//   node scripts/file-browser-check.mjs [http://host[:port][/prefix]]
//
// The Node suite (web/file-test.mjs) runs the same code against node:crypto
// and a real relay. This one runs it in Chromium, because the interesting
// failure modes are browser-shaped: the module graph has to resolve as real
// ES modules over HTTP, and the crypto has to be WebCrypto's, not Node's.
//
// It also loads p2p.html itself, so a change that breaks the net layer's
// import of kant-file.mjs fails here rather than in someone's browser.
//
// Checks:
//   * p2p.html loads clean, with the Rust wasm core live
//   * kant-file.mjs resolves as a module and exposes the file API
//   * a 400 KB file encrypts to 2 chunks and decrypts byte-exact
//   * a chunk's cid is the digest of its ciphertext, not its plaintext
//   * the wrong room secret cannot decrypt it
//   * a chunk that is not its own name is refused
//   * the manifest survives print -> parse with its witness intact
//
// Exits 0 only if everything holds.

import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const target = (process.argv[2] ?? "http://127.0.0.1:8797").replace(/\/+$/, "");
const p2pUrl = `${target}/p2p.html`;

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
// Chromium's "Failed to load resource: net::ERR_FAILED" carries no URL in the
// message text, so keep the message's own location alongside it — otherwise a
// failed gateway probe cannot be told apart from any other failed request.
page.on("console", (m) => {
  if (m.type() === "error") consoleErrors.push(`${m.text()} @ ${m.location()?.url ?? "?"}`);
});
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
const resp = await page.goto(p2pUrl, { waitUntil: "load", timeout: 60_000 });
check("p2p page responds 2xx", resp && resp.ok(), `HTTP ${resp?.status()}`);
await page.waitForTimeout(1_500);

// The wasm core is the reason the page exists; make sure the land did not
// regress it while the file layer was being added.
const core = await page.evaluate(async () => {
  try {
    const mod = await import("./kant-ipfs.mjs");
    const c = await mod.wasmOnce?.();
    return { ok: Boolean(c), hasUnixfs: typeof mod.unixfsPlanOf === "function" };
  } catch (e) { return { ok: false, err: String(e) }; }
});
check("Rust wasm core is live", core.ok, core.ok ? "" : (core.err ?? ""));

// Everything below runs inside the page, against the module the deployment
// actually served. The import specifier is relative on purpose: this suite is
// also run against origins that mount the app under a path prefix, where an
// absolute "/kant-file.mjs" would resolve against the host root instead.
const fileLayer = await page.evaluate(async () => {
  const F = await import("./kant-file.mjs");
  const out = { api: {} };

  for (const name of ["encryptFile", "decryptFile", "manifest", "printManifest",
                      "parseManifest", "cidOf"]) {
    out.api[name] = typeof F[name];
  }
  out.chunkSize = F.CHUNK_SIZE;

  const secret = globalThis.crypto.getRandomValues(new Uint8Array(32));
  const wrong = globalThis.crypto.getRandomValues(new Uint8Array(32));

  // 400 KB, so more than one chunk and the chunk loop actually iterates.
  const size = 400000;
  const data = new Uint8Array(size);
  let seed = 0x9e3779b9;
  for (let i = 0; i < size; i += 1) {
    seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0;
    data[i] = seed & 0xff;
  }

  const plainHead = Array.from(data.subarray(0, 32));

  const enc = await F.encryptFile(secret, "report.zip", "application/zip", data);
  out.size = enc.size;
  out.chunks = enc.chunks.length;
  out.cids = enc.cids.length;

  // A cid must name the ciphertext. If it named the plaintext, the relay
  // would learn the file's contents from the block names alone.
  out.cidNamesCiphertext = enc.chunks.every((c, i) => F.cidOf(c) === enc.cids[i]);

  // ...and the stored bytes must not be the plaintext either.
  const cipherHead = Array.from(enc.chunks[0].subarray(0, 32));
  out.plaintextDiffers = cipherHead.some((b, i) => b !== plainHead[i]);

  // Round trip through the relay's storage: fetch by cid.
  const store = new Map(enc.chunks.map((c, i) => [enc.cids[i], c]));
  const back = await F.decryptFile(secret, enc, async (cid) => {
    const hit = store.get(cid);
    if (!hit) throw new Error(`no such chunk ${cid}`);
    return hit;
  });
  out.roundTripExact = back.length === size && back.every((b, i) => b === data[i]);

  // The wrong room secret must not open it.
  try {
    await F.decryptFile(wrong, enc, async (cid) => store.get(cid));
    out.wrongSecretRejected = false;
  } catch { out.wrongSecretRejected = true; }

  // A chunk that is not its own name must be refused, not silently accepted.
  try {
    const tampered = enc.chunks.map((c, i) => (i === 0 ? c.slice() : c));
    tampered[0][0] ^= 0xff;
    const tstore = new Map(enc.chunks.map((c, i) => [enc.cids[i], c]));
    tstore.set(enc.cids[0], tampered[0]);
    await F.decryptFile(secret, enc, async (cid) => tstore.get(cid));
    out.tamperedChunkRefused = false;
  } catch { out.tamperedChunkRefused = true; }

  // The manifest has to survive the wire format with its witness intact.
  const m = F.manifest("room-1", "peer-a", 7, enc.name, enc.mime, enc.size, enc.nonce, enc.cids);
  const wire = F.printManifest(m);
  const back2 = F.parseManifest(wire);
  out.manifestRoundTrip =
    back2.name === m.name && back2.mime === m.mime && back2.size === m.size &&
    back2.room === m.room && back2.sender === m.sender && back2.seq === m.seq &&
    JSON.stringify(back2.cids) === JSON.stringify(m.cids);
  out.manifestWitnessStable = F.manifestWitness(back2) === F.manifestWitness(m);

  return out;
});

// The chunk crypto now also lives in the wasm core. Node's crypto and the
// browser's WebCrypto are different implementations, so agreeing in the
// crosscheck (node) is not evidence they agree HERE -- this compares the
// wasm against the page's own WebCrypto, in the browser that will run it.
const wasmCrypto = await page.evaluate(async () => {
  const out = { loaded: false, match: false, roundTrip: false, wrongSecretRefused: false, detail: "" };
  try {
    const w = await import("./pastebin_wasm.js");
    await w.default();
    out.loaded = true;
    if (typeof w.wasm_encrypt_chunk !== "function") { out.detail = "no wasm_encrypt_chunk export"; return out; }

    const secret = globalThis.crypto.getRandomValues(new Uint8Array(32));
    const F = await import("./kant-file.mjs");

    // Let the page's own encryptFile choose the nonce, then insist the wasm
    // reproduce those exact bytes.
    const size = 300000;                       // two chunks
    const data = new Uint8Array(size);
    let seed = 0x1234567;
    for (let i = 0; i < size; i += 1) {
      seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0;
      data[i] = seed & 0xff;
    }
    const enc = await F.encryptFile(secret, "wasm.bin", "application/octet-stream", data);
    out.chunks = enc.chunks.length;

    let allMatch = true, allBack = true;
    for (let i = 0; i < enc.chunks.length; i += 1) {
      const slice = data.subarray(i * F.CHUNK_SIZE, Math.min((i + 1) * F.CHUNK_SIZE, size));
      const re = w.wasm_encrypt_chunk(secret, Uint8Array.from(enc.nonce), i, slice);
      if (re.length !== enc.chunks[i].length) { allMatch = false; continue; }
      for (let k = 0; k < re.length; k += 1) if (re[k] !== enc.chunks[i][k]) { allMatch = false; break; }
      const back = w.wasm_decrypt_chunk(secret, Uint8Array.from(enc.nonce), i, Uint8Array.from(enc.chunks[i]));
      if (back.length !== slice.length) { allBack = false; continue; }
      for (let k = 0; k < back.length; k += 1) if (back[k] !== slice[k]) { allBack = false; break; }
    }
    out.match = allMatch;
    out.roundTrip = allBack;

    const wrong = globalThis.crypto.getRandomValues(new Uint8Array(32));
    try {
      w.wasm_decrypt_chunk(wrong, Uint8Array.from(enc.nonce), 0, Uint8Array.from(enc.chunks[0]));
      out.wrongSecretRefused = false;
    } catch { out.wrongSecretRefused = true; }
  } catch (e) { out.detail = String(e); }
  return out;
});

check("wasm chunk crypto loads in the browser", wasmCrypto.loaded, wasmCrypto.detail);
check("wasm ciphertext matches WebCrypto byte-for-byte", wasmCrypto.match,
  `${wasmCrypto.chunks ?? 0} chunk(s)`);
check("wasm decrypts what WebCrypto encrypted", wasmCrypto.roundTrip);
check("wasm refuses another room secret", wasmCrypto.wrongSecretRefused);

for (const [name, ok] of Object.entries(fileLayer.api)) {
  check(`exports ${name}`, ok === "function", ok === "function" ? "" : `got ${ok}`);
}

check("400 KB encrypts to 2 chunks",
  fileLayer.chunks === 2 && fileLayer.chunks === fileLayer.cids,
  `${fileLayer.chunks} chunks, ${fileLayer.cids} cids`);
check("a cid names the ciphertext", fileLayer.cidNamesCiphertext);
check("ciphertext differs from plaintext", fileLayer.plaintextDiffers);
check("decrypts byte-exact", fileLayer.roundTripExact);
check("wrong room secret rejected", fileLayer.wrongSecretRejected);
check("tampered chunk refused", fileLayer.tamperedChunkRefused);
check("manifest survives print/parse", fileLayer.manifestRoundTrip);
check("manifest witness is stable", fileLayer.manifestWitnessStable);

// The time-stored chat and the file quote, in the browser. These are pure
// functions of kant-net.mjs, but the module graph has to resolve over HTTP
// and the page has to load, so running them here catches a broken import
// that node would not.
const chatLayer = await page.evaluate(async () => {
  const out = {};
  try {
    const N = await import("./kant-net.mjs");
    const F = await import("./kant-file.mjs");
    const { utf8 } = await import("./kantzk.mjs");

    const room = N.roomOf(utf8("browser"));
    const mk = (seq, text, at) => N.printTimed(N.timed(room, "alice", seq, utf8(text), at));

    const three = [mk(0, "first", 3000), mk(1, "second", 1000), mk(2, "third", 2000)];
    out.orderedByClock = N.transcriptAt(N.receiveTimed([], three)).map(N.msgText)
      .join(",") === "second,third,first";

    // An edited clock on the wire must be refused.
    const honest = mk(0, "hi", 1000);
    const e = (await import("./kantzk.mjs")).envelopeDecode(honest);
    e.fields[4] = (await import("./kantzk.mjs")).natToBytesBE(9999);
    out.editedClockRefused = N.parseTimed(
      (await import("./kantzk.mjs")).envelopeEncode(e)) === null;

    // kzat must not be mistaken for kzchat, or an old peer breaks.
    out.oldPeerIgnores = N.parseMsg(honest) === null;

    // Quoting a file round-trips and names the manifest's witness.
    const f = F.manifest(room, "alice", 1, "notes.md", "text/markdown", 3, [1, 2, 3], ["w1"]);
    const q = N.parseTimed(N.printTimed(N.sayQuote(room, "bob", 0, f, "mine too")));
    out.quoteRoundTrip = q !== null && N.quotedText(q) === "mine too";
    out.quoteNamesFile = q !== null && N.quoteWitness(q) === F.manifestWitness(f);

    // A node shows a mixed room without losing untimed chat.
    const node = new N.KantNode({ room });
    node.ingest(N.printMsg(N.sayText(room, "alice", 0, "untimed")));
    node.ingest(mk(1, "timed", Date.parse("2026-10-02T12:00:00Z")));
    out.mixedRoomKeepsBoth = node.viewAt().length === 2;
    out.noEpochBucket = !node.viewByDay().some((d) => d.day.startsWith("1970"));
    out.untitledBucket = node.viewByDay().some((d) => d.untimed === true);
  } catch (e) { out.detail = String(e); }
  return out;
});

check("chat orders by the sender's clock", chatLayer.orderedByClock, chatLayer.detail ?? "");
check("an edited clock is refused", chatLayer.editedClockRefused);
check("an old peer ignores a stamped line", chatLayer.oldPeerIgnores);
check("a file quote round-trips", chatLayer.quoteRoundTrip);
check("a quote names the file's witness", chatLayer.quoteNamesFile);
check("a mixed room keeps untimed chat", chatLayer.mixedRoomKeepsBoth);
check("no message is filed under the epoch", chatLayer.noEpochBucket);
check("untimed chat gets its own bucket", chatLayer.untitledBucket);

// The gateway probe is an optional convenience, not part of the file layer.
// kant-ipfs.mjs defaults GATEWAY to 127.0.0.1:8080 and p2p.html probes it on
// load to decide whether to advertise "gateway reachable" or "artifacts will
// ride the room". That default is often not an IPFS gateway at all — on this
// box port 8080 is the DASL Node nginx site — so the probe legitimately fails
// and the page handles it. Counting it as a failure would make this suite
// report a broken file layer every time it ran off a dev origin.
//
// So: report the probe separately, and hold everything else to zero.
const GATEWAY_PROBE = /\/ipfs\/|\/api\/v0\/(cat|add)/;
const isProbe = (s) => GATEWAY_PROBE.test(s);
const probeErrors = consoleErrors.filter(isProbe);
const probeFailed = failedRequests.filter(isProbe);
const otherErrors = consoleErrors.filter((s) => !isProbe(s));
const otherFailed = failedRequests.filter((s) => !isProbe(s));

check(
  "no console errors outside the gateway probe",
  otherErrors.length === 0,
  otherErrors.length ? otherErrors.slice(0, 3).join(" | ")
                     : `${probeErrors.length} probe message(s) ignored`,
);
check("no page errors", pageErrors.length === 0, pageErrors.slice(0, 3).join(" | "));
check(
  "no failed requests outside the gateway probe",
  otherFailed.length === 0,
  otherFailed.length ? otherFailed.slice(0, 3).join(" | ")
                     : `${probeFailed.length} probe request(s) ignored`,
);
console.log(`note  gateway probe: ${probeFailed.length ? "no gateway reachable, page fell back to the room" : "reachable"}`);

await browser.close();

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} file-layer browser checks passed`);
if (failed.length) {
  console.error("FAILED:", failed.map((f) => f.name).join(", "));
  process.exit(1);
}
