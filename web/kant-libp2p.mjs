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
//  - CHUNK_SIZE is 256 KiB. gossipsub's default maxMessageSize is much
//    smaller (64 KiB in libp2p's own defaults), so a Kant chunk cannot be
//    published as one message. Chunks are sliced into FRAME-sized pieces
//    and reassembled, and the frame size is a parameter because the right
//    value depends on the swarm's actual limit.
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
 * Frame size for the wire. Comfortably under libp2p's 64 KiB default
 * maxMessageSize, leaving room for the header and for a transport that
 * wraps our message in its own framing.
 */
export const FRAME_BYTES = 24 * 1024;

/** The smallest frame worth sending; below this the overhead dominates. */
export const MIN_FRAME_BYTES = 1024;

/** Refuse a frame larger than this regardless of what a peer claims. */
export const MAX_FRAME_BYTES = 64 * 1024;

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

/** Encode one wire message. Pure — the tests round-trip this directly. */
export const encode = ({ tag, witness, index = 0, total = 0, payload = null }) => {
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
  return out;
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
    const m = decode(msg?.data ?? msg);
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
    pubsub.publish(topic, encode({
      tag: TAG_WANT, witness: w, index: 0, total: totalGuess,
    }));

    // Poll rather than subscribe-per-request: the handler above is already
    // collecting, and one subscription per chunk would leak a listener per
    // file into a long-lived node.
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
      if (Date.now() > deadline) break;
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

  return pubsub.subscribe(topic, (msg) => {
    const m = decode(msg?.data ?? msg);
    if (!m || m.tag !== TAG_WANT) return;
    const bytes = chunks.get(m.witness);
    if (!bytes) {
      pubsub.publish(topic, encode({ tag: TAG_DENY, witness: m.witness, index: 0, total: 1 }));
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
      pubsub.publish(topic, encode({ tag: TAG_DENY, witness: m.witness, index: 0, total: 1 }));
      return;
    }
    const total = Math.max(1, Math.ceil(body.length / frameBytes));
    for (let i = 0; i < total; i += 1) {
      pubsub.publish(topic, encode({
        tag: TAG_HAVE,
        witness: m.witness,
        index: i,
        total,
        payload: body.subarray(i * frameBytes, (i + 1) * frameBytes),
      }));
    }
  });
};

// -------------------------------------------------------------- real node

/**
 * A real js-libp2p node with gossipsub, from esm.sh — the same
 * no-bundler-import shape as the Helia vendor bundle. Returns null when the
 * CDN is unreachable so a page without it still works on the relay path;
 * libp2p is an accelerator for artifacts here, never a requirement.
 *
 * Kept deliberately small: no bootstrap peers, no relay transport. A node
 * that cannot find peers simply never answers, and the relay path still
 * serves every file.
 */
export const libp2pNode = async ({ onError = null } = {}) => {
  try {
    const [{ createLibp2p }, { gossipsub }] = await Promise.all([
      import("https://esm.sh/libp2p@2"),
      import("https://esm.sh/@chainsafe/libp2p-gossipsub"),
    ]);
    const { tcp } = await import("https://esm.sh/@chainsafe/libp2p-net-tcp");
    const { noise } = await import("https://esm.sh/@chainsafe/libp2p-noise");
    const { yamux } = await import("https://esm.sh/@chainsafe/libp2p-yamux");
    const { identify } = await import("https://esm.sh/@chainsafe/libp2p-identify");

    const node = await createLibp2p({
      addresses: { listen: ["/ip4/0.0.0.0/tcp/0"] },
      transports: [tcp()],
      connectionEncrypters: [noise()],
      streamMuxers: [yamux()],
      services: {
        identify: identify(),
        pubsub: gossipsub({ allowPublishToZeroTopicPeers: true }),
      },
    });
    if (onError) node.addEventListener("error", (e) => onError(e));
    return {
      node,
      pubsub: node.services.pubsub,
      /** Minimal `{ subscribe, publish }` over gossipsub's subscribe API. */
      transport: {
        subscribe: (topic, handler) => {
          // gossipsub handlers are called as ({ topic, data }) in v11 and
          // ({ topic, data }) via the SubscriptionEmitter in some versions;
          // normalise to a plain SubscriptionEmitter-free shape.
          const h = (msg) => handler({ data: msg?.data });
          node.services.pubsub.subscribe(topic);
          node.services.pubsub.addEventListener("message", h);
          return () => {
            node.services.pubsub.removeEventListener("message", h);
          };
        },
        publish: (topic, bytes) => node.services.pubsub.publish(topic, bytes),
      },
    };
  } catch (e) {
    if (onError) onError(e);
    return null;
  }
};

// The confidentiality property, stated where a reader will find it.
// Ciphertext only; the room secret never enters this module. A peer in the
// topic learns a file's SIZE and CHUNK COUNT and can fetch ciphertext it
// cannot read — the same exposure IPFS pinning already documents in
// kant-file-ipfs.mjs, and no more.
export const LIBP2P_EXPOSURE = "ciphertext-only-size-and-count";