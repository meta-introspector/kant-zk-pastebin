// kantzk.mjs — JavaScript reference implementation of the Lean 4 port
// in `RequestProject/Kant/`.
//
// IMPORTANT: the *proved* artefact is the Lean development.  This file is
// an unverified transcription of those definitions, kept deliberately
// close to them so that it can run in a browser, in node, or inside a
// WASM host, and so that `web/test.mjs` can check it against vectors
// computed by Lean itself.
//
// Every function below corresponds to a Lean definition of the same name.

// ---------------------------------------------------------------- Bytes

const MASK64 = (1n << 64n) - 1n;
const FNV_OFFSET = 14695981039346656037n;
const FNV_PRIME = 1099511628211n;

export function fnv1a(bytes) {
  let h = FNV_OFFSET;
  for (const b of bytes) h = ((h ^ BigInt(b & 0xff)) * FNV_PRIME) & MASK64;
  return h;
}

export function u64Bytes(x) {
  const out = [];
  for (let i = 0; i < 8; i++) out.push(Number((x >> BigInt(8 * (7 - i))) & 0xffn));
  return out;
}

/** 32-byte digest: four salted FNV-1a rounds (mirrors `Kant.Bytes.digest`). */
export function digest(bytes) {
  const out = [];
  for (let i = 0; i < 4; i++) out.push(...u64Bytes(fnv1a([i, ...bytes])));
  return out;
}

export function hexEncode(bytes) {
  return bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function hexDecode(s) {
  if (s.length % 2 !== 0) return null;
  const out = [];
  for (let i = 0; i < s.length; i += 2) out.push(parseInt(s.slice(i, i + 2), 16));
  return out;
}

/** The witness of a paste: hex of the content digest. */
export function witness(bytes) {
  return hexEncode(digest(bytes));
}

export const utf8 = (s) => Array.from(new TextEncoder().encode(s));
export const fromUtf8 = (b) => new TextDecoder().decode(Uint8Array.from(b));

// ----------------------------------------------------------------- DASL

export const DASL_PREFIX = 0xda51n;
export const MONSTER_PRIMES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 41, 47, 59, 71];
export const ATTACK_TRIPLE = [47, 59, 71];

export function mkCid(typ, payload) {
  return DASL_PREFIX * (1n << 48n) + (BigInt(typ) % 16n) * (1n << 44n) + (payload % (1n << 44n));
}

export const cidPrefix = (c) => c >> 48n;
export const cidType = (c) => (c >> 44n) % 16n;
export const cidPayload = (c) => c % (1n << 44n);

export function decodeCid(c) {
  if (cidPrefix(c) !== DASL_PREFIX) return null;
  return { type: Number(cidType(c)), payload: cidPayload(c) };
}

const byteAt = (h, i) => BigInt(i < h.length ? h[i] : 0);

export function nestedCidPayload(h) {
  const shard = byteAt(h, 0) % 71n;
  const hecke = byteAt(h, 1) % 59n;
  const bott = byteAt(h, 2) % 47n;
  const hash20 =
    (byteAt(h, 3) * (1n << 12n) + byteAt(h, 4) * (1n << 4n) + byteAt(h, 5) / 16n) % (1n << 20n);
  return shard * (1n << 36n) + hecke * (1n << 28n) + bott * (1n << 20n) + hash20;
}

/** Type-3 content address of a byte string. */
export function nestedCid(bytes) {
  return mkCid(3, nestedCidPayload(digest(bytes)));
}

export function daslHex(c) {
  return "0x" + c.toString(16).padStart(16, "0");
}

function le32(h, i) {
  return (
    byteAt(h, i) +
    byteAt(h, i + 1) * 256n +
    byteAt(h, i + 2) * 65536n +
    byteAt(h, i + 3) * 16777216n
  );
}

/** Monster orbifold coordinates in Z/71 x Z/59 x Z/47. */
export function orbifoldCoords(bytes) {
  const h = digest(bytes);
  return { l: Number(le32(h, 0) % 71n), m: Number(le32(h, 4) % 59n), n: Number(le32(h, 8) % 47n) };
}

export const rotate71 = (o, k) => ({ l: (o.l + k) % 71, m: o.m, n: o.n });
export const reflect59 = (o, k) => ({ l: o.l, m: (o.m + k) % 59, n: o.n });
export const dual47 = (o, k) => ({ l: o.l, m: o.m, n: (o.n + k) % 47 });

/** XOR merge of two addresses, preserving the DASL prefix. */
export function mergeCids(c1, c2) {
  const mask = (1n << 48n) - 1n;
  return DASL_PREFIX * (1n << 48n) + ((c1 & mask) ^ (c2 & mask));
}

// ---------------------------------------------------------------- eRDFa

export function escapeChar(c) {
  if (c === "&") return "&amp;";
  if (c === "<") return "&lt;";
  if (c === ">") return "&gt;";
  if (c === '"') return "&quot;";
  return c;
}

export function escapeHtml(s) {
  return Array.from(s).map(escapeChar).join("");
}

export function unescapeHtml(s) {
  let out = "";
  let i = 0;
  while (i < s.length) {
    if (s[i] === "&") {
      const rest = s.slice(i + 1);
      if (rest.startsWith("amp;")) { out += "&"; i += 5; continue; }
      if (rest.startsWith("lt;")) { out += "<"; i += 4; continue; }
      if (rest.startsWith("gt;")) { out += ">"; i += 4; continue; }
      if (rest.startsWith("quot;")) { out += '"'; i += 6; continue; }
      out += "&"; i += 1; continue;
    }
    out += s[i];
    i += 1;
  }
  return out;
}

// ----------------------------------------------------------- Sneakernet

export const CHANNEL_CAPACITY = {
  url: 2000,
  qr: 2953,
  animatedQr: 2953,
  wav: 65536,
  morse: 256,
  stegoPng: 1 << 20,
  svg: 1 << 20,
  animatedGif: 5 * 1024 * 1024,
  socialVideo: 5 * 1024 * 1024,
  ipfsBlock: 262144,
  torrentPiece: 262144,
  irohBlob: 262144,
};

export const SOCIAL_LIMIT = 5 * 1024 * 1024;

/** Split content into pieces of at most `limit` bytes. */
export function chunk(limit, data) {
  if (limit === 0) return [];
  const out = [];
  let rest = data;
  while (rest.length > limit) {
    out.push(rest.slice(0, limit));
    rest = rest.slice(limit);
  }
  if (rest.length > 0) out.push(rest);
  return out;
}

/** Numbered transport frames. */
export function frames(limit, data) {
  const cs = chunk(limit, data);
  return cs.map((payload, seq) => ({ seq, total: cs.length, payload }));
}

/** Reassemble frames arriving in any order. */
export function reassemble(fs) {
  return [...fs].sort((a, b) => a.seq - b.seq).flatMap((f) => f.payload);
}

// ---------------------------------------------------------------- Stego

export function byteBits(n) {
  const out = [];
  for (let i = 0; i < 8; i++) out.push(((n >> (7 - i)) & 1) === 1);
  return out;
}

export const toBits = (bytes) => bytes.flatMap(byteBits);

export function fromBits(bits) {
  const out = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    let v = 0;
    for (let j = 0; j < 8; j++) if (bits[i + j]) v += 1 << (7 - j);
    out.push(v);
  }
  return out;
}

/** Overwrite carrier LSBs with a bit stream. */
export function embedBits(carrier, bits) {
  const out = carrier.slice();
  for (let i = 0; i < bits.length && i < out.length; i++) {
    out[i] = 2 * Math.floor(out[i] / 2) + (bits[i] ? 1 : 0);
  }
  return out;
}

export const extractBits = (n, carrier) => carrier.slice(0, n).map((c) => c % 2 === 1);
export const embedBlob = (carrier, payload) => embedBits(carrier, toBits(payload));
export const extractBlob = (n, carrier) => fromBits(extractBits(8 * n, carrier));
export const capacityBytes = (carrier) => Math.floor(carrier.length / 8);

// ------------------------------------------------------------ CodeMovie

export function rleEncode(s) {
  const out = [];
  for (const x of s) {
    if (out.length > 0 && out[out.length - 1][0] === x) out[out.length - 1][1] += 1;
    else out.push([x, 1]);
  }
  return out;
}

export function rleDecode(l) {
  return l.flatMap(([v, n]) => Array(n).fill(v));
}

function bigSqrt(n) {
  if (n < 2n) return n;
  let x = n, y = (x + 1n) / 2n;
  while (y < x) { x = y; y = (x + n / x) / 2n; }
  return x;
}

/** Cantor pairing, matching Lean's `Nat.pair`. */
export function pair(a, b) {
  return a < b ? b * b + a : a * a + a + b;
}

/** Matching Lean's `Nat.unpair`. */
export function unpair(n) {
  const s = bigSqrt(n);
  const rest = n - s * s;
  return rest < s ? [rest, s] : [s, rest - s];
}

/** Gödel number of a snippet (a list of naturals). */
export function godel(list) {
  let acc = 0n;
  for (let i = list.length - 1; i >= 0; i--) acc = pair(BigInt(list[i]), acc) + 1n;
  return acc;
}

export function ungodel(n) {
  const out = [];
  while (n > 0n) {
    const [a, rest] = unpair(n - 1n);
    out.push(a);
    n = rest;
  }
  return out;
}

export const movieGodel = (movie) => godel(movie.map((f) => godel(f)));
export const unmovie = (n) => ungodel(n).map((g) => ungodel(g));
export const frameAt = (movie, t) => (movie.length === 0 ? [] : movie[t % movie.length]);

// Circuits ---------------------------------------------------------------

export const Circuit = {
  inp: (i) => ({ tag: "inp", i }),
  const: (b) => ({ tag: "const", b }),
  not: (c) => ({ tag: "not", c }),
  and: (a, b) => ({ tag: "and", a, b }),
  or: (a, b) => ({ tag: "or", a, b }),
};

export function circuitTokens(c) {
  switch (c.tag) {
    case "inp": return [0, c.i];
    case "const": return [1, c.b ? 1 : 0];
    case "not": return [...circuitTokens(c.c), 2];
    case "and": return [...circuitTokens(c.a), ...circuitTokens(c.b), 3];
    case "or": return [...circuitTokens(c.a), ...circuitTokens(c.b), 4];
  }
  throw new Error("bad circuit");
}

export function circuitRun(tokens) {
  const st = [];
  let i = 0;
  while (i < tokens.length) {
    const t = Number(tokens[i]);
    if (t === 0) { st.push(Circuit.inp(Number(tokens[i + 1]))); i += 2; }
    else if (t === 1) { st.push(Circuit.const(Number(tokens[i + 1]) === 1)); i += 2; }
    else if (t === 2) { const c = st.pop(); st.push(Circuit.not(c)); i += 1; }
    else if (t === 3) { const b = st.pop(), a = st.pop(); st.push(Circuit.and(a, b)); i += 1; }
    else if (t === 4) { const b = st.pop(), a = st.pop(); st.push(Circuit.or(a, b)); i += 1; }
    else return null;
  }
  return st;
}

export const circuitEncode = (c) => godel(circuitTokens(c));

export function circuitDecode(n) {
  const st = circuitRun(ungodel(n).map(Number));
  return st && st.length === 1 ? st[0] : null;
}

export function circuitEval(env, c) {
  switch (c.tag) {
    case "inp": return env(c.i);
    case "const": return c.b;
    case "not": return !circuitEval(env, c.c);
    case "and": return circuitEval(env, c.a) && circuitEval(env, c.b);
    case "or": return circuitEval(env, c.a) || circuitEval(env, c.b);
  }
  throw new Error("bad circuit");
}

// --------------------------------------------------------------- Store

/** Content-addressed store: witness -> paste. */
export class Store {
  constructor() { this.entries = []; }
  get(w) { return this.entries.find((p) => p.witness === w) ?? null; }
  has(w) { return this.get(w) !== null; }
  put(paste) {
    if (!this.has(paste.witness)) this.entries.unshift(paste);
    return this;
  }
  sync(pastes) { for (const p of pastes) this.put(p); return this; }
}

export function makePaste({ id, title, content, timestamp, replyTo = null }) {
  const bytes = typeof content === "string" ? utf8(content) : content;
  return {
    id, title, timestamp, replyTo,
    content: bytes,
    witness: witness(bytes),
    cid: nestedCid(bytes),
    coords: orbifoldCoords(bytes),
  };
}

// -------------------------------------------------------------- Credits

export class Ledger {
  constructor() { this.earnLog = []; this.spendLog = []; }
  static creditsFor(bytes) { return Math.floor(bytes / 1024); }
  static earned(log, peer) {
    return log.filter(([p]) => p === peer).reduce((a, [, n]) => a + n, 0);
  }
  balance(peer) {
    return Math.max(0, Ledger.earned(this.earnLog, peer) - Ledger.earned(this.spendLog, peer));
  }
  totalEarned() { return this.earnLog.reduce((a, [, n]) => a + n, 0); }
  serve(peer, bytes) { this.earnLog.unshift([peer, Ledger.creditsFor(bytes)]); return this; }
  spend(peer, c) {
    if (c > this.balance(peer)) return null;
    this.spendLog.unshift([peer, c]);
    return this;
  }
}
