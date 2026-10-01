#!/usr/bin/env node
// p2p-wasm-filetest.mjs — the room file-sharing path, end to end, on wasm.
//
//   node scripts/p2p-wasm-filetest.mjs
//
// Starts the real Node relay (server/relay.mjs) on a free port, joins two
// P2PApp peers into one room, has A publish a file (the Rust pastebin-wasm
// core computes the CID through kant-ipfs.mjs), waits for B to receive the
// kzcid record, fetches the bytes (embedded fallback — no kubo in CI), and
// verifies the bytes and CID agree on both sides.  Exits 0 only if every
// step holds.

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(fileURLToPath(new URL("..", import.meta.url)));
const port = 9401 + Math.floor(Math.random() * 80);
const base = `http://127.0.0.1:${port}`;

// 1. the relay
const relay = spawn(process.execPath,
  [join(root, "server", "relay.mjs"), "--port", String(port),
   "--static", join(root, "web"),
   "--pass-db", join(mkdtempSync(join(tmpdir(), "p2pft-")), "p.sqlite")],
  { stdio: ["ignore", "pipe", "pipe"] });
const up = new Promise((resolve, reject) => {
  const t = setTimeout(() => reject(new Error("relay did not start")), 8000);
  relay.stdout.on("data", (d) => {
    if (String(d).includes("listening")) { clearTimeout(t); resolve(); }
  });
  relay.on("error", reject);
});
await up;
console.log(`relay up on ${base}`);

// 2. two peers, one room; the wasm core loads over HTTP from the relay
const { P2PApp } = await import(join(root, "web/kant-p2p.mjs"));
const { wasmOnce } = await import(join(root, "web/kant-ipfs.mjs"));

const core = await wasmOnce();
if (!core) throw new Error("wasm core did not load");
console.log(`wasm core loaded (${typeof core.wasm_cid_of_bytes})`);

const room = `wasm-filetest-${Date.now().toString(36)}`;
const A = new P2PApp({ relayBase: base, room, peer: "peer-a" });
const B = new P2PApp({ relayBase: base, room, peer: "peer-b" });

const gotAt = [];
B.on("artifact", (rec) => gotAt.push(rec));
await A.start();
await B.start();
console.log(`both peers joined room ${room}`);

// 3. A publishes a file; the CID comes from the Rust core
const payload = new TextEncoder().encode(
  `kant pastebin wasm file-share proof ${Date.now()} ${"x".repeat(2048)}`);
// rpcBase "" disables kubo pinning: this proof is about the room path,
// which is what a CI runner (no IPFS daemon) can exercise.
const rec = await A.publish("proof.txt", payload, { rpcBase: "" });
console.log(`A published ${rec.name} cid=${rec.cid.slice(0, 16)}… via=${rec.pinned ? "ipfs" : "room"}`);

// 4. B sees the record and fetches the bytes
const deadline = Date.now() + 15000;
while (!gotAt.length && Date.now() < deadline) {
  await new Promise((r) => setTimeout(r, 300));
}
if (!gotAt.length) throw new Error("B never saw the kzcid record");
const seen = gotAt[0];
if (seen.cid !== rec.cid) throw new Error(`CID mismatch: ${seen.cid} != ${rec.cid}`);

const fetched = await B.fetch(seen, { gwBase: "" });
if (!fetched || !fetched.bytes) throw new Error("B could not fetch the bytes");
const same = Buffer.from(fetched.bytes).equals(Buffer.from(payload));
console.log(`B fetched ${fetched.bytes.length}B, bytes identical: ${same}`);

// 5. the wasm core certifies the CID on B's side too
const localCid = core.wasm_cid_of_bytes(fetched.bytes);
if (localCid !== rec.cid) throw new Error(`wasm recompute mismatch: ${localCid}`);
console.log(`wasm recompute agrees: ${localCid.slice(0, 16)}…`);

relay.kill();
A.stop(); B.stop();
rmSync(join(tmpdir(), "p2pft-"), { recursive: true, force: true });
if (!same) process.exit(1);
console.log("PASS: file shared room-to-room, CID computed by the Rust wasm core");
process.exit(0); // long-poll keeps the loop alive; leave explicitly
