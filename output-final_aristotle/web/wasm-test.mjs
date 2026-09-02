// Conformance test for the Lean-extracted WebAssembly kernel.
//
//   lake exe emitwasm dist && node web/wasm-test.mjs
//
// It validates `dist/kant_kernel.wasm` with the engine's own validator,
// instantiates it, and checks every exported function against the golden
// vectors that `lake exe emitwasm` computed from the Lean semantics of the
// very same module (`dist/kernel-vectors.json`).

import { readFile } from "node:fs/promises";
import { loadKernel } from "./kant-wasm.mjs";
import * as js from "./kantzk.mjs";

const wasmBytes = await readFile(new URL("../dist/kant_kernel.wasm", import.meta.url));
const vectors = JSON.parse(
  await readFile(new URL("../dist/kernel-vectors.json", import.meta.url), "utf8"),
).vectors;

let failures = 0;
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
import { kernelBytes as embeddedBytes, KERNEL_LENGTH } from "./kant-kernel-embedded.mjs";
import { kernelSource, KERNEL_URLS } from "./kant-wasm.mjs";

// The bundled base64 copy is the same binary, byte for byte.
const embedded = embeddedBytes();
check(embedded.length === wasmBytes.length, "embedded kernel has a different length");
check(KERNEL_LENGTH === wasmBytes.length, "KERNEL_LENGTH disagrees with the binary");
check(
  embedded.every((b, i) => b === wasmBytes[i]),
  "embedded kernel differs from dist/kant_kernel.wasm — rerun scripts/embed-kernel.mjs",
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
  check(good.bytes.every((b, i) => b === wasmBytes[i]), "served bytes differ from dist/");
  // An SPA that answers every path with index.html: bytes arrive, but they are
  // HTML. The loader must recognise that rather than blame validation.
  const spa = await kernelSource([new URL("/nowhere/kant_kernel.wasm", live)]);
  check(spa.source.startsWith("embedded"), "an HTML body should fall back to the embedded copy");
}
await new Promise((r) => serving.close(r));

// The default candidate list finds the binary in a repository checkout.
{
  const { source } = await kernelSource(KERNEL_URLS);
  check(!source.startsWith("embedded"), "the checkout copy should be found by default");
}

// The relay serves /dist/ even when its document root is web/.
{
  const { createServer: createRelay, CONFIG } = await import("../server/relay.mjs");
  const relay = createRelay({
    ...CONFIG,
    staticDir: new URL(".", import.meta.url).pathname,
  });
  await new Promise((r) => relay.listen(0, "127.0.0.1", r));
  const port = relay.address().port;
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
  const escape = await fetch(`http://127.0.0.1:${port}/dist/../README.md`);
  check(escape.status === 404, "the /dist/ mount must not expose the repository root");
  await new Promise((r) => relay.close(r));
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
