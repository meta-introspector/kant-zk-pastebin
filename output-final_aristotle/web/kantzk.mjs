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

// ----------------------------------------------------------------- Text
// Transcription of `Kant.Text`: ASCII transcoding, colon-separated field
// framing and substring search.

export const asciiBytes = (s) => Array.from(s).map((c) => c.codePointAt(0) & 0xff);
export const asciiChars = (bs) => bs.map((b) => String.fromCodePoint(b & 0xff)).join("");
export const charCodes = (s) => Array.from(s).map((c) => c.codePointAt(0));
export const codeChars = (ns) => ns.map((n) => String.fromCodePoint(n)).join("");
export const isAscii = (s) => Array.from(s).every((c) => c.codePointAt(0) < 128);

export const SEP = ":";
export const joinFields = (fs) => fs.join(SEP);
export const splitFields = (s) => s.split(SEP);

/** Minimal big-endian byte string of a non-negative integer (0 -> []). */
export function natToBytesBE(n) {
  let x = BigInt(n);
  const out = [];
  while (x > 0n) { out.unshift(Number(x % 256n)); x /= 256n; }
  return out;
}

/** Value of a big-endian byte string, as a BigInt. */
export function bytesBEToNat(bs) {
  let acc = 0n;
  for (const b of bs) acc = acc * 256n + BigInt(b);
  return acc;
}

/** Does `hay` contain `needle` as a contiguous block? */
export const containsSub = (needle, hay) => hay.includes(needle);

/** The value of the decimal digits occurring in a string. */
export function digitsValue(s) {
  let acc = 0;
  for (const c of s) if (c >= "0" && c <= "9") acc = acc * 10 + (c.codePointAt(0) - 48);
  return acc;
}

// ------------------------------------------------------------ Clipboard
// Transcription of `Kant.Clipboard`: a tag plus hex-encoded byte fields,
// joined with ':'.  Copy then paste is the identity (proved in Lean as
// `Envelope.decode_encode`).

export const TAG_PASTE = asciiBytes("kzpaste");
export const TAG_RECEIPT = asciiBytes("kzresult");

export const envelopeEncode = (e) => joinFields([e.tag, ...e.fields].map(hexEncode));

export function envelopeDecode(s) {
  const parts = splitFields(s);
  if (parts.length === 0) return null;
  const bs = [];
  for (const f of parts) {
    if (f.length % 2 !== 0 || !/^[0-9a-f]*$/.test(f)) return null;
    bs.push(hexDecode(f));
  }
  return { tag: bs[0], fields: bs.slice(1) };
}

const eqBytes = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

export const optField = (o) => (o === null || o === undefined ? [0] : [1, ...asciiBytes(o)]);

export function parseOptField(bs) {
  if (bs.length === 1 && bs[0] === 0) return { ok: true, value: null };
  if (bs.length >= 1 && bs[0] === 1) return { ok: true, value: asciiChars(bs.slice(1)) };
  return { ok: false };
}

/** A post as a copyable envelope. */
export function ofPaste(p) {
  return {
    tag: TAG_PASTE,
    fields: [
      asciiBytes(p.id),
      asciiBytes(p.title),
      Array.from(p.content),
      asciiBytes(p.timestamp),
      optField(p.replyTo ?? null),
      asciiBytes(p.witness),
    ],
  };
}

/** Read a post back; the witness that arrived must be the witness of the
 *  content that arrived, so tampering is refused. */
export function toPaste(e) {
  if (!e || !eqBytes(e.tag, TAG_PASTE) || e.fields.length !== 6) return null;
  const [i, t, c, ts, r, w] = e.fields;
  const rep = parseOptField(r);
  if (!rep.ok) return null;
  const p = makePaste({
    id: asciiChars(i), title: asciiChars(t), content: c,
    timestamp: asciiChars(ts), replyTo: rep.value,
  });
  return p.witness === asciiChars(w) ? p : null;
}

export const copyText = (p) => envelopeEncode(ofPaste(p));
export const pasteText = (s) => toPaste(envelopeDecode(s));

/** The numeric results shown beside a post. */
export const receiptOf = (p, credits) => ({
  witness: p.witness, cid: p.cid, bytes: p.content.length, credits,
});

export const ofReceipt = (r) => ({
  tag: TAG_RECEIPT,
  fields: [asciiBytes(r.witness), natToBytesBE(r.cid), natToBytesBE(r.bytes),
           natToBytesBE(r.credits)],
});

export function toReceipt(e) {
  if (!e || !eqBytes(e.tag, TAG_RECEIPT) || e.fields.length !== 4) return null;
  const [w, c, b, k] = e.fields;
  return {
    witness: asciiChars(w),
    cid: bytesBEToNat(c),
    bytes: Number(bytesBEToNat(b)),
    credits: Number(bytesBEToNat(k)),
  };
}

export const copyReceipt = (r) => envelopeEncode(ofReceipt(r));
export const pasteReceipt = (s) => toReceipt(envelopeDecode(s));

export const TAG_BUNDLE = asciiBytes("kzfeed");

/** Several posts as one copyable envelope. */
export const ofPastes = (ps) => ({
  tag: TAG_BUNDLE,
  fields: ps.map((p) => asciiBytes(copyText(p))),
});

/** Read a bundle of posts back. */
export function toPastes(e) {
  if (!e || !eqBytes(e.tag, TAG_BUNDLE)) return null;
  const out = [];
  for (const f of e.fields) {
    const p = pasteText(asciiChars(f));
    if (!p) return null;
    out.push(p);
  }
  return out;
}

export const copyAll = (ps) => envelopeEncode(ofPastes(ps));
export const pasteAll = (s) => toPastes(envelopeDecode(s));

export const shareUrl = (base, e) => base + "#" + envelopeEncode(e);
export const fragment = (u) => (u.indexOf("#") < 0 ? "" : u.slice(u.indexOf("#") + 1));
export const parseShareUrl = (u) => envelopeDecode(fragment(u));

// ------------------------------------------------------------------ Feed
// Transcription of `Kant.Feed`: the reader's view of the posts.

export const row = (p, credits = 0) => ({
  witness: p.witness,
  cid: p.cid,
  title: escapeHtml(p.title),
  body: escapeHtml(asciiChars(Array.from(p.content))),
  timestamp: p.timestamp,
  replyTo: p.replyTo ?? null,
  bytes: p.content.length,
  copy: copyText(p),
  receipt: copyReceipt(receiptOf(p, credits)),
});

export const feed = (store) => store.entries;
export const view = (store) => feed(store).map((p) => row(p));

/** Split a feed into pages of at most `size` entries. */
export function paginate(size, xs) {
  if (size === 0) return [];
  const out = [];
  for (let i = 0; i < xs.length; i += size) out.push(xs.slice(i, i + size));
  return out;
}

export const page = (size, n, xs) => xs.slice(size * n, size * n + size);

export const mentions = (q, p) =>
  containsSub(q, p.title) || containsSub(q, asciiChars(Array.from(p.content)));

export const search = (q, ps) => ps.filter((p) => mentions(q, p));

export const replies = (w, ps) => ps.filter((p) => p.replyTo === w);
export const thread = (root, ps) => [root, ...replies(root.witness, ps)];

export const timeKey = (p) => digitsValue(p.timestamp);
export const newest = (ps) => [...ps].sort((a, b) => timeKey(b) - timeKey(a));

export const timeline = (store, q, size) =>
  paginate(size, search(q, newest(feed(store))).map((p) => row(p)));

// ------------------------------------------------------------------ Meme
// Transcription of `Kant.Meme`: a picture whose least significant bits
// carry a marker, a clipboard envelope and a zero terminator.

export const MEME_MAGIC = "KZM1";

export const memePayload = (e) => [...charCodes(MEME_MAGIC + envelopeEncode(e)), 0];

/** Draw the meme: hide the payload in the carrier's least significant bits. */
export const memeRender = (carrier, e) => embedBlob(carrier, memePayload(e));

/** Read the hidden bytes of a carrier: everything up to the first zero. */
export function memeReadPayload(carrier) {
  const bytes = extractBlob(capacityBytes(carrier), carrier);
  const stop = bytes.indexOf(0);
  return stop < 0 ? bytes : bytes.slice(0, stop);
}

/** Recover the envelope hidden in a picture, if there is one. */
export function memeDecode(carrier) {
  const text = codeChars(memeReadPayload(carrier));
  if (!text.startsWith(MEME_MAGIC)) return null;
  return envelopeDecode(text.slice(MEME_MAGIC.length));
}

export const memeOfPaste = (carrier, p) => memeRender(carrier, ofPaste(p));
export const memeOfPastes = (carrier, ps) => memeRender(carrier, ofPastes(ps));
export const memeToPastes = (carrier) => toPastes(memeDecode(carrier));
export const memeOfReceipt = (carrier, r) => memeRender(carrier, ofReceipt(r));
export const memeToPaste = (carrier) => toPaste(memeDecode(carrier));
export const memeToReceipt = (carrier) => toReceipt(memeDecode(carrier));

/** How many characters of envelope a carrier can hold. */
export const memeCapacityChars = (carrier) =>
  Math.max(0, capacityBytes(carrier) - MEME_MAGIC.length - 1);

/** The caption drawn on the meme: escaped, so it is safe in a page. */
export const memeCaption = (top, witness, bottom) => escapeHtml(top + witness + bottom);

// ---------------------------------------------------------------- Repost
// Transcription of `Kant.Repost`: quote reposts and share cards.

export const TAG_QUOTE = asciiBytes("kzquote");

/** A quote repost: your own post, and the post it quotes, carried whole. */
export const quoteWith = (comment, original) => ({ comment, original });

export const ofQuote = (q) => ({
  tag: TAG_QUOTE,
  fields: [asciiBytes(copyText(q.comment)), asciiBytes(copyText(q.original))],
});

/** Read a quote back: both halves must paste, so a doctored quotation fails. */
export function toQuote(e) {
  if (!e || !eqBytes(e.tag, TAG_QUOTE) || e.fields.length !== 2) return null;
  const comment = pasteText(asciiChars(e.fields[0]));
  const original = pasteText(asciiChars(e.fields[1]));
  if (comment === null || original === null) return null;
  return { comment, original };
}

export const copyQuote = (q) => envelopeEncode(ofQuote(q));
export const pasteQuote = (s) => toQuote(envelopeDecode(s));

export const memeOfQuote = (carrier, q) => memeRender(carrier, ofQuote(q));
export const memeToQuote = (carrier) => toQuote(memeDecode(carrier));

/** Drop the fragment marker so the link's `#` is the first one in a card. */
export const sanitize = (s) => Array.from(s).filter((c) => c !== "#").join("");

/** A share card: a readable headline, a newline, and a link carrying the data. */
export const card = (headline, base, e) => sanitize(headline) + "\n" + shareUrl(base, e);

export const readCard = (s) => parseShareUrl(s);

/** The headline shown for a post: its escaped title and its address. */
export const headline = (p) => sanitize(escapeHtml(p.title + " " + p.witness));

export const postCard = (base, p) => card(headline(p), base, ofPaste(p));
export const receiptCard = (base, r) => card(sanitize(r.witness), base, ofReceipt(r));
export const bundleCard = (base, ps) => card(sanitize(String(ps.length)), base, ofPastes(ps));

// ----------------------------------------------------------------- Strip
// Transcription of `Kant.Strip`: one share spread over several pictures,
// each still carrying its own sequence number, so they may be collected
// in any order (`Kant.Strip.readStrip_perm`).

export const TAG_PART = asciiBytes("kzpart");

export const ofFrame = (f) => ({
  tag: TAG_PART,
  fields: [natToBytesBE(f.seq), natToBytesBE(f.total), f.payload],
});

export function toFrame(e) {
  if (!e || !eqBytes(e.tag, TAG_PART) || e.fields.length !== 3) return null;
  const [s, t, p] = e.fields;
  return { seq: Number(bytesBEToNat(s)), total: Number(bytesBEToNat(t)), payload: p };
}

export const still = (carrier, f) => memeRender(carrier, ofFrame(f));
export const readStill = (carrier) => toFrame(memeDecode(carrier));

/** Cut an envelope into parts of at most `limit` bytes and hide one in each still. */
export const strip = (carrier, limit, e) =>
  frames(limit, asciiBytes(envelopeEncode(e))).map((f) => still(carrier, f));

export function readParts(carriers) {
  const out = [];
  for (const c of carriers) {
    const f = readStill(c);
    if (f === null) return null;
    out.push(f);
  }
  return out;
}

/** Put a strip back together, whatever order the stills arrived in. */
export function readStrip(carriers) {
  const parts = readParts(carriers);
  if (parts === null) return null;
  return envelopeDecode(asciiChars(reassemble(parts)));
}

export const stripOfPaste = (carrier, limit, p) => strip(carrier, limit, ofPaste(p));
export const stripOfPastes = (carrier, limit, ps) => strip(carrier, limit, ofPastes(ps));
export const stripOfQuote = (carrier, limit, q) => strip(carrier, limit, ofQuote(q));
export const stripToPaste = (carriers) => toPaste(readStrip(carriers));
export const stripToPastes = (carriers) => toPastes(readStrip(carriers));
export const stripToQuote = (carriers) => toQuote(readStrip(carriers));

/** How many payload bytes a still of this carrier can take per part. */
export const stripLimitFor = (carrier) => {
  for (let limit = capacityBytes(carrier); limit > 0; limit -= 1) {
    const probe = { seq: 0xffff, total: 0xffff, payload: Array(limit).fill(0xff) };
    if (memePayload(ofFrame(probe)).length * 8 <= carrier.length) return limit;
  }
  return 0;
};
