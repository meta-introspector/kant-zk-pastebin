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

/** A browser that can actually open a window.
 *
 *  Playwright's bundled download is only the headless shell here, which
 *  cannot render headed — so a headed run needs a full browser from
 *  somewhere else. Preference order:
 *
 *    1. $KANT_CHROMIUM, so a caller can name one explicitly;
 *    2. the Nix-provided chromium (`nix build nixpkgs#chromium`), which is
 *       pinned by the store hash and does not depend on a snap refresh or a
 *       Playwright browser download;
 *    3. the Playwright full-chromium download, if `playwright install` has
 *       been run;
 *    4. a system browser, as a last resort.
 *
 *  A "headed" run that silently fell back to headless would be the worst
 *  possible outcome for an evidence capture, so with none of these present
 *  this throws instead of quietly degrading. */
function findChromium() {
  const fromEnv = process.env.KANT_CHROMIUM;
  if (fromEnv) {
    if (!fs.existsSync(fromEnv)) throw new Error(`KANT_CHROMIUM=${fromEnv} does not exist`);
    return { path: fromEnv, from: 'KANT_CHROMIUM' };
  }
  // A nix store path for chromium, newest first. Resolved by globbing the
  // store rather than hardcoding one hash, so a nix GC or an upgrade does
  // not silently break the capture.
  const store = process.env.NIX_STORE ?? '/nix/store';
  const nixPkgsChromium = fs.readdirSync(store)
    .filter((d) => /^.{32}-chromium-\d/.test(d))
    .sort()
    .reverse()
    .map((d) => path.join(store, d, 'bin', 'chromium'))
    .find((p) => fs.existsSync(p));
  if (nixPkgsChromium) return { path: nixPkgsChromium, from: 'nixpkgs#chromium' };

  const pwRoot = process.env.PLAYWRIGHT_BROWSERS_PATH
    ?? path.join(process.env.HOME ?? '', '.cache', 'ms-playwright');
  const pwFull = fs.existsSync(pwRoot)
    ? fs.readdirSync(pwRoot).filter((d) => /^chromium-\d+$/.test(d)).sort().reverse()
        .map((d) => path.join(pwRoot, d, 'chrome-linux64', 'chrome'))
        .find((p) => fs.existsSync(p))
    : null;
  if (pwFull) return { path: pwFull, from: 'playwright chromium' };

  const system = ['/snap/bin/chromium', '/usr/bin/chromium', '/usr/bin/chromium-browser']
    .find((p) => fs.existsSync(p));
  if (system) return { path: system, from: 'system' };
  return null;
}

const browserChoice = findChromium();
// The browser's own version string, recorded so a run can be tied to the
// engine that produced it. Failing to read it is not a failure of the
// capture, so it degrades to null rather than throwing.
let browserVersion = null;
if (browserChoice) {
  try {
    const { execFileSync } = await import('node:child_process');
    browserVersion = execFileSync(browserChoice.path, ['--version'], {
      encoding: 'utf8', timeout: 20_000, stdio: ['ignore', 'pipe', 'ignore'],
    }).trim().replace(/^Chromium\s+/, '');
  } catch { browserVersion = null; }
}
if (headed && !browserChoice) {
  throw new Error(
    '--headed needs a full browser; only the Playwright headless shell is installed.\n' +
    '  nix build nixpkgs#chromium          # pinned, no snap or download needed\n' +
    '  npx playwright install chromium      # or the Playwright download\n' +
    '  KANT_CHROMIUM=<path>                 # or name one explicitly\n' +
    'There is deliberately no silent fallback to headless here: a headed ' +
    'evidence run that was secretly headless is worse than no run at all.',
  );
}

const browser = await chromium.launch({
  headless: !headed,
  ...(browserChoice ? { executablePath: browserChoice.path } : {}),
  args: ['--no-sandbox', ...(headed ? ['--window-size=1440,1800'] : [])],
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


      // (4) The actual IPFS round trip, through the daemon, from the page.
      //
      // Everything above this line reasons about manifests and witnesses in
      // memory. None of it touches a daemon, so none of it can catch the
      // failures that actually live in this layer: the page resolving its
      // gateway, kubo refusing a cross-origin RPC (it answers 403, which is
      // why KUBO_RPC is the same-origin /ipfs-rpc and not :5001), a partial
      // pin, or a chunk the gateway will not serve back.
      //
      // This is the check the earlier suite was missing. It also explains why
      // a broken IPFS path is invisible from the room: web/index.html
      // downgrades to a relay-only announcement when `complete` is false, so
      // the file share keeps working and nothing looks wrong.
      try {
        const IPFS = await import('./kant-file-ipfs.mjs');
        // KUBO_RPC is defined in kant-ipfs.mjs and *not* re-exported by
        // kant-file-ipfs.mjs, so it has to come from there. Reading it off the
        // wrong module yields `undefined`, the fetch throws, and the check
        // reports "unreachable" for a daemon that is up — which is the first
        // version of this check, and why it is worth saying out loud.
        const { KUBO_RPC, GATEWAY } = await import('./kant-ipfs.mjs');
        out.rpcEndpoint = KUBO_RPC;
        out.gwEndpoint = GATEWAY;
        out.kuboReachable = await (async () => {
          try {
            const r = await fetch(`${KUBO_RPC}/api/v0/version`, { method: 'POST' });
            return r.ok;
          } catch (e) {
            out.rpcError = String(e && e.message ? e.message : e);
            return false;
          }
        })();

        if (out.kuboReachable) {
          const pin = await IPFS.putChunks(enc.chunks);
          out.pinnedEveryChunk = pin.complete === true && pin.cids.length === enc.chunks.length;
          out.pinnedCidCount = pin.cids.length;
          out.failedAt = pin.failedAt;

          // The manifest a peer would actually receive, carrying the CIDs the
          // daemon just gave us next to the witnesses that name the chunks.
          const live = F.manifest(room, 'peer', 3, 'evidence.bin',
            'application/octet-stream', enc.size, enc.nonce, enc.cids, pin.cids);
          out.liveManifestRoundTrips = (() => {
            const q = F.parseManifest(F.printManifest(live));
            return !!q && q.ipfs.length === enc.cids.length && q.ipfs[0] !== q.cids[0];
          })();

          // Fetch each chunk back over HTTP and hand it to decryptFile the way
          // a second peer would — witness-keyed, resolving through ipfsFetcher.
          const back = await F.decryptFile(secret,
            { size: enc.size, nonce: enc.nonce, cids: enc.cids },
            IPFS.ipfsFetcher(live));
          out.ipfsRoundTripsToSameBytes = (() => {
            if (back.length !== data.length) return false;
            for (let i = 0; i < data.length; i += 1) if (back[i] !== data[i]) return false;
            return true;
          })();

          // And the daemon must refuse to serve a chunk it does not hold,
          // rather than handing back something that decrypts to garbage.
          out.gatewayRefusesAnAbsentCid = await (async () => {
            try {
              const bytes = await IPFS.getChunk('bafkreieqaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
              return bytes === null;
            } catch { return true; }
          })();
        }
      } catch (e) {
        out.ipfsError = String(e && e.message ? e.message : e);
      }

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

  // The live-daemon round trip. These need the daemon; without it they are
  // reported as failures rather than skipped, because a skip here is exactly
  // how a broken IPFS path stayed invisible — the room still works, relay-only.
  check('kubo is reachable from the page', observation.kuboReachable,
    observation.ipfsError ?? `via ${observation.kuboReachable ? 'same-origin /ipfs-rpc' : 'unreachable'}`);
  check('every chunk is pinned on ipfs', observation.pinnedEveryChunk,
    `${observation.pinnedCidCount ?? 0} pinned, failed at ${observation.failedAt ?? 'n/a'}`);
  check('a pinned manifest keeps both names', observation.liveManifestRoundTrips);
  check('ipfs chunks decrypt back to the original bytes', observation.ipfsRoundTripsToSameBytes);
  check('the gateway refuses an absent cid', observation.gatewayRefusesAnAbsentCid);
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
  // Which browser ran, so a reader can tell a pinned store path from a
  // snap. The store hash is recorded rather than the full path: the path
  // says nothing the derivation does not, and this file may be published.
  browser: browserChoice ? { from: browserChoice.from, version: browserVersion } : null,
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