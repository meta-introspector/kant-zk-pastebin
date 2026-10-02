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
//
// Phase 2 repeats it with a multi-chunk artifact, which takes the UnixFS
// dag-pb path instead of the single-block one: the record carries a leaf
// list rather than the bytes (they would not fit in a relay line), and the
// fetch goes through a stub gateway standing in for an IPFS daemon, since CI
// has none. The CID is still computed and verified by the Rust core.

import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(fileURLToPath(new URL("..", import.meta.url)));
// 1. the relay.
//
// The port used to be chosen at random from a fixed 9401-9480 range, which
// collided with a relay left behind by an earlier run: the new process died of
// EADDRINUSE and the only symptom was an 8s timeout reading "relay did not
// start". Ask the OS for a free port instead, and report a real startup error
// instead of hiding it behind that timeout.
const freePort = () => new Promise((resolve, reject) => {
  const probeSrv = createServer();
  probeSrv.once("error", reject);
  probeSrv.listen(0, "127.0.0.1", () => {
    const { port } = probeSrv.address();
    probeSrv.close(() => resolve(port));
  });
});
const port = await freePort();
const base = `http://127.0.0.1:${port}`;

const relay = spawn(process.execPath,
  [join(root, "server", "relay.mjs"), "--port", String(port),
   "--static", join(root, "web"),
   "--pass-db", join(mkdtempSync(join(tmpdir(), "p2pft-")), "p.sqlite")],
  { stdio: ["ignore", "pipe", "pipe"] });
let relayErr = "";
relay.stderr.on("data", (d) => { relayErr += String(d); });
const up = new Promise((resolve, reject) => {
  const t = setTimeout(() => reject(new Error(`relay did not start on ${port}: ${relayErr.trim() || "no output"}`)), 20_000);
  relay.stdout.on("data", (d) => {
    if (String(d).includes("listening")) { clearTimeout(t); resolve(); }
  });
  relay.on("exit", (code) => { clearTimeout(t); reject(new Error(`relay exited ${code}: ${relayErr.trim()}`)); });
  relay.on("error", (e) => { clearTimeout(t); reject(e); });
});
await up;
console.log(`relay up on ${base}`);

// 2. two peers, one room; the wasm core loads over HTTP from the relay
const { P2PApp } = await import(join(root, "web/kant-p2p.mjs"));
const { wasmOnce } = await import(join(root, "web/kant-ipfs.mjs"));

const core = await wasmOnce();
if (!core) throw new Error("wasm core did not load");
console.log(`wasm core loaded (${typeof core.wasm_cid_of_bytes})`);

process.on("exit", () => relay.kill());
process.on("SIGINT", () => { relay.kill(); process.exit(130); });

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

// ── phase 2: a multi-chunk artifact, over the UnixFS dag-pb path ──────────
//
// Phase 1's payload is ~2 KB and rides inside the room record as base64. A
// zip cannot: base64 of 400 KB is ~533 KB and the relay answers 413 above
// 262144 B. So the record announces leaves and the bytes come from a
// gateway. There is no IPFS daemon in CI, so a stub stands in — it serves
// exactly one CID, the one under test, and nothing else.
const { MAX_ARTIFACT_BYTES: CHUNK, unixfsPlanOf } = await import(join(root, "web/kant-ipfs.mjs"));

// Deterministic, compressible-but-not-trivial content: pseudo-random bytes so
// the zip is a realistic multi-chunk payload rather than a run of zeros.
let seed = 0x2545f491;
const zip = Buffer.alloc(400_000);
for (let i = 0; i < zip.length; i += 1) {
  seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0;
  zip[i] = seed & 0xff;
}
const zipBytes = new Uint8Array(zip);
const zipPlan = await unixfsPlanOf(zipBytes);
if (!zipPlan.chunked || zipPlan.leaves.length < 2) {
  throw new Error(`zip should be chunked, got ${zipPlan.leaves.length} leaves`);
}
if (zip.length <= CHUNK) throw new Error("zip is not past the chunk boundary");
console.log(`\nzip: ${zip.length}B -> ${zipPlan.leaves.length} leaves, root ${zipPlan.root.slice(0, 16)}…`);

// A gateway that only knows this one root, served over plain HTTP.
const gw = createServer((req, res) => {
  const want = decodeURIComponent(req.url.replace(/^\/ipfs\//, ""));
  if (want !== zipPlan.root) { res.writeHead(404).end(); return; }
  res.writeHead(200, { "content-type": "application/octet-stream" });
  res.end(zip);
});
await new Promise((r) => gw.listen(0, "127.0.0.1", r));
const gwBase = `http://127.0.0.1:${gw.address().port}`;
console.log(`stub gateway up on ${gwBase} (serves only ${zipPlan.root.slice(0, 16)}…)`);

const zipRec = await A.publish("bundle.zip", zipBytes, { rpcBase: "" });
if (zipRec.cid !== zipPlan.root) {
  throw new Error(`published cid ${zipRec.cid} != planned ${zipPlan.root}`);
}
if (zipRec.b64 !== undefined) {
  throw new Error("a chunked record must not embed the bytes; they exceed a relay line");
}
if (!zipRec.chunked || zipRec.leaves.length !== zipPlan.leaves.length) {
  throw new Error("record should announce the same leaves as the plan");
}
console.log(`A published ${zipRec.name} cid=${zipRec.cid.slice(0, 16)}… leaves=${zipRec.leaves.length} (no b64)`);

gotAt.length = 0;
const zipDeadline = Date.now() + 15000;
while (!gotAt.length && Date.now() < zipDeadline) {
  await new Promise((r) => setTimeout(r, 300));
}
if (!gotAt.length) throw new Error("B never saw the zip record");
const zipSeen = gotAt[0];
if (zipSeen.cid !== zipRec.cid) throw new Error(`zip CID mismatch: ${zipSeen.cid} != ${zipRec.cid}`);

const zipFetched = await B.fetch(zipSeen, { gwBase });
if (!zipFetched || !zipFetched.bytes) throw new Error("B could not fetch the zip");
const zipSame = Buffer.from(zipFetched.bytes).equals(zip);
console.log(`B fetched ${zipFetched.bytes.length}B via=${zipFetched.via}, bytes identical: ${zipSame}`);

const zipLocal = core.wasm_unixfs_cid(zipFetched.bytes);
if (zipLocal !== zipRec.cid) throw new Error(`wasm recompute mismatch: ${zipLocal}`);
console.log(`wasm recompute agrees: ${zipLocal.slice(0, 16)}…`);

// A gateway that returns the wrong bytes must be rejected, not trusted.
const liar = createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/octet-stream" });
  res.end(Buffer.alloc(zip.length, 0x41));
});
await new Promise((r) => liar.listen(0, "127.0.0.1", r));
const rejected = await B.fetch(zipSeen, { gwBase: `http://127.0.0.1:${liar.address().port}` })
  .then(() => "accepted", () => "rejected");
if (rejected !== "rejected") throw new Error("a lying gateway was trusted");
console.log("a gateway serving the wrong bytes is rejected (root CID verified)");
liar.close();
gw.close();

// Always tear the relay down, including on a failed assertion above —
// otherwise a failing run leaves an orphan holding the port.
relay.kill();
A.stop(); B.stop();
gw?.close();
rmSync(join(tmpdir(), "p2pft-"), { recursive: true, force: true });
if (!same || !zipSame) process.exit(1);
console.log("\nPASS: single-block and multi-chunk artifacts shared room-to-room, CIDs computed by the Rust wasm core");
process.exit(0); // long-poll keeps the loop alive; leave explicitly
