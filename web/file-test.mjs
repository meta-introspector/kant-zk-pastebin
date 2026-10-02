// file-test.mjs — conformance checks for the file-drop layer.
//
// Two kinds of check, same shape as net-test.mjs:
//   1. the pure functions of `web/kant-file.mjs` — encrypt, chunk,
//      content-address, and the kzfile manifest's self-certification;
//   2. an end-to-end run of the real relay from `server/relay.mjs` with
//      two virtual agents that have never met: Alice drops a file (pin
//      every chunk, announce the manifest as a room line), Bob polls
//      the room, fetches every chunk by its digest, and decrypts the
//      file — plus the refusals: wrong room, wrong cid, tampered chunk.
//
// Run:  node web/file-test.mjs

import assert from "node:assert/strict";
import {
  CHUNK_SIZE, TAG_FILE, cidOf, encryptFile, decryptFile,
  manifest, manifestCore, manifestWitness, ofManifest, toManifest,
  printManifest, parseManifest,
} from "./kant-file.mjs";
import { roomOf, KantNode, parseMsg } from "./kant-net.mjs";
import { envelopeDecode, utf8 } from "./kantzk.mjs";
import { createServer, Rooms, CONFIG } from "../server/relay.mjs";
import { witness } from "./kantzk.mjs";
import crypto from "node:crypto";

let checks = 0;
const check = (name, fn) => { fn(); checks += 1; console.log(`  ok  ${name}`); };
const checkAsync = async (name, fn) => { await fn(); checks += 1; console.log(`  ok  ${name}`); };

const secret = Array.from(crypto.getRandomValues(new Uint8Array(32)));
const room = roomOf(secret);
const bytes = (n) => { // getRandomValues caps at 64 KiB per call
  const out = new Uint8Array(n);
  for (let off = 0; off < n; off += 65536) {
    crypto.getRandomValues(out.subarray(off, Math.min(off + 65536, n)));
  }
  return out;
};

// ------------------------------------------------------- the pure layer

console.log("the file codec (web/kant-file.mjs)");

check("a chunk's cid is the digest of its ciphertext", () => {
  const b = bytes(100);
  assert.equal(cidOf(b), witness(Array.from(b)));
});

await checkAsync("a file encrypts to chunks and decrypts back byte-exact", async () => {
  const data = bytes(CHUNK_SIZE * 2 + 137); // three chunks, ragged last
  const enc = await encryptFile(secret, "big.bin", "application/octet-stream", data);
  assert.equal(enc.cids.length, 3);
  const store = new Map(enc.cids.map((c, i) => [c, enc.chunks[i]]));
  const out = await decryptFile(secret,
    manifest(room, "alice", 1, enc.name, enc.mime, enc.size, enc.nonce, enc.cids),
    (cid) => store.get(cid));
  assert.deepEqual([...out], [...data]);
});

await checkAsync("the wrong room secret cannot decrypt the file", async () => {
  const data = bytes(500);
  const enc = await encryptFile(secret, "s.txt", "text/plain", data);
  const m = manifest(room, "alice", 1, enc.name, enc.mime, enc.size, enc.nonce, enc.cids);
  const store = new Map(enc.cids.map((c, i) => [c, enc.chunks[i]]));
  const other = Array.from(crypto.getRandomValues(new Uint8Array(32)));
  await assert.rejects(() => decryptFile(other, m, (cid) => store.get(cid)));
});

await checkAsync("a chunk that is not its own name is refused", async () => {
  const data = bytes(500);
  const enc = await encryptFile(secret, "s.txt", "text/plain", data);
  const m = manifest(room, "alice", 1, enc.name, enc.mime, enc.size, enc.nonce, enc.cids);
  await assert.rejects(() => decryptFile(secret, m, () => bytes(10)));
});

check("a manifest line certifies itself, and a forged one is refused", () => {
  const f = manifest(room, "alice", 1, "note.txt", "text/plain", 12,
    Array.from({ length: 12 }, () => 0), ["ab".repeat(32)]);
  const line = printManifest(f);
  const back = parseManifest(line);
  assert.ok(back);
  assert.equal(back.name, "note.txt");
  assert.equal(back.cids.length, 1);
  // a mangled line must not parse
  assert.equal(parseManifest(line.slice(0, -2) + "00"), null);
  // a line whose fields were swapped behind the witness's back is
  // refused: decode, rename the file, re-encode — the witness still
  // commits to "note.txt", so every peer throws the line away.
  const e = envelopeDecode(line);
  e.fields[3] = utf8("evil.txt");
  assert.equal(toManifest(e), null);
});

check("the manifest core commits to every field", () => {
  const f = manifest(room, "alice", 1, "a.txt", "text/plain", 1,
    Array.from({ length: 12 }, () => 7), ["cd".repeat(32)]);
  const g = { ...f, seq: 2 };
  assert.notEqual(manifestWitness(f), manifestWitness(g));
  assert.notEqual(manifestWitness(f), manifestWitness({ ...f, name: "b.txt" }));
  assert.notEqual(manifestWitness(f), manifestWitness({ ...f, cids: ["ef".repeat(32)] }));
});

// ------------------------------------------- the real relay, end to end

console.log("the real relay (server/relay.mjs)");

const cfg = { ...CONFIG, port: 0, host: "127.0.0.1", staticDir: "",
  passDb: "/tmp/kant-file-test/passes.sqlite", archiveDir: "/tmp/kant-file-test/archive" };
const server = createServer(cfg, new Rooms(cfg));
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;

await checkAsync("a block pins under its digest and serves back byte-exact", async () => {
  const b = bytes(4096);
  const cid = cidOf(b);
  const pin = await fetch(`${base}/room/${room}/block/${cid}`,
    { method: "POST", body: b });
  assert.equal(pin.status, 200);
  const j = await pin.json();
  assert.equal(j.cid, cid);
  assert.equal(j.bytes, b.length);
  const got = await fetch(`${base}/room/${room}/block/${cid}`);
  assert.equal(got.status, 200);
  assert.equal(got.headers.get("content-type"), "application/octet-stream");
  assert.deepEqual([...Buffer.from(await got.arrayBuffer())], [...b]);
});

await checkAsync("a block whose cid lies is refused", async () => {
  const b = bytes(64);
  const r = await fetch(`${base}/room/${room}/block/${"11".repeat(32)}`,
    { method: "POST", body: b });
  assert.equal(r.status, 400);
});

await checkAsync("an unknown block is a 404", async () => {
  const r = await fetch(`${base}/room/${room}/block/${"22".repeat(32)}`);
  assert.equal(r.status, 404);
});

await checkAsync("two strangers exchange a file through the relay", async () => {
  // Alice opens the room; Bob joins by the same secret.
  const alice = new KantNode({ peer: "alice", relay: base, secret });
  const bob = new KantNode({ peer: "bob", relay: base, secret });
  assert.equal(alice.room, bob.room);

  // Alice drops a file: encrypt, pin every chunk, announce the manifest.
  const data = bytes(CHUNK_SIZE + 100); // two chunks
  const enc = await encryptFile(secret, "drop.bin", "application/octet-stream", data);
  for (let i = 0; i < enc.cids.length; i += 1) {
    const r = await fetch(`${base}/room/${room}/block/${enc.cids[i]}`,
      { method: "POST", body: enc.chunks[i] });
    assert.equal(r.status, 200);
  }
  alice.seq += 1;
  const m = manifest(room, "alice", alice.seq, enc.name, enc.mime, enc.size, enc.nonce, enc.cids);
  await alice.publish(printManifest(m));

  // Bob polls the room and finds the manifest among the lines.
  const out = await bob.client.poll(room, { wait: 0 });
  for (const line of out.lines ?? []) bob.ingest(line);
  const found = (out.lines ?? []).map(parseManifest).find(Boolean);
  assert.ok(found, "bob saw the kzfile manifest");
  assert.equal(found.name, "drop.bin");

  // Bob fetches every chunk by digest and decrypts.
  const got = await decryptFile(secret, found,
    async (cid) => Buffer.from(await (await fetch(`${base}/room/${room}/block/${cid}`)).arrayBuffer()));
  assert.deepEqual([...got], [...data]);

  // The manifest is a room line like any other: a chat peer that does
  // not know kzfile still relays it (the relay is content-blind), and
  // the witness check keeps it honest.
  assert.equal(parseMsg(printManifest(m)), null, "kzfile is not mistaken for kzchat");
});

await checkAsync("a stranger without the secret cannot fetch the chunks", async () => {
  // The room name is the digest of the secret; a stranger who guesses a
  // wrong room gets nothing, and the right room without... well, the
  // room name IS the trust credential — so this check pins the other
  // side: a block pinned in one room is invisible in another.
  const b = bytes(128);
  const cid = cidOf(b);
  const r = await fetch(`${base}/room/${room}/block/${cid}`,
    { method: "POST", body: b });
  assert.equal(r.status, 200);
  const elsewhere = await fetch(`${base}/room/${"33".repeat(32)}/block/${cid}`);
  assert.equal(elsewhere.status, 404);
});

await checkAsync("the archive recorded the pins and the line", async () => {
  const fs = await import("node:fs");
  const dir = cfg.archiveDir;
  const names = fs.readdirSync(dir);
  assert.ok(names.length >= 1, "an archive file exists");
  const entries = fs.readFileSync(`${dir}/${names[0]}`, "utf8")
    .trim().split("\n").map((l) => JSON.parse(l));
  assert.ok(entries.some((e) => e.kind === "block"));
  assert.ok(entries.some((e) => e.kind === "line"));
});

server.close();
console.log(`\n${checks} checks passed.`);
