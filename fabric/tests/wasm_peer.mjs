// The WebAssembly peer: it fetches a block from IPFS by address, computes the
// Lean-verified content digest of the bytes in the wasm kernel, and checks that
// the native Rust daemon computes the same digest over the same bytes. Then it
// writes a block of its own and reads it back from IPFS, closing the loop.
//
//   node fabric/tests/wasm_peer.mjs http://127.0.0.1:8190 <cid>
//
// Exit code 0 only when every check passes. The kernel is the artefact in
// web/kant_kernel.wasm that `lake exe emitwasm` produced; nothing here is a JS
// reimplementation of the digest.

import { createHash } from "node:crypto";

const [base, cidArg] = process.argv.slice(2);
if (!base || !cidArg) {
  console.error("usage: wasm_peer.mjs <fabric-base-url> <cid>");
  process.exit(2);
}

const { loadKernel } = await import(new URL("../../web/kant-wasm.mjs", import.meta.url));
const kernel = await loadKernel();
let failures = 0;
const check = (ok, msg) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${msg}`);
  if (!ok) failures += 1;
};
const hex = (bytes) => Buffer.from(bytes).toString("hex");

// 1. Fetch the block from the IPFS gateway, not from the fabric: this is the
//    transport both implementations share.
const gateway = process.env.FABRIC_IPFS_GATEWAY ?? "http://127.0.0.1:8081";
const res = await fetch(`${gateway}/ipfs/${cidArg}`);
check(res.ok, `gateway answered ${res.status} for ${cidArg}`);
const bytes = new Uint8Array(await res.arrayBuffer());

// 2. The address is the sha256 of the bytes, checked here independently.
const digest = createHash("sha256").update(bytes).digest();
const multibase = "b" + base32(Buffer.concat([Buffer.from([0x01, 0x55, 0x12, 0x20]), digest]));
check(multibase === cidArg, `bytes hash to the requested address (${multibase === cidArg})`);

// 3. The wasm kernel's digest over those same bytes.
const wasmDigest = hex(kernel.digest(bytes));
check(kernel.source.includes("kant_kernel.wasm"), `kernel loaded from ${kernel.source}`);

// 4. Ask the native side for its digest of the same bytes. A POST is the
//    exposed way to make the Rust implementation hash a payload; storing an
//    identical block again is a no-op in IPFS.
const post = await fetch(`${base}/blocks`, { method: "POST", body: bytes });
const stored = await post.json();
check(stored.ok === true, `fabric accepted the block (${post.status})`);
check(stored.cid === cidArg, `fabric computed the same CID (${stored.cid})`);
check(stored.kant_digest === wasmDigest, `rust and wasm digests agree (${stored.kant_digest})`);

// 5. Write a new block authored here, then read it back through IPFS.
const authored = new TextEncoder().encode(
  JSON.stringify({ from: "wasm-peer", digest: wasmDigest, at: new Date().toISOString() }),
);
const mine = await (await fetch(`${base}/blocks`, { method: "POST", body: authored })).json();
check(mine.ok === true, "fabric stored the wasm-authored block");
const back = new Uint8Array(await (await fetch(`${gateway}/ipfs/${mine.cid}`)).arrayBuffer());
check(hex(back) === hex(authored), `round trip through IPFS preserved the bytes (${mine.cid})`);
check(
  hex(kernel.digest(back)) === mine.kant_digest,
  "the daemon's digest of the wasm block matches the kernel",
);

console.log(failures === 0 ? "wasm peer: all checks passed" : `wasm peer: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

function base32(buf) {
  const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
  let out = "";
  let bits = 0;
  let value = 0;
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += alphabet[(value >> bits) & 31];
    }
  }
  if (bits > 0) out += alphabet[(value << (5 - bits)) & 31];
  return out;
}
