// test/test-kant-p2p.mjs — unit tests for kant-ipfs.mjs and kant-p2p.mjs.
// Network-free: kant-ipfs is tested through injectable rpc/gateway bases (a
// failing local port exercises every fallback path); kant-p2p through a
// scripted in-memory RelayClient that answers the relay's protocol surface.

import test from "node:test";
import assert from "node:assert/strict";
import {
  cidOf, cidBytes, base32NoPad, encodeCidRecord, decodeCidRecord,
  bytesToB64, b64ToBytes, ipfsAdd, ipfsCat, publishArtifact, fetchArtifact,
  MAX_ARTIFACT_BYTES,
} from "../web/kant-ipfs.mjs";
import { P2PApp } from "../web/kant-p2p.mjs";
import { RelayClient } from "../web/kant-net.mjs";
import { utf8, fromUtf8 } from "../web/kantzk.mjs";

const utf8Bytes = (s) => new TextEncoder().encode(s);

// ── CID shape ───────────────────────────────────────────────────────────

test("cidOf produces CIDv1 raw sha2-256 base32 with the right bytes", async () => {
  const data = utf8Bytes("hello kant");
  const cid = await cidOf(data);
  assert.match(cid, /^b[a-z2-7]+$/);
  const raw = cidBytes(cid);
  assert.equal(raw[0], 0x01, "CIDv1");
  assert.equal(raw[1], 0x55, "raw codec");
  assert.equal(raw[2], 0x12, "sha2-256");
  assert.equal(raw[3], 0x20, "32-byte digest");
  assert.equal(raw.length, 36);
});

test("cidOf is deterministic and content-addressed", async () => {
  const a = await cidOf(utf8Bytes("same"));
  const b = await cidOf(utf8Bytes("same"));
  const c = await cidOf(utf8Bytes("different"));
  assert.equal(a, b);
  assert.notEqual(a, c);
});

test("cidOf rejects artifacts over one chunk (client/node CID parity rule)", async () => {
  await assert.rejects(() => cidOf(new Uint8Array(MAX_ARTIFACT_BYTES + 1)));
});

test("base32NoPad matches RFC4648 lower alphabet without padding", () => {
  // cross-checked against python base64.b32encode: f→MY====, fo→MZXQ====, foo→MZXW6===
  assert.equal(base32NoPad(utf8Bytes("f")), "my");
  assert.equal(base32NoPad(utf8Bytes("fo")), "mzxq");
  assert.equal(base32NoPad(utf8Bytes("foo")), "mzxw6");
});

// ── base64 helpers ──────────────────────────────────────────────────────

test("base64 round-trip preserves arbitrary bytes", () => {
  const bytes = Uint8Array.from({ length: 1000 }, (_, i) => (i * 37 + 11) & 0xff);
  assert.deepEqual(b64ToBytes(bytesToB64(bytes)), bytes);
});

// ── record envelopes ────────────────────────────────────────────────────

test("kzcid record round-trip pinned and embedded", async () => {
  const bytes = utf8Bytes("artifact bytes");
  const pinnedRec = await encodeCidRecord({ peer: "p1", name: "a.bin", bytes, pinned: true });
  assert.equal(pinnedRec.pinned, true);
  assert.equal(pinnedRec.b64, undefined);
  assert.ok(decodeCidRecord(JSON.parse(JSON.stringify(pinnedRec))));

  const embedded = await encodeCidRecord({ peer: "p1", name: "a.bin", bytes, pinned: false });
  assert.equal(embedded.pinned, false);
  assert.equal(fromUtf8(b64ToBytes(embedded.b64)), "artifact bytes");
  assert.ok(decodeCidRecord(JSON.parse(JSON.stringify(embedded))));

  assert.equal(decodeCidRecord({ tag: "other" }), null);
  assert.equal(decodeCidRecord({ tag: "kzcid", cid: "nope" }), null);
  assert.equal(decodeCidRecord({ tag: "kzcid", cid: "bafk", pinned: false }), null, "embedded requires b64");
});

// ── fallback paths (kubo/gateway absent → null, never throw) ────────────

test("ipfsAdd returns null when kubo is unreachable", async () => {
  const out = await ipfsAdd(utf8Bytes("x"), "x.bin", "http://127.0.0.1:9"); // port 9: refuse
  assert.equal(out, null);
});

test("ipfsCat returns null when the gateway is unreachable", async () => {
  const out = await ipfsCat("bafkqaaa", "http://127.0.0.1:9", 300);
  assert.equal(out, null);
});

test("publishArtifact falls back to embedding when kubo is down", async () => {
  const rec = await publishArtifact({
    peer: "p1", name: "t.txt", bytes: utf8Bytes("no node here"),
    rpcBase: "http://127.0.0.1:9",
  });
  assert.equal(rec.via, "room");
  assert.equal(rec.pinned, false);
  assert.ok(rec.b64.length > 0);
});

test("fetchArtifact verifies CID integrity (lying gateway rejected)", async () => {
  const bytes = utf8Bytes("real content");
  const rec = await encodeCidRecord({ peer: "p1", name: "r.bin", bytes, pinned: true });
  // a gateway that serves WRONG bytes for the CID must be rejected
  const fakeFetch = async () => ({ ok: true, arrayBuffer: async () => utf8Bytes("evil").buffer });
  const origFetch = globalThis.fetch;
  globalThis.fetch = fakeFetch;
  try {
    const out = await fetchArtifact(rec, { gwBase: "http://gateway.example" });
    assert.equal(out, null, "mismatched bytes must not pass");
  } finally {
    globalThis.fetch = origFetch;
  }
  // embedded fallback path still verifies and returns bytes
  const emb = await encodeCidRecord({ peer: "p1", name: "r.bin", bytes, pinned: false });
  const viaRoom = await fetchArtifact(emb, { gwBase: "http://127.0.0.1:9" });
  assert.equal(viaRoom.via, "room");
  assert.deepEqual(viaRoom.bytes, bytes);
});

// ── p2p app over a scripted relay ───────────────────────────────────────

/** In-memory relay matching the kant-zk protocol surface. */
class FakeRelay {
  constructor() { this.rooms = new Map(); this.calls = []; }
  post(room, lines) {
    this.calls.push(["post", room, lines]);
    const ls = this.rooms.get(room) ?? [];
    ls.push(...lines);
    this.rooms.set(room, ls);
    return Promise.resolve({ cursor: ls.length });
  }
  poll(room) {
    this.calls.push(["poll", room]);
    return Promise.resolve({ cursor: (this.rooms.get(room) ?? []).length, lines: [] });
  }
  health() { return Promise.resolve({ ok: true }); }
}

function fakeRelayClient(app) {
  const fr = new FakeRelay();
  const client = new RelayClient("http://fake", { fetchImpl: async () => ({ ok: true, json: async () => ({}) }) });
  client.health = () => fr.health();
  client.post = (room, lines) => fr.post(room, lines);
  client.poll = (room, opts) => fr.poll(room, opts);
  app.relay = client;
  app._fake = fr;
  return app;
}

function newApp() {
  return fakeRelayClient(new P2PApp({ relayBase: "http://fake", room: "test-room", peer: "tester" }));
}

test("start announces presence into the room", async () => {
  const app = newApp();
  // never actually poll: stop before start's loop matters
  await app.start();
  app.stop();
  const [, room, lines] = app._fake.calls.find(([k]) => k === "post");
  assert.equal(room, "test-room");
  const rec = JSON.parse(lines[0]);
  assert.equal(rec.tag, "kzpeer");
  assert.ok(rec.peer.startsWith("tester#"));
});

test("publish pins via ipfs or embeds, and the room gets a kzcid line", async () => {
  const app = newApp();
  const bytes = utf8Bytes("room cargo");
  const rec = await app.publish("cargo.bin", bytes, { note: "demo" });
  assert.equal(rec.tag, "kzcid");
  assert.equal(rec.pinned, false, "no kubo in tests → embedded");
  assert.equal(await cidOf(bytes), rec.cid);
  const [, , lines] = app._fake.calls.find(([k]) => k === "post" && JSON.stringify(k) !== "x");
  const posted = app._fake.rooms.get("test-room").map((l) => JSON.parse(l));
  assert.ok(posted.some((o) => o.tag === "kzcid" && o.cid === rec.cid));
});

test("incoming kzcid records dedupe by CID and fire 'artifact' once", async () => {
  const app = newApp();
  const events = [];
  app.on("artifact", (r) => events.push(r.cid));
  const line = JSON.stringify(await encodeCidRecord({ peer: "other#1", name: "n", bytes: utf8Bytes("z"), pinned: false }));
  app.handleLine(line);
  app.handleLine(line); // same artifact again (even from the same peer)
  const otherPeer = JSON.stringify(await encodeCidRecord({ peer: "other#2", name: "n", bytes: utf8Bytes("z"), pinned: false }));
  app.handleLine(otherPeer); // different peer, same content → same CID → deduped
  assert.equal(events.length, 1);
});

test("own records are not re-emitted as artifacts", async () => {
  const app = newApp();
  const events = [];
  app.on("artifact", () => events.push(1));
  const mine = JSON.stringify({ tag: "kzcid", peer: app.id, name: "m", cid: "b" + "a".repeat(58), size: 1, pinned: true });
  app.handleLine(mine);
  assert.equal(events.length, 0);
});

test("foreign (non-JSON, non-tagged) lines are ignored gracefully", () => {
  const app = newApp();
  app.handleLine("this is not json");
  app.handleLine(JSON.stringify({ hello: 1 }));
  app.handleLine("");
  assert.equal(app.seen.size, 0);
});

test("oversized embedded records are refused before hitting the relay", async () => {
  const app = newApp();
  const big = { tag: "kzcid", peer: "x", name: "big", cid: "b" + "a".repeat(58), size: 1, pinned: false, b64: "A".repeat(70_000) };
  await assert.rejects(() => app.postRecord(big));
});

test("experiment merge-cids runs in-process via the proved kernel or reports absence", async () => {
  const app = newApp();
  const r = await app.experiment("merge-cids", { a: "1", b: "2" });
  if (r.result.error) {
    assert.match(r.result.error, /kernel/i);
  } else {
    assert.ok(r.result.merged !== undefined);
    assert.equal(typeof r.result.merged, "string");
  }
});

test("experiment room-digest fingerprints the published CID set", async () => {
  const app = newApp();
  await app.publish("x.txt", utf8Bytes("one"));
  await app.publish("y.txt", utf8Bytes("two"));
  const r = await app.experiment("room-digest", {});
  assert.equal(r.result.count, 2);
  assert.match(r.result.digest, /^\d+$/);
});

test("arist experiment degrades to a JSON error when glue is missing", async () => {
  const app = newApp();
  const r = await app.experiment("arist", { op: "api-base" });
  assert.ok(r.result.error ?? r.result.base !== undefined);
});

test("kzcidx results are announced back into the room", async () => {
  const app = newApp();
  await app.experiment("room-digest", {});
  const posted = app._fake.rooms.get("test-room").map((l) => JSON.parse(l));
  assert.ok(posted.some((o) => o.tag === "kzcidx" && o.kind === "room-digest"));
});
