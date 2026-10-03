// Conformance test for the Lean-extracted WebAssembly kernel.
//
//   node web/wasm-test.mjs
//
// It validates `web/kant_kernel.wasm` with the engine's own validator,
// instantiates it, and checks every exported function against the golden
// vectors in `web/kernel-vectors.json`, which `lake exe emitwasm` computed from
// the Lean semantics of the very same module.
//
// Both files are tracked copies of `lake exe emitwasm`'s output in `dist/`,
// written by `scripts/embed-kernel.mjs` (`--check` verifies them against
// `dist/`). They used to be read from `dist/` directly, which is gitignored,
// so on a fresh checkout the test died with ENOENT and was filed as broken
// rather than run — while being the only test tying the binary to Lean.
// `scripts/wasm-test.mjs` delegates here, so there is one copy of these
// assertions and one place they can drift.

import { readFile } from "node:fs/promises";
import { loadKernel } from "./kant-wasm.mjs";
import * as js from "./kantzk.mjs";

const wasmBytes = await readFile(new URL("./kant_kernel.wasm", import.meta.url));
const vectors = JSON.parse(
  await readFile(new URL("./kernel-vectors.json", import.meta.url), "utf8"),
).vectors;

let failures = 0;
/** The HTTP status of a request whose path is sent verbatim, unnormalised. */
function rawStatusOf(port, rawPath) {
  return new Promise((resolve, reject) => {
    const sock = connect(port, "127.0.0.1", () => {
      sock.write(`GET ${rawPath} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n`);
    });
    let buf = "";
    sock.on("data", (d) => { buf += d; });
    sock.on("end", () => {
      const m = /^HTTP\/1\.[01] (\d{3})/.exec(buf);
      if (!m) reject(new Error(`no status line in ${JSON.stringify(buf.slice(0, 80))}`));
      else resolve(Number(m[1]));
    });
    sock.on("error", reject);
  });
}
/** True when a path was answered with the repository root's README.md. */
async function readmeVia(port, rawPath) {
  const res = await fetch(`http://127.0.0.1:${port}${rawPath}`);
  const body = await res.text();
  return body.includes("the repository root");
}
const check = (ok, msg) => {
  if (!ok) {
    failures += 1;
    console.error("FAIL", msg);
  }
};

check(WebAssembly.validate(wasmBytes), "module fails WebAssembly.validate");

const { instance } = await WebAssembly.instantiate(wasmBytes, {});
const exports = instance.exports;

const expectedExports = [
  "hex_digit", "cid_prefix", "cid_type", "cid_payload", "mk_cid", "merge_cids",
  "credits_for", "capacity_bytes", "social_chunks", "fits_social", "lsb_embed",
  "lsb_extract", "hex_hi", "hex_lo", "fnv_offset", "fnv1a_step", "u64_byte",
  "cantor_pair", "rotate71", "reflect59", "dual47",
];
for (const name of expectedExports) {
  check(typeof exports[name] === "function", `missing export ${name}`);
}

for (const v of vectors) {
  const fn = exports[v.f];
  if (typeof fn !== "function") continue;
  // wasm `i64` results arrive in JS as *signed* BigInts; the kernel is unsigned.
  const got = BigInt.asUintN(64, fn(...v.args.map((a) => BigInt(a))));
  check(
    got === BigInt(v.expected),
    `${v.f}(${v.args.join(", ")}) = ${got}, Lean semantics say ${v.expected}`,
  );
}

// A couple of properties checked directly against the running binary.
for (let n = 0; n < 16; n += 1) {
  const expected = BigInt("0123456789abcdef".charCodeAt(n));
  check(exports.hex_digit(BigInt(n)) === expected, `hex_digit(${n})`);
}
for (let s = 0; s < 256; s += 1) {
  for (const bit of [0n, 1n]) {
    const embedded = exports.lsb_embed(BigInt(s), bit);
    check(exports.lsb_extract(embedded) === bit, `lsb round-trip (${s}, ${bit})`);
    check(embedded >> 1n === BigInt(s) >> 1n, `lsb preserves high bits (${s}, ${bit})`);
  }
}

// Three-way agreement: the extracted binary against the JavaScript client
// (which `web/test.mjs` in turn pins to the Lean golden vectors).
const kernel = await loadKernel();
for (const [a, b] of [[0n, 0n], [1n, 2n], [0xda51n << 48n, 12345n], [123456789n, 987654321n]]) {
  check(kernel.mergeCids(a, b) === js.mergeCids(a, b), `merge_cids vs JS (${a}, ${b})`);
}
for (const [t, p] of [[3n, 7n], [5n, (1n << 44n) - 1n], [0n, 0n]]) {
  check(kernel.mkCid(t, p) === js.mkCid(t, p), `mk_cid vs JS (${t}, ${p})`);
  const c = kernel.mkCid(t, p);
  check(kernel.cidType(c) === js.cidType(c), `cid_type vs JS (${c})`);
  check(kernel.cidPayload(c) === js.cidPayload(c), `cid_payload vs JS (${c})`);
  check(kernel.cidPrefix(c) === js.cidPrefix(c), `cid_prefix vs JS (${c})`);
}
for (const n of [0, 7, 8, 1000, 5 * 1024 * 1024, 5 * 1024 * 1024 + 1]) {
  check(
    kernel.capacityBytes(n) === BigInt(js.capacityBytes(new Array(n))),
    `capacity_bytes vs JS (${n})`,
  );
  check(
    kernel.socialChunks(n) === BigInt(Math.ceil(n / js.SOCIAL_LIMIT)),
    `social_chunks vs ceil(n / SOCIAL_LIMIT) (${n})`,
  );
  check(kernel.fitsSocial(n) === (n <= js.SOCIAL_LIMIT), `fits_social vs JS (${n})`);
}
for (const [x, k] of [[70, 1], [3, 5], [0, 0]]) {
  const o = { l: x, m: x, n: x };
  check(kernel.rotate71(x, k) === BigInt(js.rotate71(o, k).l), `rotate71 vs JS (${x}, ${k})`);
  check(kernel.reflect59(x, k) === BigInt(js.reflect59(o, k).m), `reflect59 vs JS (${x}, ${k})`);
  check(kernel.dual47(x, k) === BigInt(js.dual47(o, k).n), `dual47 vs JS (${x}, ${k})`);
}
for (const s of [0, 1, 200, 255]) {
  for (const bit of [false, true]) {
    check(
      kernel.lsbEmbed(s, bit ? 1 : 0) === BigInt(js.embedBits([s], [bit])[0]),
      `lsb_embed vs JS (${s}, ${bit})`,
    );
    check(
      (kernel.lsbExtract(s) === 1n) === js.extractBits(1, [s])[0],
      `lsb_extract vs JS (${s})`,
    );
  }
}

// The digest and hex paths, assembled from the verified per-step exports,
// must reproduce the JavaScript client's `fnv1a`, `digest` and `hexEncode`.
for (const text of ["", "hello", "kant-zk-pastebin", "\u00e9\u00e8\u00ea"]) {
  const bytes = js.utf8(text);
  check(kernel.fnv1a(bytes) === js.fnv1a(bytes), `fnv1a vs JS ("${text}")`);
  check(kernel.hexEncode(bytes) === js.hexEncode(bytes), `hexEncode vs JS ("${text}")`);
  check(
    kernel.digest(bytes).join(",") === js.digest(bytes).join(","),
    `digest vs JS ("${text}")`,
  );
  check(kernel.witness(bytes) === js.witness(bytes), `witness vs JS ("${text}")`);
}
for (let i = 0; i < 8; i += 1) {
  const x = 0xdeadbeefcafebaben;
  check(
    kernel.u64Byte(x, i) === BigInt(js.u64Bytes(x)[i]),
    `u64_byte vs JS (byte ${i})`,
  );
}
for (const [a, b] of [[0, 0], [1, 2], [2, 1], [7, 13], [1000, 999]]) {
  check(kernel.cantorPair(a, b) === BigInt(js.pair(a, b)), `cantor_pair vs JS (${a}, ${b})`);
}

// --- delivery ------------------------------------------------------------
// Regression tests for the reported "wasm kernel: unavailable
// (kant_kernel.wasm failed validation) — falling back to the JS core": the
// loader used to hand a 404 error page to WebAssembly.validate.

import { createServer } from "node:http";
import { connect } from "node:net";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { kernelBytes as embeddedBytes, KERNEL_LENGTH } from "./kant-kernel-embedded.mjs";
import { kernelSource, KERNEL_URLS } from "./kant-wasm.mjs";

// The bundled base64 copy is the same binary, byte for byte.
const embedded = embeddedBytes();
check(embedded.length === wasmBytes.length, "embedded kernel has a different length");
check(KERNEL_LENGTH === wasmBytes.length, "KERNEL_LENGTH disagrees with the binary");
check(
  embedded.every((b, i) => b === wasmBytes[i]),
  "embedded kernel differs from web/kant_kernel.wasm — rerun scripts/embed-kernel.mjs",
);
check(WebAssembly.validate(embedded), "embedded kernel fails WebAssembly.validate");

// A host that serves only web/ answers /dist/kant_kernel.wasm with a 404 body.
// The loader must not mistake that for an invalid module: it falls back to the
// embedded copy and still gives a working kernel.
const notFound = createServer((_req, res) => {
  res.writeHead(404, { "content-type": "text/plain" });
  res.end("not found");
});
await new Promise((r) => notFound.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${notFound.address().port}`;
{
  const { bytes, source } = await kernelSource([new URL("/dist/kant_kernel.wasm", base)]);
  check(source.startsWith("embedded"), `404 should fall back to the embedded copy, got ${source}`);
  check(bytes.length === wasmBytes.length, "fallback returned the wrong bytes");
  const k = await loadKernel(new URL("/dist/kant_kernel.wasm", base));
  check(k.embedded === true, "loadKernel should report the embedded source");
  check(k.witness(js.utf8("hello")) === js.witness(js.utf8("hello")), "fallback kernel computes");
}
await new Promise((r) => notFound.close(r));

// A host that serves the real binary is preferred over the embedded copy, and
// a host that answers with something else entirely is reported honestly.
const serving = createServer((req, res) => {
  if (req.url === "/dist/kant_kernel.wasm") {
    res.writeHead(200, { "content-type": "application/wasm" });
    res.end(Buffer.from(wasmBytes));
  } else {
    res.writeHead(200, { "content-type": "text/html" });
    res.end("<!doctype html><title>single page app</title>");
  }
});
await new Promise((r) => serving.listen(0, "127.0.0.1", r));
const live = `http://127.0.0.1:${serving.address().port}`;
{
  const good = await kernelSource([new URL("/dist/kant_kernel.wasm", live)]);
  check(!good.source.startsWith("embedded"), "a served binary should be used in preference");
  check(good.bytes.every((b, i) => b === wasmBytes[i]), "served bytes differ from the tracked copy");
  // An SPA that answers every path with index.html: bytes arrive, but they are
  // HTML. The loader must recognise that rather than blame validation.
  const spa = await kernelSource([new URL("/nowhere/kant_kernel.wasm", live)]);
  check(spa.source.startsWith("embedded"), "an HTML body should fall back to the embedded copy");
}
await new Promise((r) => serving.close(r));

// The default candidate list finds the binary without reaching for `dist/`:
// `web/kant_kernel.wasm` is the first candidate and is tracked, so a checkout
// and a `web/`-only deployment both resolve it.
{
  const { source } = await kernelSource(KERNEL_URLS);
  check(!source.startsWith("embedded"), "the checkout copy should be found by default");
}

// The relay serves /dist/ even when its document root is web/. Build a throwaway
// tree — web/ as the static root, the kernel in the sibling dist/, and a
// README.md in the root that mount must never reach — so this exercises the real
// code path without depending on the gitignored `dist/` of a Lean build.
{
  const { createServer: createRelay, CONFIG } = await import("../server/relay.mjs");
  const tmp = await mkdtemp(join(tmpdir(), "kant-wasm-relay-"));
  try {
    const staticDir = join(tmp, "web");
    await mkdir(staticDir);
    await mkdir(join(tmp, "dist"));
    await writeFile(join(staticDir, "index.html"), "<!doctype html><title>static root</title>\n");
    await writeFile(join(tmp, "dist", "kant_kernel.wasm"), wasmBytes);
    await writeFile(join(tmp, "README.md"), "the repository root\n");

    const relay = createRelay({ ...CONFIG, staticDir });
    await new Promise((r) => relay.listen(0, "127.0.0.1", r));
    const port = relay.address().port;

    // Controls, so the 404s below cannot be vacuous: the server is up and the
    // static root answers, and the /dist/ mount reaches a file that exists.
    const rootRes = await fetch(`http://127.0.0.1:${port}/`);
    check(rootRes.ok, `the static root should answer, got HTTP ${rootRes.status}`);

    const res = await fetch(`http://127.0.0.1:${port}/dist/kant_kernel.wasm`);
    check(res.ok, `relay --static web should serve /dist/kant_kernel.wasm, got HTTP ${res.status}`);
    if (res.ok) {
      check(
        res.headers.get("content-type") === "application/wasm",
        "the relay should label the kernel application/wasm",
      );
      const got = new Uint8Array(await res.arrayBuffer());
      check(got.length === wasmBytes.length && got.every((b, i) => b === wasmBytes[i]),
        "the relay served the wrong bytes for the kernel");
    }
    // Nothing can reach the repository root through the /dist/ mount, for two
    // separate reasons, and this pins both.
    //
    // A literal `..` is gone before the relay sees it: the handler parses the
    // request with `new URL(req.url, …)`, and the WHATWG URL parser strips dot
    // segments. `fetch` would have done the same on the client side, so this
    // sends the path over a raw socket to reach the relay's own parser.
    const rawStatus = await rawStatusOf(port, "/dist/../README.md");
    check(rawStatus === 404,
      `a literal .. must not escape the mount (raw /dist/../README.md → ${rawStatus})`);
    check(!(await readmeVia(port, "/dist/../README.md")),
      "a literal .. served the repository root's README.md");

    // Percent-encoded traversal. `%2e%2e` is not actually a way past the URL
    // parser — the WHATWG spec counts `.%2e`, `%2e.` and `%2e%2e` as dot
    // segments, so both parsers collapse it before the relay sees anything. It
    // is kept because that is the fact worth pinning. `..%2f` *does* survive,
    // because an encoded slash is not a dot segment: it reaches the relay
    // verbatim, and only `serveStatic`'s refusal to decode it stops it.
    //
    // So the live risk is a `decodeURIComponent` added to the static path — a
    // natural change, to serve spaces and non-ASCII filenames — which would
    // turn `/dist/..%2fREADME.md` into a real traversal unless
    // `staticCandidates` still normalises and still refuses to leave distRoot.
    // Verified: dropping the decode, `path.normalize` and the `startsWith`
    // guard together makes this fail (HTTP 200, serving the root README).
    // Dropping the guard alone does not, and cannot: nothing that parses as a
    // URL reaches it. It is defence in depth behind the parser.
    for (const escape of ["/dist/%2e%2e/README.md", "/dist/..%2fREADME.md"]) {
      const r = await fetch(`http://127.0.0.1:${port}${escape}`);
      check(r.status === 404,
        `an encoded traversal must not escape the mount (${escape} → ${r.status})`);
      check(!(await readmeVia(port, escape)),
        `an encoded traversal served the repository root's README.md (${escape})`);
    }
    await new Promise((r) => relay.close(r));
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
}

if (failures === 0) {
  console.log(
    `ok — ${wasmBytes.length} byte module, ${expectedExports.length} exports, ` +
      `${vectors.length} golden vectors, agreement with the JS client, all checks passed`,
  );
} else {
  console.error(`${failures} check(s) failed`);
  process.exit(1);
}
