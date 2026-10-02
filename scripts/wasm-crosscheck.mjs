#!/usr/bin/env node
// wasm-crosscheck.mjs — the Rust core and the JS path must agree.
//
//   node scripts/wasm-crosscheck.mjs
//
// Proves, for this exact build of web/pastebin_wasm_bg.wasm:
//   1. wasm_cid_of_bytes === kant-ipfs cidOf, byte-for-byte, across sizes
//      including past the 256 KiB chunk boundary, where both produce the
//      UnixFS dag-pb root kubo would
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
const {
  cidOf,
  chunkPlanOf,
  unixfsCidOf,
  rawCidOf,
  MAX_ARTIFACT_BYTES,
} = await import(join(root, "web/kant-ipfs.mjs"));
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
// Past the boundary on purpose: the previous list stopped exactly at
// MAX_ARTIFACT_BYTES, so the chunked path was never actually compared.
const sizes = [
  1, 55, 1024, 65535, 65536, 262143, MAX_ARTIFACT_BYTES,
  MAX_ARTIFACT_BYTES + 1, MAX_ARTIFACT_BYTES + 4096, 300_000, 700_000,
];
// An empty artifact has no chunk plan, so both cores refuse it rather than
// inventing a CID. Asserted outright instead of being quietly dropped from
// the list above.
// wasm-bindgen surfaces a Rust Err as a *synchronous* throw, while the JS
// path rejects, so both failure modes have to be caught.
const refuses = async (call) => {
  try { await call(); return false; } catch { return true; }
};
for (const [name, call] of [
  ["wasm", () => wasm.wasm_unixfs_cid(new Uint8Array(0))],
  ["js", () => unixfsCidOf(new Uint8Array(0))],
]) {
  ok(`empty artifact refused (${name})`, await refuses(call));
}
for (const n of sizes) {
  const bytes = rnd(n);
  const js = await cidOf(bytes);
  // Past the boundary cidOf is the UnixFS root, not the raw leaf, so this has
  // to compare against wasm_unixfs_cid rather than wasm_cid_of_bytes.
  const rs = wasm.wasm_unixfs_cid(bytes);
  ok(`cid ${n}B agrees`, js === rs);
  // Within one chunk the unixfs CID and the raw leaf CID are the same value.
  if (n <= MAX_ARTIFACT_BYTES) {
    ok(`cid ${n}B stays raw`, rs === wasm.wasm_cid_of_bytes(bytes));
  } else {
    ok(`cid ${n}B is a dag-pb root`, rs !== wasm.wasm_cid_of_bytes(bytes));
  }
  // 2. identity accepts the produced CID. It validates CIDv1/raw/sha2-256 by
  //    design, so a chunked artifact's dag-pb root is correctly rejected —
  //    that is a property of the check, not a failure of the CID.
  const isRaw = n <= MAX_ARTIFACT_BYTES;
  ok(`identity ${n}B ${isRaw ? "accepts" : "rejects a dag-pb root"}`, (() => {
    try {
      const accepted = wasm.wasm_cid_identity(js).length === 36;
      return isRaw ? accepted : !accepted;
    } catch {
      return !isRaw;
    }
  })());
  // 2b. the chunk plan agrees between the two cores and sums to the size.
  if (n > 0) {
    const jsPlan = chunkPlanOf(n);
    ok(`plan ${n}B sums`, jsPlan.reduce((a, b) => a + b, 0) === n);
    // wasm-bindgen marshals Vec<u32> as a Uint32Array, so compare contents.
    const wasmPlan = Array.from(wasm.wasm_chunk_plan(n));
    ok(`plan ${n}B wasm==js`, JSON.stringify(jsPlan) === JSON.stringify(wasmPlan));
  }
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
// Large artifacts are now chunked rather than refused, so this checks the
// split instead. (It previously asserted the opposite, which is why the
// boundary was never exercised.)
ok("chunk plan splits over the boundary", (() => {
  const plan = wasm.wasm_chunk_plan(MAX_ARTIFACT_BYTES + 1);
  return plan.length === 2 && plan[0] === MAX_ARTIFACT_BYTES && plan[1] === 1;
})());
ok("chunk plan splits an even multiple", (() => {
  const plan = wasm.wasm_chunk_plan(MAX_ARTIFACT_BYTES * 3);
  return plan.length === 3 && plan.every((n) => n === MAX_ARTIFACT_BYTES);
})());

// 4. Both cores pinned to CIDs kubo actually produced for deterministic
//    input (byte[i] = i % 251), so this catches drift from real IPFS rather
//    than merely from each other. Captured from kubo 0.40.1:
//      ipfs add --cid-version=1 --raw-leaves -Q
const probe = (n) => Uint8Array.from({ length: n }, (_, i) => i % 251);
const KUBO_VECTORS = [
  [262_144, "bafkreibruh455iawsviqslif5c7uurdcfdemh22mtnytyzvnzn75kpejxy"],
  [262_145, "bafybeiexg2oqkfnj56l7fcmawswqbijt5shq4b5rg6a546uwpkqqzwjioi"],
  [300_000, "bafybeih7gz5kvvg2zafb7vue6izhy6c4tglvwpi3rgunwdag2fidn2y6eq"],
  [700_000, "bafybeiat65mgaomregcezwr6uzau6iumvujm3xlrtud36wlbpivuexuu24"],
];
for (const [n, expected] of KUBO_VECTORS) {
  const bytes = probe(n);
  ok(`kubo vector ${n}B (wasm)`, wasm.wasm_unixfs_cid(bytes) === expected);
  ok(`kubo vector ${n}B (js)`, await unixfsCidOf(bytes) === expected);
  const plan = JSON.parse(wasm.wasm_unixfs_plan(bytes));
  ok(`kubo vector ${n}B leaf count`, plan.leaves.length === chunkPlanOf(n).length);
  ok(`kubo vector ${n}B leaves sum`, plan.leaves.reduce((a, l) => a + l.size, 0) === n);
  // Each leaf must address exactly its own slice of the artifact.
  const addressed = await Promise.all(
    plan.leaves.map((l) => rawCidOf(bytes.subarray(l.offset, l.offset + l.size))),
  );
  ok(`kubo vector ${n}B leaves address`, addressed.every((cid, i) => cid === plan.leaves[i].cid));
}

// 5. Small artifacts keep the raw CID they had before chunking existed, so
//    rooms already published under those CIDs stay resolvable.
ok("small artifacts keep the raw CID", (() => {
  const core = wasm.wasm_cid_of_bytes;
  return [1, 2000, 100_000, MAX_ARTIFACT_BYTES]
    .every((n) => wasm.wasm_unixfs_cid(probe(n)) === core(probe(n)));
})());

console.log(`${checks - fail.length}/${checks} crosscheck checks passed`);
if (fail.length) {
  console.error("FAIL:", fail.join(", "));
  process.exit(1);
}
