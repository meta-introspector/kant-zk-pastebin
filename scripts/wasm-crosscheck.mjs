#!/usr/bin/env node
// wasm-crosscheck.mjs — the Rust core and the JS path must agree.
//
//   node scripts/wasm-crosscheck.mjs
//
// Proves, for this exact build of web/pastebin_wasm_bg.wasm:
//   1. wasm_cid_of_bytes === kant-ipfs cidOf, byte-for-byte, across sizes
//      from 0 to the 256 KiB single-chunk boundary;
//   2. wasm_cid_identity accepts every produced CID and rejects junk;
//   3. the kzcid record codec round-trips and refuses credential-shaped
//      fields;
//   4. chunk_plan bounds match MAX_ARTIFACT_BYTES.
// CI runs this after the bundle build (kant-cli.yml wires it in) so a Rust
// change that drifts from the JS/kubo contract fails the build.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const root = join(fileURLToPath(new URL("..", import.meta.url)));
const { cidOf, MAX_ARTIFACT_BYTES } = await import(join(root, "web/kant-ipfs.mjs"));
const wasm = await import(join(root, "web/pastebin_wasm.js"));
await wasm.default({
  module_or_path: readFileSync(join(root, "web/pastebin_wasm_bg.wasm")),
});

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };

const rnd = (n) => {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i += 65536) {
    crypto.getRandomValues(b.subarray(i, Math.min(i + 65536, n)));
  }
  return b;
};

// 1. CID agreement across the interesting sizes.
const sizes = [0, 1, 55, 1024, 65535, 65536, 262143, MAX_ARTIFACT_BYTES];
for (const n of sizes) {
  const bytes = rnd(n);
  const js = await cidOf(bytes);
  const rs = wasm.wasm_cid_of_bytes(bytes);
  ok(`cid ${n}B agrees`, js === rs);
  // 2. identity accepts every produced CID.
  ok(`identity ${n}B accepts`, (() => {
    try { return wasm.wasm_cid_identity(js).length === 36; } catch { return false; }
  })());
}

// 2b. identity rejects junk.
for (const junk of ["", "notacid", "b!!!", `b${"a".repeat(57)}x`]) {
  ok(`identity rejects ${JSON.stringify(junk.slice(0, 8))}`, (() => {
    try { wasm.wasm_cid_identity(junk); return false; } catch { return true; }
  })());
}

// 3. kzcid codec round-trip + credential guard.
const bytes = new TextEncoder().encode("hello world");
const cid = await cidOf(bytes);
const line = wasm.wasm_kzcid_record("peer-x", "hello.txt", cid, bytes.length, "demo", false, 1_700_000_000_000);
const parsed = JSON.parse(wasm.wasm_parse_kzcid_record(line));
ok("kzcid round-trip", parsed.cid === cid && parsed.tag === "kzcid" && parsed.size === bytes.length);
ok("kzcid guard refuses credential note", (() => {
  try { wasm.wasm_kzcid_record("p", "x", cid, 1, "leaked api_key here", false, 1); return false; }
  catch { return true; }
})());
ok("parse rejects junk line", (() => {
  try { wasm.wasm_parse_kzcid_record("{\"tag\":\"nope\"}"); return false; }
  catch { return true; }
})());

// 4. chunk plan bounds.
ok("chunk plan ok at boundary", (() => {
  try { return wasm.wasm_chunk_plan(MAX_ARTIFACT_BYTES)[0] === MAX_ARTIFACT_BYTES; }
  catch { return false; }
})());
ok("chunk plan refuses over", (() => {
  try { wasm.wasm_chunk_plan(MAX_ARTIFACT_BYTES + 1); return false; }
  catch { return true; }
})());

console.log(`${checks - fail.length}/${checks} crosscheck checks passed`);
if (fail.length) {
  console.error("FAIL:", fail.join(", "));
  process.exit(1);
}
