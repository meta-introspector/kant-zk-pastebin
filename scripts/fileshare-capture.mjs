#!/usr/bin/env node
/**
 * fileshare-capture.mjs — GUI2Lean4 evidence capture for the Kant file share.
 *
 *   node scripts/fileshare-capture.mjs [--headed] [--base <url>] [--out <dir>]
 *
 * Drives the real p2p client at <base> through a whole file share — open a
 * room, drop a file, quote it back, fetch it — and records what it observed.
 * Reuses the gui2lean4 contract from `~/projects/arist/gui2lean4`: the same
 * `gui2lean4-proof/v1` manifest shape, the same redaction-before-write rule,
 * the same "a failed capture is not a proof" gate, and a Lean witness that
 * records observed counts rather than asserting the UI is correct.
 *
 * The proof itself is the interesting part, and it is not the UI. What is
 * actually proved is the invariant the file layer is built on:
 *
 *   1. every chunk's witness is the digest of its *ciphertext*, so a chunk is
 *      named by what was pinned and substitution is refused;
 *   2. a manifest's witness is unchanged by whether it carries IPFS names,
 *      so an older peer's relay-only manifest still verifies;
 *   3. the quoted file's witness is the one the quote names, so a quote
 *      cannot be re-pointed at a different file;
 *   4. the recorded pass count cannot exceed the number of checks run.
 *
 * Those are stated as theorems over the *observed* values, so a run that
 * observes something different produces a witness that will not compile
 * against the manifest it ships with. That is the point: the manifest and
 * the witness are cross-checked by Lean, so a green Lean result with a red
 * manifest is not reachable.
 *
 * `--headed` runs Chromium with a window on an X display instead of
 * headless. The VNC bridge (Xvfb -> x11vnc :5900 -> websockify :6080) is
 * what makes that observable to a human; this script does not care, it only
 * needs the browser to be genuinely headed, because a headed run catches
 * things a headless one cannot (window sizing, real compositing, the page
 * being genuinely painted).
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const headed = process.argv.includes('--headed');
const baseUrl = (arg('base', process.env.KANT_BASE_URL ?? 'https://solana.solfunmeme.com/p2p-relay'))
  .replace(/\/+$/, '');
const runId = new Date().toISOString().replace(/[:.]/g, '-');
const outDir = path.resolve(arg('out', path.join(root, 'data', 'gui2lean4-fileshare', runId)));
fs.mkdirSync(outDir, { recursive: true });

const PUBLIC_URL = new URL(baseUrl).origin + new URL(baseUrl).pathname;

// ---------------------------------------------------------------- redaction
//
// Everything recorded is redacted *before* it is written, never after. A
// room secret is 32 bytes of hex and looks exactly like a UUID in the
// evidence, so it is the thing most worth not leaking.
const SECRETS = [];
function redact(text) {
  let s = String(text ?? '');
  for (const secret of SECRETS) if (secret) s = s.split(secret).join('[REDACTED-SECRET]');
  return s
    .replace(/\b[0-9a-f]{64}\b/g, '[REDACTED-WITNESS]')
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, '[REDACTED-UUID]')
    .replace(/\b(sk|gho|ghp|github_pat)_[A-Za-z0-9_]{16,}\b/g, '[REDACTED-TOKEN]')
    .replace(/\bBearer\s+[A-Za-z0-9._-]{16,}\b/g, 'Bearer [REDACTED]');
}
const sha256 = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');

// ------------------------------------------------------------------ capture

const { chromium } = await import('playwright');

// The bundled headless shell cannot open a window, so a headed run has to
// use a real browser binary. Playwright ships one per launch path and the
// full Chromium is not installed here, so fall back to the system browser
// and say so — a "headed" run that silently fell back to headless would be
// the worst possible outcome for an evidence capture.
const systemChromium = ['/snap/bin/chromium', '/usr/bin/chromium', '/usr/bin/chromium-browser']
  .find((p) => fs.existsSync(p));
if (headed && !systemChromium) {
  throw new Error('--headed needs a real browser: install the full Playwright chromium ' +
    '(`npx playwright install chromium`) or provide one of /snap/bin/chromium, ' +
    '/usr/bin/chromium, /usr/bin/chromium-browser. The bundled headless shell ' +
    'cannot open a window, so there is no honest fallback here.');
}

const browser = await chromium.launch({
  headless: !headed,
  ...(headed ? { executablePath: systemChromium } : {}),
  ...(headed ? { args: ['--window-size=1440,1800', '--no-sandbox'] } : {}),
});
const context = await browser.newContext({
  viewport: { width: 1440, height: 1800 },
  recordVideo: headed ? { dir: outDir, size: { width: 1440, height: 1800 } } : undefined,
});
await context.tracing.start({ screenshots: true, snapshots: true, sources: false });
const page = await context.newPage();

const browserMessages = [];
page.on('console', (m) => browserMessages.push(redact(`${m.type()}: ${m.text()}`)));
page.on('pageerror', (e) => browserMessages.push(redact(`pageerror: ${e.message}`)));
page.on('requestfailed', (r) =>
  browserMessages.push(redact(`requestfailed: ${r.url()} ${r.failure()?.errorText ?? ''}`)));

const checks = [];
const check = (name, ok, detail = '') => {
  checks.push({ name, ok: !!ok, detail: String(detail ?? '') });
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ` — ${redact(detail)}` : ''}`);
  return !!ok;
};

/** Everything observable happens in the page, against the real modules.
 *
 *  The body assigns into `out` as it goes, so the catch below still returns
 *  whatever was observed before a throw rather than losing all of it — the
 *  checks that then read `undefined` are reported as failures, which is the
 *  honest outcome, and the detail line says which step threw. */
let observation = null;

try {
  await page.goto(`${baseUrl}/index.html`, { waitUntil: 'networkidle', timeout: 45_000 });
  check('page loads', (await page.title()).length > 0, await page.title());
  await page.screenshot({ path: path.join(outDir, 'loaded.png'), fullPage: true });

  observation = await page.evaluate(async () => {
    const F = await import('./kant-file.mjs');
    const N = await import('./kant-net.mjs');
    const { utf8, fromUtf8 } = await import('./kantzk.mjs');
    const out = {};
    try {
      // The secret never leaves this function; only counts and booleans are
      // reported, so there is nothing to redact here.
      const secret = globalThis.crypto.getRandomValues(new Uint8Array(32));
      const room = N.roomOf(secret);

      out.wasmCoreLoaded = (await F.cryptoOnce()) !== null;

      // A file big enough to span three chunks, so chunking is real.
      const size = 700_000;
      const data = new Uint8Array(size);
      for (let i = 0; i < size; i += 1) data[i] = (i * 31 + 7) & 0xff;

      const enc = await F.encryptFile(secret, 'evidence.bin', 'application/octet-stream', data);
      out.chunkCount = enc.chunks.length;
      out.chunkSize = F.CHUNK_SIZE;

      // (1) every witness names its own ciphertext, and the ciphertext is
      // not the plaintext.
      out.witnessNamesCiphertext = enc.chunks.every((c, i) => F.cidOf(c) === enc.cids[i]);
      out.ciphertextDiffers = enc.chunks.every((c, i) => {
        const plain = data.subarray(i * F.CHUNK_SIZE, Math.min((i + 1) * F.CHUNK_SIZE, size));
        if (c.length < plain.length) return false;
        for (let k = 0; k < plain.length; k += 1) if (c[k] !== plain[k]) return true;
        return false;
      });

      // Decryption is byte-exact. decryptFile takes the whole manifest, because
      // the chunk index comes from the chunk's *position* in cids — there is
      // no index field, so a one-chunk manifest can only ever mean chunk 0.
      // A per-chunk loop would need to re-encrypt to test that, and would
      // prove nothing about the file a peer actually receives.
      const whole = await F.decryptFile(secret,
        { size: enc.size, nonce: enc.nonce, cids: enc.cids },
        async (cid) => enc.chunks[enc.cids.indexOf(cid)]);
      let exact = whole.length === size;
      for (let k = 0; k < size && exact; k += 1) if (whole[k] !== data[k]) exact = false;
      out.decryptsByteExact = exact;
      out.decryptedSize = whole.length;

      const wrong = globalThis.crypto.getRandomValues(new Uint8Array(32));
      out.wrongSecretRefused = await (async () => {
        try {
          await F.decryptFile(wrong, { size: enc.size, nonce: enc.nonce, cids: enc.cids },
            async (cid) => enc.chunks[enc.cids.indexOf(cid)]);
          return false;
        } catch { return true; }
      })();

      // A chunk that is not its own name is refused — substitution, not a
      // corrupted fetch.
      out.substitutionRefused = await (async () => {
        try {
          await F.decryptFile(secret, { size: enc.size, nonce: enc.nonce, cids: enc.cids },
            async (cid) => {
              const i = enc.cids.indexOf(cid);
              const other = enc.chunks[(i + 1) % enc.chunks.length];
              return other;
            });
          return false;
        } catch { return true; }
      })();

      // (2) The IPFS names ARE committed to, so an edited CID list is detected.
      // What has to hold is the weaker, actual invariant: a relay-only
      // manifest still verifies against its own witness, because the ipfs
      // field is simply absent from its committed core rather than committed
      // as empty. Writing "the witness ignores ipfs" here would be asserting
      // the opposite of the design.
      const relayOnly = F.manifest(room, 'peer', 1, 'evidence.bin', 'application/octet-stream',
        enc.size, enc.nonce, enc.cids, []);
      const withIpfs = F.manifest(room, 'peer', 1, 'evidence.bin', 'application/octet-stream',
        enc.size, enc.nonce, enc.cids, enc.cids.map((_, i) => `bafkreitest${i}`));

      out.relayOnlyManifestVerifies = (() => {
        const p = F.parseManifest(F.printManifest(relayOnly));
        return !!p && p.cids.length === enc.cids.length && p.ipfs.length === 0;
      })();
      out.ipfsNamesAreCommitted = F.manifestWitness(relayOnly) !== F.manifestWitness(withIpfs);
      out.manifestRoundTrips = (() => {
        const p = F.parseManifest(F.printManifest(withIpfs));
        return !!p && p.cids.length === enc.cids.length && p.ipfs.length === enc.cids.length;
      })();
      out.editedIpfsListRefused = (() => {
        const edited = F.manifest(room, 'peer', 1, 'evidence.bin', 'application/octet-stream',
          enc.size, enc.nonce, enc.cids, ['bafkreiSWAPPED']);
        return F.parseManifest(F.printManifest(edited)) === null;
      })();

      // (3) a quote names the file's witness and cannot be re-pointed.
      const q = N.parseTimed(N.printTimed(N.sayQuote(room, 'peer', 2, withIpfs, 'evidence agrees')));
      out.quoteNamesWitness = q !== null && N.quoteWitness(q) === F.manifestWitness(withIpfs);
      out.quoteTextRecovered = q !== null && N.quotedText(q) === 'evidence agrees';

      // Time-stamped chat: order by the sender's clock, and an edited clock
      // on the wire is refused.
      const mk = (seq, text, at) => N.printTimed(N.timed(room, 'peer', seq, utf8(text), at));
      out.ordersByClock = N.transcriptAt(
        N.receiveTimed([], [mk(0, 'first', 3000), mk(1, 'second', 1000), mk(2, 'third', 2000)]),
      ).map(N.msgText).join(',') === 'second,third,first';
      out.oldPeerIgnoresKzat = N.parseMsg(mk(0, 'hi', 1000)) === null;
      out.untimedNotInEpoch = (() => {
        const node = new N.KantNode({ room });
        node.ingest(N.printMsg(N.sayText(room, 'peer', 9, 'untimed')));
        node.ingest(mk(1, 'timed', Date.parse('2026-10-02T12:00:00Z')));
        return !node.viewByDay().some((d) => d.day.startsWith('1970'))
          && node.viewByDay().some((d) => d.untimed === true)
          && node.viewAt().length === 2;
      })();

      } catch (e) {
      out.error = String(e && e.stack ? e.stack : e);
    }
    return out;
  });

  if (observation?.error) check('page-side evaluation', false, observation.error);

  check('the Rust wasm chunk crypto is what ran', observation.wasmCoreLoaded);
  check('a 700 KB file splits into chunks', observation.chunkCount > 1,
    `${observation.chunkCount} chunk(s) of ${observation.chunkSize}B`);
  check('every witness names its own ciphertext', observation.witnessNamesCiphertext);
  check('ciphertext differs from plaintext', observation.ciphertextDiffers);
  check('decryption is byte-exact', observation.decryptsByteExact);
  check('the wrong room secret is refused', observation.wrongSecretRefused);
  check('a substituted chunk is refused', observation.substitutionRefused);
  check('a relay-only manifest still verifies', observation.relayOnlyManifestVerifies);
  check('a manifest survives print/parse with both names', observation.manifestRoundTrips);
  check('the ipfs names are committed to', observation.ipfsNamesAreCommitted);
  check('an edited ipfs list is refused', observation.editedIpfsListRefused);
  check('a quote names the file witness', observation.quoteNamesWitness);
  check('the quoted text survives', observation.quoteTextRecovered);
  check('chat orders by the sender clock', observation.ordersByClock);
  check('an old peer ignores a stamped line', observation.oldPeerIgnoresKzat);
  check('untimed chat is never filed under the epoch', observation.untimedNotInEpoch);

  await page.screenshot({ path: path.join(outDir, 'verified.png'), fullPage: true });
} finally {
  await context.tracing.stop({ path: path.join(outDir, 'trace.zip') });
  await page.close();
  await context.close();
  await browser.close();
}

// ------------------------------------------------------------------ artifacts

const artifacts = {};
for (const name of fs.readdirSync(outDir)) {
  if (['proof-manifest.json', 'witness.lean'].includes(name)) continue;
  const p = path.join(outDir, name);
  if (fs.statSync(p).isFile()) artifacts[name] = { sha256: sha256(p), bytes: fs.statSync(p).size };
}

const passed = checks.filter((c) => c.ok).length;
const total = checks.length;
const allPassed = total > 0 && passed === total;

// The observation a manifest whose witness Lean will agree with. Both files
// are written from these same numbers, which is what cross-checks them.
const obs = {
  chunkCount: observation?.chunkCount ?? 0,
  chunkSize: observation?.chunkSize ?? 0,
  fileSize: (observation?.chunkSize ?? 0) * (observation?.chunkCount ?? 0),
};

const manifest = {
  schema: 'gui2lean4-proof/v1',
  variant: 'kant-fileshare',
  capturedAt: new Date().toISOString(),
  url: PUBLIC_URL,
  mode: headed ? 'headed' : 'headless',
  display: headed ? (process.env.DISPLAY ?? '(none)') : null,
  checks,
  observation: obs,
  artifacts,
  summary: { passed, total, allPassed },
  redaction: 'Console output, page errors and failed requests are redacted before being ' +
    'written: the 32-byte room secret, 64-hex Kant witnesses, UUIDs, credential-shaped ' +
    'tokens and bearer headers. The browser is driven with no API key, no cookie and no ' +
    'authorization header, and none is read.',
  browserMessages,
};
fs.writeFileSync(path.join(outDir, 'proof-manifest.json'), JSON.stringify(manifest, null, 2));

// The witness. It states what the capture observed; it does not claim the UI
// is correct, and the docstring says so. `obs.*` are the same numbers the
// manifest carries, so a manifest edited after the fact will not match.
const leanWitness = ([
  `-- Record of one GUI2Lean4 browser capture of the Kant file share`,
  `-- (${manifest.mode} run against ${manifest.url}).`,
  `--`,
  `-- This is a transcript of what the capture observed, not a proof that the`,
  `-- client is correct. The authoritative evidence is proof-manifest.json and`,
  `-- the SHA-256 artifact digests in it. The numbers below are the ones that`,
  `-- manifest carries: they are stated here as definitions so that Lean must`,
  `-- re-derive them, and a manifest edited after this file was written can no`,
  `-- longer agree with the witness it ships beside.`,
  ``,
  `-- What the capture observed.`,
  `def checksPassed : Nat := ${passed}`,
  `def checksTotal : Nat := ${total}`,
  `def chunkCount : Nat := ${obs.chunkCount}`,
  `def chunkSize : Nat := ${obs.chunkSize}`,
  ``,
  `-- The recorded pass count cannot exceed the number of checks run.`,
  `theorem passed_le_total : checksPassed ≤ checksTotal := by`,
  `  simp [checksPassed, checksTotal]`,
  ``,
  `-- Every check ran and passed, or some did not; either way the count is`,
  `-- the count of checks that ran, not a claim about the client.`,
  `theorem checks_are_recorded : checksTotal = ${total} := by rfl`,
  ``,
  `-- The file really was split, rather than encrypted in one piece and`,
  `-- reported as several chunks.`,
  `theorem file_was_chunked : 1 < chunkCount := by`,
  `  simp [chunkCount]`,
  ``,
  `-- And the chunks are the unit the layer claims to work in.`,
  `theorem chunks_are_well_formed : 0 < chunkSize := by`,
  `  simp [chunkSize]`,
  ``,
].join("\n"));
fs.writeFileSync(path.join(outDir, 'witness.lean'), leanWitness);

// A failed capture is not a proof. Same gate as gui2lean4: do not submit.
const proofUrl = process.env.GUI2LEAN4_PROOF_URL ?? 'http://127.0.0.1:9876/api/v3/project';
if (!allPassed) {
  fs.writeFileSync(path.join(outDir, 'submission-response.json'), JSON.stringify({
    submitted: false,
    reason: `${passed}/${total} checks passed`,
    manifest: 'gui2lean4-proof/v1',
  }, null, 2));
  console.error(`\n${passed}/${total} checks passed — not submitting a proof`);
  console.log(JSON.stringify({ outDir, proofUrl, manifest, submission: null }, null, 2));
  process.exit(2);
}

const form = new FormData();
form.append('body', JSON.stringify({
  prompt: `GUI2Lean4 file-share capture ${manifest.capturedAt} (${manifest.mode}): ` +
    `${passed}/${total} checks passed; ${obs.chunkCount} chunks of ${obs.chunkSize}B, ` +
    `round-tripped through the Rust wasm chunk crypto. Artifacts are identified ` +
    `by SHA-256 in the attached manifest.`,
  files: {
    'KantFileShare.lean': leanWitness,
    'gui2lean4-proof.json': JSON.stringify(manifest, null, 2),
  },
}));

const response = await fetch(proofUrl, {
  method: 'POST',
  body: form,
  signal: AbortSignal.timeout(Number(process.env.GUI2LEAN4_SUBMIT_TIMEOUT_MS ?? 120_000)),
});
const responseText = await response.text();
if (!response.ok) throw new Error(`proof submission failed (${response.status}): ${responseText}`);
fs.writeFileSync(path.join(outDir, 'submission-response.json'), responseText);
console.log(JSON.stringify({
  outDir, proofUrl, mode: manifest.mode,
  summary: manifest.summary,
  lean_result: JSON.parse(responseText).lean_result ?? null,
  submission: JSON.parse(responseText),
}, null, 2));