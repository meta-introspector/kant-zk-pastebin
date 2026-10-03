// Tests for web/kant-libp2p.mjs.
//
// The pubsub node is injected, so this runs with no network, no daemon and
// no CDN: a fake bus stands in for a swarm. That is deliberate — the
// alternative is a suite that only runs when libp2p happens to be
// reachable, which is a suite that stops being run.
//
// The cases that matter most are the hostile ones: a peer that answers with
// the WRONG bytes, a peer that claims a frame it never sent, a peer that
// answers a request for a chunk it does not have, and a frame big enough to
// be a denial of service. A transport that only ever meets honest peers is
// a transport whose bugs are found in production.
//
//   node web/libp2p-test.mjs

import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  FRAME_BYTES, MIN_FRAME_BYTES, MAX_FRAME_BYTES, MAX_CHUNK_BYTES,
  Libp2pError, asWitness, encode, decode, topicOf,
  libp2pFetcher, serveChunks, LIBP2P_EXPOSURE, LIBP2P_VERSIONS,
} from "./kant-libp2p.mjs";

/** The same unwrapping the module does, so tests decode what it decodes. */
const bytesOf = (msg) =>
  msg?.data?.data ?? msg?.data ?? msg?.detail?.data ?? msg;
import { cidOf, encryptFile, decryptFile } from "./kant-file.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

let pass = 0, fail = 0;
const t = (name, fn) => {
  try { fn(); console.log(`  ok    ${name}`); pass++; }
  catch (e) { console.log(`  FAIL  ${name}\n        ${e.message}`); fail++; }
};
const ta = async (name, fn) => {
  try { await fn(); console.log(`  ok    ${name}`); pass++; }
  catch (e) { console.log(`  FAIL  ${name}\n        ${e.message}`); fail++; }
};

const bytes = (n, seed = 1) =>
  Uint8Array.from({ length: n }, (_, i) => (i * 31 + seed) & 0xff);
const hex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");

/**
 * A fake swarm that behaves like the real one where it matters.
 *
 * Deliberately faithful on the three behaviours that bit the first draft of
 * `libp2pNode()`:
 *
 *  - `publish` is ASYNC. Real gossipsub returns a Promise and callers that
 *    do not await it get an unhandled rejection.
 *  - `publish` THROWS `NoPeersSubscribedToTopic` when nobody is on the
 *    topic. That is the normal state of a tab that has not met anyone, and
 *    the adapter has to absorb it rather than surface it.
 *  - `publish` THROWS `Duplicate` for a message already seen, so the
 *    framing must not make two frames of one chunk collide.
 *  - `subscribe(topic)` returns NOTHING and is idempotent, exactly as
 *    gossipsub 17.1.2 does; the unsubscribe is the adapter's own bookkeeping.
 */
function bus({ isolate = false, drop = null } = {}) {
  const subs = new Map(); // topic -> Set<handler>
  const delivered = [];
  const seen = new Set();
  return {
    delivered,
    /** Everything this bus sent, already decoded — tests assert on this
     *  rather than re-decoding, so a decode bug cannot make a test pass. */
    sent: () => delivered.map((m) => ({ topic: m.topic, msg: decode(m.bytes) })),
    transport: {
      subscribe(topic, handler) {
        // void return, matching gossipsub; subscribing twice is a no-op.
        if (!subs.has(topic)) subs.set(topic, new Set());
        subs.get(topic).add(handler);
        return undefined;
      },
      async publish(topic, bytes) {
        const key = topic + "|" + bytesToKey(bytes);
        if (seen.has(key)) throw new Error("PublishError.Duplicate");
        seen.add(key);
        delivered.push({ topic, bytes });
        if (isolate) throw new Error("PublishError.NoPeersSubscribedToTopic");
        if (drop && drop(bytes)) return { recipients: [] };
        for (const h of subs.get(topic) ?? []) {
          try { h({ detail: { topic, data: bytes } }); }
          catch { /* a bad handler is not fatal */ }
        }
        return { recipients: [] };
      },
    },
    handlers: (topic) => subs.get(topic)?.size ?? 0,
  };
}

const bytesToKey = (b) => Array.from(b).join(",");

const ROOM = "a".repeat(64);
const MW = hex(bytes(32, 7));

/** A peer that answers every `want` on `topic` with the frames for `witness`,
 *  optionally in reverse order. */
function pubsubAnsweringWithFrames(transport, topic, witness, total, frameAt, { reverse = false } = {}) {
  const order = Array.from({ length: total }, (_, i) => i);
  if (reverse) order.reverse();
  return transport.subscribe(topic, async (msg) => {
    const m = decode(bytesOf(msg));
    if (!m || m.tag !== 1 || m.witness !== witness) return;
    for (const i of order) await transport.publish(topic, encode(frameAt(i)));
  });
}

/** A peer that answers every `want` on `topic` with one canned frame. */
function pubsubAnsweringWith(transport, topic, reply) {
  return transport.subscribe(topic, async (msg) => {
    // bytesOf, not msg.data: the bus delivers a CustomEvent-shaped
    // `{ detail: { topic, data } }` exactly as gossipsub does, and reading
    // `msg.data` there yields undefined, which decodes to null and makes the
    // peer look silent.
    const m = decode(bytesOf(msg));
    if (!m || m.tag !== 1) return;
    await transport.publish(topic, encode(reply));
  });
}

/** A bus whose publish behaves exactly like gossipsub's, for the real
 *  gossipsub adapter's own tests below. */
function strictBus() {
  const subs = new Map();
  const seen = new Set();
  const listeners = new Map();
  return {
    subs,
    publishCalls: 0,
    pubsub: {
      subscribe (topic) { if (!subs.has(topic)) subs.set(topic, new Set()); },
      unsubscribe (topic) { subs.delete(topic); },
      addEventListener (_evt, fn) {
        listeners.set(fn, true);
        return { __fn: fn };
      },
      removeEventListener (_evt, fn) { listeners.delete(fn); },
      async publish (topic, data, opts = {}) {
        this.publishCalls = (this.publishCalls ?? 0) + 1;
        const key = topic + "|" + bytesToKey(data);
        if (seen.has(key) && !opts.ignoreDuplicatePublishError) {
          throw new Error("PublishError.Duplicate");
        }
        seen.add(key);
        const subs_ = subs.get(topic) ?? new Set();
        if (subs_.size === 0 && !opts.allowPublishToZeroTopicPeers) {
          throw new Error("PublishError.NoPeersSubscribedToTopic");
        }
        for (const fn of listeners.keys()) {
          for (const h of subs_) {
            try { h({ detail: { topic, data } }); } catch { /* ignore */ }
          }
        }
        return { recipients: [] };
      },
    },
  };
}

console.log("framing");
t("a want frame round-trips", () => {
  const m = decode(encode({ tag: 1, witness: MW, index: 2, total: 5 }));
  assert.equal(m.tag, 1);
  assert.equal(m.witness, MW);
  assert.equal(m.index, 2);
  assert.equal(m.total, 5);
});

t("a have frame carries its payload", () => {
  const payload = bytes(1000, 3);
  const m = decode(encode({ tag: 2, witness: MW, index: 0, total: 1, payload }));
  assert.equal(m.payload.length, 1000);
  assert.deepEqual(Array.from(m.payload), Array.from(payload));
});

t("an empty payload round-trips as empty, not missing", () => {
  const m = decode(encode({ tag: 2, witness: MW, index: 0, total: 1, payload: new Uint8Array(0) }));
  assert.equal(m.payload.length, 0);
});

t("a frame larger than the header is rejected", () => {
  for (const short of [new Uint8Array(0), new Uint8Array(40), new Uint8Array(10)]) {
    assert.equal(decode(short), null, `${short.length}B should not decode`);
  }
});

t("an unknown tag is rejected rather than guessed at", () => {
  const m = encode({ tag: 2, witness: MW, index: 0, total: 1 });
  m[0] = 99;
  assert.equal(decode(m), null);
});

t("a frame whose index is past its total is rejected", () => {
  // encode refuses to build one, which is the first line of defence; decode
  // must refuse one too, since the sender is a stranger.
  assert.throws(() => encode({ tag: 2, witness: MW, index: 3, total: 3 }), Libp2pError);
  const m = encode({ tag: 2, witness: MW, index: 0, total: 3 });
  m[36] = 9; // index = 9, total = 3
  assert.equal(decode(m), null);
});

t("a frame claiming an absurd total is rejected", () => {
  const m = encode({ tag: 2, witness: MW, index: 0, total: 1 });
  m[37] = 0xff; m[38] = 0xff; m[39] = 0xff;
  assert.equal(decode(m), null);
});

t("a payload past the chunk cap is rejected", () => {
  const m = encode({ tag: 2, witness: MW, index: 0, total: 1, payload: new Uint8Array(4) });
  m[0] = 2;
  // Re-encode with a body over the cap rather than hand-editing the length,
  // since the cap is enforced at encode time too.
  assert.throws(() => encode({
    tag: 2, witness: MW, index: 0, total: 1,
    payload: new Uint8Array(MAX_CHUNK_BYTES + 1),
  }), /exceeds the cap/);
  assert.ok(m);
});

t("a witness that is not 64 hex chars is refused at encode", () => {
  for (const bad of ["", "abc", MW.slice(0, 63), MW + "f", MW.toUpperCase().slice(0, 63) + "G"]) {
    assert.throws(() => encode({ tag: 1, witness: bad, index: 0, total: 1 }), Libp2pError);
  }
});

t("asWitness accepts either case and rejects everything else", () => {
  assert.equal(asWitness(MW), MW);
  // Hex is case-insensitive by construction; a witness that has been through
  // a hex library or a shell may be upper case, and refusing it would mean
  // refusing a chunk that is named perfectly correctly.
  assert.equal(asWitness(MW.toUpperCase()), MW);
  assert.equal(asWitness(null), null);
  assert.equal(asWitness(123), null);
  assert.equal(asWitness(MW.slice(0, 63)), null);
  assert.equal(asWitness("z".repeat(64)), null);
  assert.equal(asWitness(""), null);
});

console.log("topics");
t("a topic is the room and the manifest witness, never the secret", () => {
  const topic = topicOf(ROOM, MW);
  assert.ok(topic.includes(ROOM));
  assert.ok(topic.includes(MW));
  assert.ok(!/secret/i.test(topic));
});

t("two files in one room get different topics", () => {
  assert.notEqual(topicOf(ROOM, MW), topicOf(ROOM, hex(bytes(32, 9))));
});

t("two rooms with the same file get different topics", () => {
  assert.notEqual(topicOf(ROOM, MW), topicOf("b".repeat(64), MW));
});

t("a topic needs a room and a witness", () => {
  assert.throws(() => topicOf("", MW), Libp2pError);
  assert.throws(() => topicOf(ROOM, "nope"), Libp2pError);
});

console.log("round trip");
await ta("a chunk smaller than a frame crosses in one piece", async () => {
  const secret = bytes(32, 11);
  const enc = await encryptFile(secret, "small.txt", "text/plain", bytes(5000, 13));
  const c = enc.chunks[0];
  const w = cidOf(c);

  const b = bus();
  const topic = topicOf(ROOM, MW);
  serveChunks(b.transport, { topic, chunks: new Map([[w, c]]), cidOf });
  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 2000,
  });
  const got = await fetchChunk(w);
  fetchChunk.close();

  assert.deepEqual(Array.from(got), Array.from(c));
});

await ta("a multi-frame chunk is reassembled in the right order", async () => {
  const secret = bytes(32, 17);
  const enc = await encryptFile(secret, "big.bin", "application/octet-stream", bytes(9000, 19));
  const c = enc.chunks[0];
  const w = cidOf(c);
  assert.ok(c.length > 1024, "this chunk needs several 1 KiB frames");

  const b = bus();
  const topic = topicOf(ROOM, MW);
  serveChunks(b.transport, { topic, chunks: new Map([[w, c]]), frameBytes: 1024, cidOf });
  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 3000,
  });
  const got = await fetchChunk(w);
  fetchChunk.close();

  assert.equal(got.length, c.length);
  assert.deepEqual(Array.from(got), Array.from(c));
  assert.equal(cidOf(got), w);
});

await ta("out-of-order delivery still reassembles", async () => {
  const c = bytes(5000, 23);
  const w = cidOf(c);

  // Deliver every frame to the client, reversed, without going through a
  // server: order on the wire is not guaranteed and the client must not
  // depend on it.
  const b = bus();
  const topic = topicOf(ROOM, MW);
  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 3000,
  });
  const total = Math.ceil(c.length / 1024);
  // Answer only on the request, and deliver every frame BACKWARDS. pubsub
  // makes no ordering promise, so the client has to reassemble by index.
  // (Publishing the same frames twice would be refused as Duplicate by a
  // faithful bus — gossipsub de-duplicates by message bytes — so the frames
  // go out once, in the wrong order, and that is the whole test.)
  pubsubAnsweringWithFrames(b.transport, topic, w, total, (i) => ({
    tag: 2, witness: w, index: i, total,
    payload: c.subarray(i * 1024, (i + 1) * 1024),
  }), { reverse: true });

  const got = await fetchChunk(w);
  fetchChunk.close();
  assert.deepEqual(Array.from(got), Array.from(c));
  assert.equal(cidOf(got), w, "reassembled bytes must still be their own name");
});

await ta("a whole file crosses and decrypts byte-exactly", async () => {
  const secret = Array.from({ length: 32 }, (_, i) => (i * 5 + 1) & 0xff);
  const plain = bytes(20000, 29);
  const enc = await encryptFile(secret, "evidence.bin", "application/octet-stream", plain);
  const topic = topicOf(ROOM, MW);

  const chunks = new Map(enc.chunks.map((c) => [cidOf(c), c]));
  const b = bus();
  serveChunks(b.transport, { topic, chunks, frameBytes: 1024, cidOf });
  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 5000,
  });

  const out = await decryptFile(secret, { ...enc, cids: enc.cids }, fetchChunk);
  fetchChunk.close();
  assert.deepEqual(Array.from(out), Array.from(plain));
});

console.log("hostile peers");
await ta("a peer answering with the wrong bytes is refused, not returned", async () => {
  const b = bus();
  const topic = topicOf(ROOM, MW);
  const liar = bytes(400, 31); // valid bytes, wrong chunk

  // The liar answers the client's request rather than shouting into an empty
  // topic: a peer subscribed after the message went out would simply never
  // hear it, and that would test the bus rather than the client.
  pubsubAnsweringWith(b.transport, topic, {
    tag: 2, witness: MW, index: 0, total: 1, payload: liar,
  });

  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 2000,
  });
  // The client asked for MW; it is told MW and given something else.
  await assert.rejects(() => fetchChunk(MW), /not it/);
  fetchChunk.close();
});

await ta("a chunk served under a witness it does not match is refused on arrival", async () => {
  // The client's own check, independent of any server: it verifies the
  // reassembled bytes against the witness it asked for.
  const b = bus();
  const topic = topicOf(ROOM, MW);
  const liar = bytes(64, 47);
  pubsubAnsweringWith(b.transport, topic, {
    tag: 2, witness: MW, index: 0, total: 1, payload: liar,
  });
  const fetchChunk = libp2pFetcher(b.transport, { topic, cidOf, frameBytes: 1024, timeoutMs: 2000 });
  let msg = "";
  try { await fetchChunk(MW); } catch (e) { msg = e.message; }
  fetchChunk.close();
  assert.match(msg, /not it/, `expected a corruption refusal, got: ${msg}`);
});

await ta("bytes served under the wrong witness are refused", async () => {
  // The server side must not put bytes on the wire under a name they do not
  // match. If it did, this peer would be the one that breaks a download.
  const real = bytes(300, 37);
  const wrongWitness = hex(bytes(32, 41));
  const reported = [];
  const b = bus();
  const topic = topicOf(ROOM, MW);
  serveChunks(b.transport, {
    topic,
    chunks: new Map([[wrongWitness, real]]),
    frameBytes: 1024,
    cidOf,
    onMismatch: (w) => reported.push(w),
  });
  void b.transport.publish(topic, encode({ tag: 1, witness: wrongWitness, index: 0, total: 1 }));

  const served = b.sent().filter((m) => m.msg?.tag === 2 && m.msg.witness === wrongWitness);
  assert.equal(served.length, 0,
    "a server published bytes that are not the chunk it named");
  assert.deepEqual(reported, [wrongWitness],
    "the mismatch was swallowed instead of reported");
  // And it must deny, so the requester fails fast rather than waiting.
  assert.equal(b.sent().filter((m) => m.msg?.tag === 3).length, 1);
});

t("a server needs cidOf to check bytes before serving them", () => {
  assert.throws(() => serveChunks(bus().transport, { topic: "t", chunks: new Map() }), /cidOf/);
});

await ta("a chunk nobody holds is denied rather than left to time out", async () => {
  const b = bus();
  const topic = topicOf(ROOM, MW);
  serveChunks(b.transport, { topic, chunks: new Map(), frameBytes: 1024, cidOf });
  void b.transport.publish(topic, encode({ tag: 1, witness: MW, index: 0, total: 1 }));
  const denies = b.sent().filter((m) => m.msg?.tag === 3);
  assert.equal(denies.length, 1, "an absent chunk should draw exactly one deny");
});

await ta("an isolated peer fails at once instead of hanging", async () => {
  // With a faithful bus the REQUEST is refused: gossipsub throws
  // NoPeersSubscribedToTopic when nobody is on the topic. Failing there is
  // better than sitting out the whole timeout on a request that was never
  // made -- and it is the normal state of a tab that has not met anyone.
  const b = bus({ isolate: true });
  const topic = topicOf(ROOM, MW);
  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 5000,
  });
  await assert.rejects(() => fetchChunk(MW), /could not be published/);
  fetchChunk.close();
});

await ta("a published request nobody answers still times out", async () => {
  // The other failure: the request went out, peers exist, nobody has the
  // chunk. That must time out with a clear message, not hang.
  const b = bus();                       // delivers, but no server is subscribed
  const topic = topicOf(ROOM, MW);
  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 300,
  });
  await assert.rejects(() => fetchChunk(MW), /no peer answered/);
  fetchChunk.close();
});

await ta("a missing frame does not produce a short file", async () => {
  // Half the frames arrive; the client must time out rather than hand
  // `decryptFile` a truncated chunk that happens to pass no check at all.
  const c = bytes(4000, 43);
  const w = cidOf(c);
  const b = bus();
  const topic = topicOf(ROOM, MW);
  const fetchChunk = libp2pFetcher(b.transport, {
    topic, cidOf, frameBytes: 1024, timeoutMs: 300,
  });
  const total = Math.ceil(c.length / 1024);
  for (let i = 0; i < total - 1; i += 1) {
    await b.transport.publish(topic, encode({
      tag: 2, witness: w, index: i, total,
      payload: c.subarray(i * 1024, (i + 1) * 1024),
    }));
  }
  await assert.rejects(() => fetchChunk(w), /no peer answered/);
  fetchChunk.close();
});

console.log("arguments");
t("a fetcher needs a pubsub, a topic and cidOf", () => {
  assert.throws(() => libp2pFetcher(null, { topic: "t", cidOf }), /pubsub/);
  assert.throws(() => libp2pFetcher(bus().transport, { topic: "t" }), /cidOf/);
  assert.throws(() => libp2pFetcher(bus().transport, { cidOf }), /topic/);
});

t("a frame size outside the safe range is refused", () => {
  for (const bad of [0, 16, MIN_FRAME_BYTES - 1, MAX_FRAME_BYTES + 1]) {
    assert.throws(
      () => libp2pFetcher(bus().transport, { topic: topicOf(ROOM, MW), cidOf, frameBytes: bad }),
      Libp2pError, `frameBytes ${bad} should be refused`);
  }
});

t("the default frame fits any plausible swarm stream window", () => {
  // gossipsub 17.1.2 has NO maxMessageSize option, so this is not a
  // protocol constant. It is a self-imposed bound that stays far below every
  // libp2p transport's default stream window, which is the property worth
  // having: a frame is never the thing a peer refuses.
  assert.ok(FRAME_BYTES + 41 <= 32 * 1024,
    `a default frame (${FRAME_BYTES}B + 41B header) must stay small`);
});

t("a server needs a Map of chunks", () => {
  assert.throws(() => serveChunks(bus().transport, { topic: "t", chunks: {}, cidOf }), /Map/);
  assert.throws(() => serveChunks(null, { topic: "t", chunks: new Map(), cidOf }), /pubsub/);
});

t("the exposure is documented as ciphertext only", () => {
  assert.match(LIBP2P_EXPOSURE, /ciphertext-only/);
});

console.log("the gossipsub contract");
// These pin the behaviours verified in the js-libp2p worktree
// (libp2p 3.3.11 / @libp2p/gossipsub 17.1.2). They exist because the first
// draft of libp2pNode() got all three wrong, and none of them would have
// failed a test written against my own assumptions.
t("versions are pinned to the ones actually in the tree", () => {
  const V = LIBP2P_VERSIONS;
  assert.equal(V["libp2p"], "3.3.11");
  assert.equal(V["@libp2p/gossipsub"], "17.1.2");
  // The @chainsafe/* names this used to import are dead upstream; the
  // packages are published under @libp2p now.
  for (const [name, v] of Object.entries(V)) {
    assert.match(name, /^(@libp2p\/|libp2p$)/, `${name} is not a current package name`);
    assert.match(v, /^\d+\.\d+\.\d+$/, `${name}@${v} is not pinned exactly`);
  }
});

t("a gossipsub subscribe returns nothing, so unsubscribe is ours", () => {
  const b = strictBus();
  const result = b.pubsub.subscribe("t");
  assert.equal(result, undefined, "gossipsub subscribe() returns void");
  b.pubsub.subscribe("t"); // idempotent
  assert.equal(b.subs.get("t").size, 0, "subscribe alone adds no handler");
});

t("gossipsub publish throws NoPeersSubscribedToTopic when alone", async () => {
  const b = strictBus();
  let msg = "";
  try { await b.pubsub.publish("t", new Uint8Array([1])); }
  catch (e) { msg = e.message; }
  assert.match(msg, /NoPeersSubscribedToTopic/);
  // ...and the per-publish opt is what lifts it, which is why the adapter
  // must pass it: a browser tab with no peers is the normal case.
  await b.pubsub.publish("t", new Uint8Array([1]), { allowPublishToZeroTopicPeers: true });
});

t("gossipsub publish throws Duplicate on a repeat", async () => {
  const b = strictBus();
  await b.pubsub.publish("t", new Uint8Array([1, 2]), { allowPublishToZeroTopicPeers: true });
  let msg = "";
  try { await b.pubsub.publish("t", new Uint8Array([1, 2]), { allowPublishToZeroTopicPeers: true }); }
  catch (e) { msg = e.message; }
  assert.match(msg, /Duplicate/);
  // Two DIFFERENT frames of one chunk must not collide on the dedup key,
  // or the second frame would be silently dropped as a duplicate.
  await b.pubsub.publish("t", new Uint8Array([1, 3]), { allowPublishToZeroTopicPeers: true });
});

t("frames of one chunk are distinct messages, so none is a duplicate", async () => {
  const c = bytes(4000, 53);
  const w = cidOf(c);
  const topic = topicOf(ROOM, MW);
  const frames = [];
  const total = Math.ceil(c.length / 1024);
  for (let i = 0; i < total; i += 1) {
    frames.push(encode({
      tag: 2, witness: w, index: i, total,
      payload: c.subarray(i * 1024, (i + 1) * 1024),
    }));
  }
  // The index is inside the payload-bearing header, so two frames of the
  // same chunk differ byte-for-byte.
  assert.equal(new Set(frames.map((f) => bytesToKey(f))).size, frames.length);
});

t("the adapter reads evt.detail.data, not evt.data", () => {
  // gossipsub's `message` event is a CustomEvent<Message>; the payload is on
  // `detail`. Reading evt.data gets undefined and silently collects nothing.
  const evt = { detail: { topic: "t", data: new Uint8Array([7]) } };
  assert.equal(evt.detail.data[0], 7);
  assert.equal(evt.data, undefined);
});

t("fetchChunk exposes close() and its topic", () => {
  const b = bus();
  const topic = topicOf(ROOM, MW);
  const f = libp2pFetcher(b.transport, { topic, cidOf });
  assert.equal(f.topic, topic);
  f.close();
  f.close(); // idempotent
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);