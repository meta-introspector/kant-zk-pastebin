// kant-libp2p.mjs — a third place for a file's chunks to live, beside the
// relay's own block store and IPFS.
//
// `kant-file.mjs` never decides where a chunk is: `decryptFile` takes a
// `fetchChunk` callback and checks the returned bytes against the chunk's
// Kant witness itself. That injection point is the whole reason this module
// can exist without touching the crypto core, the line format, or the relay.
// A `libp2pFetcher` is just another `fetchChunk`.
//
// What crosses the wire is CIPHERTEXT, never plaintext. A chunk is already
// AES-GCM under the room key before it reaches this module, so a peer that
// is in the topic but not in the room learns a file's size and chunk count
// and nothing else. The room secret never leaves the peers, which is the
// same property the relay path has and the reason this is safe to run on a
// public swarm.
//
// Two constraints shape the design:
//
//  - CHUNK_SIZE is 256 KiB. js-libp2p's gossipsub 17.1.2 has NO
//    `maxMessageSize` option at all — I had claimed a 64 KiB cap and cited it
//    as fact; that number is go-libp2p's, not this codebase's. The real
//    constraint is upstream of gossipsub: the swarm's stream and muxer
//    limits, which differ per transport and per peer. So the frame size here
//    is a PARAMETER bounded to something any plausible swarm accepts, rather
//    than a number pretending to be a constant of the protocol. Frames stay
//    well under the smallest limit that matters and are reassembled by index.
//  - A topic name is public. It is therefore derived from the ROOM (which
//    the relay already knows) and the MANIFEST WITNESS (which every peer in
//    the room already knows), and never from the room secret. A secret-derived
//    topic would hand a passive observer a hash to grind.
//
// The pubsub node is injected, never imported: `{ subscribe, publish }`.
// `libp2pNode()` below builds a real one from esm.sh, but nothing in this
// file requires it, so the tests need no network and no daemon.

// The envelope. A binary header rather than JSON, because base64 inside JSON
// would inflate every chunk by a third to describe bytes we already have.
//
//   0      tag       u8    1 = want, 2 = have, 3 = deny
//   1..33  witness   32B   the Kant witness of the chunk (64 hex chars)
//   33..37 index     u32   frame index, big endian
//   37..41 total     u32   frame count for this chunk
//   41..   payload   rest  frame bytes on a `have`; empty otherwise
const TAG_WANT = 1, TAG_HAVE = 2, TAG_DENY = 3;
const HEADER = 41;
const U32 = 4294967296;

/**
 * Frame size for the wire: 16 KiB, plus the 41-byte header.
 *
 * Deliberately conservative and deliberately a PARAMETER. gossipsub 17.1.2
 * exposes no message-size option, so the binding limit is whatever the
 * transport and muxer on the far side allow. 16 KiB fits inside every
 * libp2p transport's default stream window by a wide margin, which is the
 * property worth having: a frame is small enough that no plausible peer
 * rejects it outright.
 */
export const FRAME_BYTES = 16 * 1024;

/** The smallest frame worth sending; below this the overhead dominates. */
export const MIN_FRAME_BYTES = 1024;

/** Refuse a frame larger than this regardless of what a peer claims. */
export const MAX_FRAME_BYTES = 64 * 1024;

/** Longest request nonce we will carry. */
export const MAX_NONCE_BYTES = 8;

/** A chunk bigger than this is not a file share, it is an attack. */
export const MAX_CHUNK_BYTES = 1024 * 1024;

export class Libp2pError extends Error {
  constructor(message, { code = "libp2p", witness = null } = {}) {
    super(message);
    this.name = "Libp2pError";
    this.code = code;
    this.witness = witness;
  }
}

// ---------------------------------------------------------------- framing

const u8 = (n) => [n & 0xff];

const u32 = (n) => [
  (n / U32) & 0xff, (n / 65536) & 0xff, (n / 256) & 0xff, n & 0xff,
];

const readU32 = (b, at) =>
  ((b[at] << 24) >>> 0) + (b[at + 1] << 16) + (b[at + 2] << 8) + b[at + 3];

const hexToBytes = (hex) => {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
};

const bytesToHex = (b) =>
  Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");

/** The 64-hex Kant witness, lowercased, or null if it is not one.
 *
 *  Upper case is accepted and normalized. Witnesses are hex and every
 *  producer here emits lower case, but a witness that has been through a
 *  hex-encoding library or a shell may not be, and rejecting one would mean
 *  refusing a chunk that is named perfectly correctly. Normalizing is
 *  strictly safer than pattern-matching case-sensitively against a name
 *  that is case-insensitive by construction. */
export const asWitness = (s) => {
  if (typeof s !== "string" || s.length !== 64) return null;
  const lower = s.toLowerCase();
  return /^[0-9a-f]{64}$/.test(lower) ? lower : null;
};

/** Encode one wire message. Pure — the tests round-trip this directly.
 *
 *  `nonce` rides in the reserved bytes of the header on a `want`. It exists
 *  because gossipsub de-duplicates by message bytes: two identical requests
 *  for the same chunk are the same message, and the second is refused. */
export const encode = ({
  tag, witness, index = 0, total = 0, payload = null, nonce = null,
}) => {
  const w = asWitness(witness);
  if (w === null) throw new Libp2pError(`not a witness: ${witness}`, { code: "bad-witness" });
  if (!Number.isInteger(index) || index < 0 || !Number.isInteger(total) || total < 1) {
    throw new Libp2pError("bad frame index/total", { code: "bad-frame" });
  }
  if (index >= total) throw new Libp2pError("frame index past total", { code: "bad-frame" });
  const body = payload ? Uint8Array.from(payload) : new Uint8Array(0);
  if (body.length > MAX_CHUNK_BYTES) {
    throw new Libp2pError(`frame payload ${body.length}B exceeds the cap`, { code: "too-big" });
  }
  const out = new Uint8Array(HEADER + body.length);
  out.set(u8(tag), 0);
  out.set(hexToBytes(w), 1);
  out.set(u32(index), 33);
  out.set(u32(total), 37);
  out.set(body, HEADER);
  // The nonce lives AFTER the payload, so a `have` frame's length still
  // equals header + payload and the decoder needs no special case.
  if (nonce !== null && nonce !== undefined) {
    const tail = Uint8Array.from(nonce).slice(0, MAX_NONCE_BYTES);
    const grown = new Uint8Array(HEADER + body.length + tail.length);
    grown.set(out);
    grown.set(tail, HEADER + body.length);
    return grown;
  }
  return out;
};

/** Request counter, so two asks for the same chunk are different messages. */
let _nonce = 0;
const nextNonce = () => {
  _nonce = (_nonce + 1) >>> 0;
  return u32(_nonce);
};

/**
 * Pull the bytes out of whatever a handler was handed.
 *
 * gossipsub delivers a `message` CustomEvent, so the payload is at
 * `evt.detail.data` (verified in @libp2p/gossipsub 17.1.2: `message:
 * CustomEvent<Message>`, and `Message` is `{ topic, data }`). The adapter
 * above normalises to `{ data }` before calling a handler, but this module's
 * handlers also run against a plain `{ data }` in the tests and against raw
 * bytes if anyone wires a different transport — so unwrap all three.
 *
 * The old `msg?.data ?? msg` form silently produced `undefined` for a
 * CustomEvent, which `decode` turned into a null message: the handler ran,
 * saw nothing, and the peer looked like it had simply never answered.
 */
const bytesOf = (msg) => {
  if (msg == null) return null;
  if (msg instanceof Uint8Array) return msg;
  if (Array.isArray(msg)) return Uint8Array.from(msg);
  if (msg.data != null && typeof msg.data !== "object") return msg.data;
  if (msg.data?.data != null) return msg.data.data; // { data: { data } }
  const detail = msg.detail;
  if (detail != null) return bytesOf(detail);
  if (msg.data != null) return msg.data;
  return null;
};

/** Decode one wire message. Returns null for anything malformed — a
 *  malformed message from a stranger is not this module's problem to raise. */
export const decode = (bytes) => {
  let b;
  try { b = Uint8Array.from(bytes ?? []); } catch { return null; }
  if (b.length < HEADER) return null;
  const tag = b[0];
  if (tag !== TAG_WANT && tag !== TAG_HAVE && tag !== TAG_DENY) return null;
  const witness = bytesToHex(b.subarray(1, 33));
  const index = readU32(b, 33);
  const total = readU32(b, 37);
  if (total < 1 || index >= total || total > 0x10000) return null;
  const payload = tag === TAG_HAVE ? b.subarray(HEADER) : new Uint8Array(0);
  if (payload.length > MAX_CHUNK_BYTES) return null;
  return { tag, witness, index, total, payload };
};

// ------------------------------------------------------------------ topic

/**
 * The topic for one file. Derived from the room and the manifest witness,
 * both of which every peer in the room already knows and neither of which is
 * the secret. A peer must be in the room to learn this string at all.
 */
export const topicOf = (room, manifestWitness) => {
  const r = String(room ?? "");
  const w = asWitness(manifestWitness);
  if (!r) throw new Libp2pError("a topic needs a room", { code: "bad-room" });
  if (w === null) throw new Libp2pError("a topic needs a manifest witness", { code: "bad-witness" });
  // The full witness, so two different files in one room never share a topic
  // and a peer subscribed to one file is not handed another's chunks.
  return `kant-file/1/${r}/${w}`;
};

// ----------------------------------------------------------------- client

/**
 * A `fetchChunk` for `decryptFile`, served over pubsub.
 *
 * `pubsub` is `{ subscribe(topic, handler) -> unsubscribe, publish(topic, bytes) }`.
 * `has(witness)` says whether this peer holds the chunk to answer with, so a
 * peer that does not have it can `deny` instead of leaving the requester to
 * time out — a request for a chunk nobody has should fail fast and say so.
 */
export const libp2pFetcher = (pubsub, {
  topic,
  frameBytes = FRAME_BYTES,
  timeoutMs = 8000,
  cidOf,
} = {}) => {
  if (!pubsub || typeof pubsub.publish !== "function" || typeof pubsub.subscribe !== "function") {
    throw new Libp2pError("pubsub must be { subscribe, publish }", { code: "bad-pubsub" });
  }
  if (typeof topic !== "string" || !topic) {
    throw new Libp2pError("a fetcher needs a topic", { code: "bad-topic" });
  }
  if (typeof cidOf !== "function") {
    throw new Libp2pError("cidOf is required: bytes are checked before use", { code: "no-cidOf" });
  }
  if (frameBytes < MIN_FRAME_BYTES || frameBytes > MAX_FRAME_BYTES) {
    throw new Libp2pError(
      `frameBytes ${frameBytes} outside [${MIN_FRAME_BYTES}, ${MAX_FRAME_BYTES}]`,
      { code: "bad-frame" });
  }

  // The manifest witness scopes the SUBSCRIPTION, not an individual frame.
  // Frames carry CHUNK witnesses, which are a different set of names — a
  // fetcher that filtered incoming frames by the manifest witness would
  // discard every legitimate answer and time out on a perfectly healthy
  // peer. The topic already scopes us to one file, and `collect` re-checks
  // the name of whatever it reassembles.
  const held = new Map(); // chunk witness -> { frames: Map<index, bytes>, total }

  const off = pubsub.subscribe(topic, (msg) => {
    const m = decode(bytesOf(msg));
    // Only `have` frames. A `want` from another peer is not ours to answer —
    // serving is `serveChunks`' job, and a client that also served would
    // answer every request twice.
    if (!m || m.tag !== TAG_HAVE) return;
    let slot = held.get(m.witness);
    if (!slot) { slot = { frames: new Map(), total: m.total }; held.set(m.witness, slot); }
    if (slot.total !== m.total) return; // a peer changed its mind mid-transfer
    // First frame to arrive fixes the count; later frames must agree.
    slot.frames.set(m.index, m.payload);
  });

  let closed = false;
  const close = () => { if (!closed) { closed = true; try { off?.(); } catch { /* gone */ } } };

  const collect = (witness, total) => {
    const slot = held.get(witness);
    if (!slot || slot.frames.size !== total) return null;
    const parts = [];
    for (let i = 0; i < total; i += 1) {
      const p = slot.frames.get(i);
      if (!p) return null;
      parts.push(p);
    }
    const size = parts.reduce((n, p) => n + p.length, 0);
    if (size > MAX_CHUNK_BYTES) return null;
    const out = new Uint8Array(size);
    let at = 0;
    for (const p of parts) { out.set(p, at); at += p.length; }
    return out;
  };

  /** Fetch one chunk by its Kant witness. Throws rather than returning
   *  something wrong: `decryptFile` would reject it anyway, and a clear
   *  failure here names the peer rather than the crypto. */
  const fetchChunk = async (witness) => {
    const w = asWitness(witness);
    if (w === null) {
      throw new Libp2pError(`not a witness: ${witness}`, { code: "bad-witness" });
    }
    const heldAlready = held.get(w);
    if (heldAlready && heldAlready.frames.size === heldAlready.total) {
      const got = collect(w, heldAlready.total);
      if (got && cidOf(got) === w) return got;
    }

    // The frame count is derived from the ANSWER, not guessed from the
    // witness: a witness is a digest and says nothing about length. So the
    // request carries a single index and the peer replies with `total`, and
    // `collect` waits for exactly that many frames.
    const bytes = typeof witness === "string" ? w.length / 2 : 0;
    const totalGuess = Math.max(1, Math.ceil(bytes / frameBytes));
    const deadline = Date.now() + timeoutMs;

    // Ask for the whole chunk in one message. The peer replies with every
    // frame and states the count; asking frame-by-frame would multiply the
    // message count by the chunk size for no gain, since pubsub has no
    // per-request reply channel anyway.
    //
    // `nonce` makes each request a DISTINCT pubsub message. gossipsub keeps
    // a seen-cache and `publish` throws PublishError.Duplicate for anything
    // already seen, so two byte-identical `want` frames for the same chunk —
    // which is exactly what a retry after a timeout looks like — would be
    // refused as a duplicate and the chunk could never be requested twice.
    //
    // `publish` is awaited because it is async and can reject. A rejection
    // here means nobody was listening (NoPeersSubscribedToTopic) or the
    // router is unhappy; either way the request did not go out, so there is
    // nothing to wait for and the right thing is to fail now rather than sit
    // out the whole timeout on a request that was never made.
    const ask = () => Promise.resolve(pubsub.publish(topic, encode({
      tag: TAG_WANT, witness: w, index: 0, total: totalGuess, nonce: nextNonce(),
    })));
    try {
      await ask();
    } catch (e) {
      throw new Libp2pError(
        `the chunk request could not be published: ${e?.message ?? e}`,
        { code: "no-peers", witness: w });
    }

    // Poll rather than subscribe-per-request: the handler above is already
    // collecting, and one subscription per chunk would leak a listener per
    // file into a long-lived node.
    //
    // One re-ask partway through: a peer that joined the topic after the
    // first request never saw it, and pubsub has no replay, so a request
    // that was sent into an empty room is simply lost. That is the common
    // case here — the reader often arrives before the holder does.
    const reaskAt = Date.now() + Math.max(250, Math.floor(timeoutMs / 2));
    let reasked = false;
    for (;;) {
      const slot = held.get(w);
      if (slot && slot.frames.size === slot.total) {
        const got = collect(w, slot.total);
        if (got !== null) {
          // Check the name before handing bytes to the crypto. A peer that
          // answers with the wrong chunk is refused here rather than
          // producing a confusing "not its own name" from three layers down.
          if (cidOf(got) !== w) {
            held.delete(w);
            throw new Libp2pError(
              `peer answered chunk ${w.slice(0, 12)}… with bytes that are not it`,
              { code: "corrupt", witness: w });
          }
          return got;
        }
      }
      const now = Date.now();
      if (!reasked && now >= reaskAt) {
        reasked = true;
        try { await ask(); } catch { /* nobody to ask yet; keep waiting */ }
      }
      if (now > deadline) break;
      await new Promise((r) => setTimeout(r, 25));
    }
    throw new Libp2pError(
      `no peer answered chunk ${w.slice(0, 12)}… within ${timeoutMs}ms`,
      { code: "timeout", witness: w });
  };

  fetchChunk.close = close;
  fetchChunk.topic = topic;
  return fetchChunk;
};

// ----------------------------------------------------------------- server

/**
 * Answer `want` frames from a local chunk map.
 *
 * `chunks` maps a Kant witness to its ciphertext. Bytes are checked against
 * the witness they are served under BEFORE going on the wire: serving bytes
 * under a name they do not match would make this peer the one that breaks a
 * download, and would let anyone use it to launder a hash collision into
 * somebody else's file.
 */
export const serveChunks = (pubsub, {
  topic, chunks, frameBytes = FRAME_BYTES, cidOf, onMismatch = null,
} = {}) => {
  if (!pubsub || typeof pubsub.subscribe !== "function" || typeof pubsub.publish !== "function") {
    throw new Libp2pError("pubsub must be { subscribe, publish }", { code: "bad-pubsub" });
  }
  if (typeof chunks?.get !== "function") {
    throw new Libp2pError("chunks must be a Map of witness -> ciphertext", { code: "bad-chunks" });
  }
  if (typeof cidOf !== "function") {
    throw new Libp2pError("cidOf is required: bytes are checked before they are served", { code: "no-cidOf" });
  }
  if (frameBytes < MIN_FRAME_BYTES || frameBytes > MAX_FRAME_BYTES) {
    throw new Libp2pError(
      `frameBytes ${frameBytes} outside [${MIN_FRAME_BYTES}, ${MAX_FRAME_BYTES}]`,
      { code: "bad-frame" });
  }

  // Bytes whose digest does not match the witness they are filed under are
  // never served, and are reported once so the mistake above this layer is
  // visible instead of silently costing a download.
  const mismatched = new Set();

  // `publish` is async and throws. Every send below is chained and swallowed
  // on purpose: a handler that returns a rejected promise surfaces as an
  // unhandled rejection, and refusing to answer is not an error worth
  // crashing a page over.
  const send = (bytes) => Promise.resolve(pubsub.publish(topic, bytes)).catch(() => null);

  return pubsub.subscribe(topic, (msg) => {
    const m = decode(bytesOf(msg));
    if (!m || m.tag !== TAG_WANT) return;
    const bytes = chunks.get(m.witness);
    if (!bytes) {
      void send(encode({ tag: TAG_DENY, witness: m.witness, index: 0, total: 1 }));
      return;
    }
    const body = Uint8Array.from(bytes);
    // Serving bytes under a name they do not match would make this peer the
    // one that breaks somebody's download, and would let anyone use it to
    // launder a collision into a third party's file.
    if (cidOf(body) !== m.witness) {
      if (!mismatched.has(m.witness)) {
        mismatched.add(m.witness);
        onMismatch?.(m.witness);
      }
      void send(encode({ tag: TAG_DENY, witness: m.witness, index: 0, total: 1 }));
      return;
    }
    const total = Math.max(1, Math.ceil(body.length / frameBytes));
    // Sequential, not parallel: gossipsub de-duplicates by message bytes and
    // a burst of publishes is also a burst of work on the router. Chaining
    // keeps frame order on the wire and keeps the seen-cache happy.
    let chain = Promise.resolve();
    for (let i = 0; i < total; i += 1) {
      chain = chain.then(() => send(encode({
        tag: TAG_HAVE,
        witness: m.witness,
        index: i,
        total,
        payload: body.subarray(i * frameBytes, (i + 1) * frameBytes),
      })));
    }
    void chain;
  });
};

// -------------------------------------------------------------- real node

/**
 * Pinned versions, read off the actual sources in the js-libp2p worktree
 * (each package's package.json) rather than guessed. Guessing is what
 * produced a v2-era `@chainsafe/` import set and a `tcp()` listener that
 * cannot exist in a browser; both are gone below.
 *
 *   libp2p            3.3.11
 *   @libp2p/gossipsub 17.1.2   (the `@chainsafe/*` names are dead upstream)
 *   @libp2p/identify / noise / yamux / websockets / webrtc / webtransport
 */
export const LIBP2P_VERSIONS = Object.freeze({
  "libp2p": "3.3.11",
  "@libp2p/gossipsub": "17.1.2",
  "@libp2p/identify": "3.3.9",
  "@libp2p/noise": "2.1.6",
  "@libp2p/yamux": "7.1.4",
  "@libp2p/websockets": "10.1.21",
  "@libp2p/webrtc": "6.0.33",
  "@libp2p/webtransport": "6.0.40",
});

const esm = (spec, version) => `https://esm.sh/${spec}@${version}`;

/**
 * A real js-libp2p node with gossipsub, loaded from esm.sh — the same
 * no-bundler shape as the Helia vendor bundle. Returns null when the CDN is
 * unreachable so a page without it still works on the relay path; libp2p is
 * an accelerator for artifacts here, never a requirement.
 *
 * The API this is written against, verified in the sources:
 *
 *  - `node.services.pubsub` is the router. `subscribe(topic)` RETURNS
 *    NOTHING and is idempotent — there is no per-subscription unsubscribe
 *    function, and calling it twice is harmless. Messages arrive as a
 *    `message` CustomEvent whose `detail` is `{ topic, data, ... }`, so the
 *    payload is `evt.detail.data`, NOT `evt.data` and not a bare Uint8Array.
 *  - `publish(topic, data)` is ASYNC and THROWS. `PublishError.NoPeersSub-
 *    cribedToTopic` when nobody is on the topic (which is the normal case
 *    for a peer that has not yet met anyone) and `PublishError.Duplicate`
 *    for a repeat of a message already seen. An un-awaited publish rejects
 *    and, in a browser, that surfaces as an unhandled rejection.
 *  - Because `subscribe` returns void, this adapter keeps its OWN
 *    per-topic listener bookkeeping and returns a real unsubscribe, which is
 *    what the rest of this module and its tests are written against.
 *
 * On transports: a browser CANNOT listen on TCP, and js-libp2p's WebTransport
 * transport explicitly "only allows dialing to other nodes" — it does not
 * listen. So a browser peer dials out and is reachable through a circuit
 * relay; `circuitRelayTransport` is what makes an inbound relayed address
 * work. A node that cannot find peers simply never answers a request, and
 * the relay path still serves every file.
 */
export const libp2pNode = async ({
  onError = null,
  relay = "",
  rendezvous = [],
  inBrowser = typeof window !== "undefined",
} = {}) => {
  try {
    const V = LIBP2P_VERSIONS;
    const [core, gs, id, noiseMod, yamuxMod, wsMod, circuitMod] = await Promise.all([
      import(esm("libp2p", V["libp2p"])),
      import(esm("@libp2p/gossipsub", V["@libp2p/gossipsub"])),
      import(esm("@libp2p/identify", V["@libp2p/identify"])),
      import(esm("@libp2p/noise", V["@libp2p/noise"])),
      import(esm("@libp2p/yamux", V["@libp2p/yamux"])),
      import(esm("@libp2p/websockets", V["@libp2p/websockets"])),
      import(esm("@libp2p/circuit-relay-v2", "4.2.13")),
    ]);

    // WebTransport cannot listen in a browser, so a browser node listens on
    // nothing and dials. Under Node the same node CAN listen on WebSocket,
    // which is what makes the local two-peer test possible at all.
    const transports = [];
    if (!inBrowser) transports.push(wsMod.webSockets());
    else {
      const wt = await import(esm("@libp2p/webtransport", V["@libp2p/webtransport"]))
        .catch(() => null);
      const rtc = await import(esm("@libp2p/webrtc", V["@libp2p/webrtc"]))
        .catch(() => null);
      if (wt?.webTransport) transports.push(wt.webTransport());
      if (rtc?.webRTC) transports.push(rtc.webRTC());
    }
    if (transports.length === 0) {
      throw new Error("no usable transport in this environment");
    }

    const services = {
      identify: id.identify(),
      // `allowPublishToZeroTopicPeers` is a PUBLISH-time opt, not a
      // constructor one; it is passed per publish below. Without it,
      // answering a chunk request while alone throws NoPeersSubscribedToTopic
      // — and a peer serving a file with no peers connected is not an error,
      // it is the normal state of a browser tab that has not met anyone yet.
      pubsub: gs.gossipsub({ emitSelf: false }),
    };
    if (relay) services.relay = circuitMod.circuitRelay();

    const node = await core.createLibp2p({
      addresses: { listen: inBrowser ? [] : ["/ip4/127.0.0.1/tcp/0/ws"] },
      transports,
      connectionEncrypters: [noiseMod.noise()],
      streamMuxers: [yamuxMod.yamux()],
      connectionGater: { denyDialMultiaddr: () => false },
      peerDiscovery: rendezvous.length ? [await bootstrap(rendezvous)] : undefined,
      services,
    });
    if (onError) node.addEventListener?.("error", (e) => onError(e));

    const pubsub = node.services.pubsub;
    // One listener per topic, not per subscription: `subscribe()` is void and
    // idempotent, so the handler count is this module's to manage.
    const byTopic = new Map();
    const publishQueue = new Map(); // topic -> Promise, to serialise per topic

    const transport = {
      subscribe(topic, handler) {
        let entry = byTopic.get(topic);
        if (!entry) {
          entry = { handlers: new Set(), onMessage: null };
          pubsub.subscribe(topic);
          entry.onMessage = (evt) => {
            const detail = evt?.detail ?? evt;
            if (detail?.topic !== undefined && detail.topic !== topic) return;
            const data = detail?.data;
            if (data == null) return;
            for (const h of [...entry.handlers]) {
              try { h({ data }); } catch { /* one bad handler must not stop the rest */ }
            }
          };
          pubsub.addEventListener("message", entry.onMessage);
          byTopic.set(topic, entry);
        }
        entry.handlers.add(handler);
        let released = false;
        return () => {
          if (released) return;
          released = true;
          entry.handlers.delete(handler);
          // Leave the topic subscribed but stop listening once nobody wants
          // it: `unsubscribe()` makes gossipsub apply a prune backoff, and
          // re-subscribing inside that window is refused. Keeping the
          // subscription avoids that entirely.
          if (entry.handlers.size === 0) {
            pubsub.removeEventListener?.("message", entry.onMessage);
            byTopic.delete(topic);
          }
        };
      },

      // Serialised per topic and always resolved: a caller of this module
      // awaits nothing here, and an unhandled rejection from
      // NoPeersSubscribedToTopic would surface as a console error on every
      // chunk we offer to an empty room.
      publish(topic, bytes) {
        const prev = publishQueue.get(topic) ?? Promise.resolve();
        const next = prev.then(async () => {
          try {
            return await pubsub.publish(topic, bytes, {
              allowPublishToZeroTopicPeers: true,
              ignoreDuplicatePublishError: true,
            });
          } catch (e) {
            // Duplicate and no-peers are ordinary here, not failures.
            if (onError && !/Duplicate|NoPeersSubscribedToTopic/.test(e?.message ?? "")) {
              onError(e);
            }
            return { recipients: [] };
          }
        }).catch(() => ({ recipients: [] }));
        publishQueue.set(topic, next);
        return next;
      },
    };

    if (relay) {
      await circuitMod.circuitRelay().relayListen?.(node.services.relay).catch(() => {});
    }
    return { node, pubsub, transport, stop: async () => {
      for (const topic of byTopic.keys()) pubsub.unsubscribe(topic);
      byTopic.clear();
      await node.stop().catch(() => {});
    } };
  } catch (e) {
    if (onError) onError(e);
    return null;
  }
};

/** Bootstrap peer discovery, only when peers were actually named. */
async function bootstrap(addrs) {
  const { bootstrap } = await import(
    `https://esm.sh/@libp2p/bootstrap@${LIBP2P_VERSIONS["@libp2p/identify"]}`.replace(
      "@libp2p/identify", "@libp2p/bootstrap"))
    .catch(() => ({}));
  if (!bootstrap) return { start: () => {}, stop: () => {} };
  return bootstrap({ list: addrs });
}

// The confidentiality property, stated where a reader will find it.
// Ciphertext only; the room secret never enters this module. A peer in the
// topic learns a file's SIZE and CHUNK COUNT and can fetch ciphertext it
// cannot read — the same exposure IPFS pinning already documents in
// kant-file-ipfs.mjs, and no more.
export const LIBP2P_EXPOSURE = "ciphertext-only-size-and-count";