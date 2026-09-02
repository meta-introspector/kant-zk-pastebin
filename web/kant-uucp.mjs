// kant-uucp.mjs — the static sneakernet: DMs, tweets, bang paths, no relay.
//
// An unverified transcription of `RequestProject/Kant/Uucp.lean`.  Every
// pure function here corresponds to a Lean definition of the same name,
// and `web/uucp-test.mjs` pins them to vectors computed by Lean itself
// (`RequestProject/Kant/Demo.lean` checks the same numbers with `#guard`).
//
// The model in one paragraph: a node keeps a spool of self-certifying
// chat lines.  `bag()` renders the whole spool as one line of ASCII that
// fits in a direct message, a tweet thread, a QR code or a URL fragment;
// `paste()` takes such a line and merges it in.  There is no server:
// state moves only when a human moves a code.  A node is therefore
// exactly as up to date as the last code pasted into it
// (`Kant.Uucp.Node.mem_sneakernet_iff`).

import {
  asciiBytes, asciiChars, envelopeEncode, envelopeDecode,
  natToBytesBE, bytesBEToNat, shareUrl, parseShareUrl,
  frames, reassemble, chunk, utf8,
} from "./kantzk.mjs";
import { printMsg, parseMsg, transcript, message } from "./kant-net.mjs";

const eqBytes = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

const sameMsg = (a, b) =>
  a.room === b.room && a.sender === b.sender && a.seq === b.seq &&
  a.body.length === b.body.length && a.body.every((x, i) => x === b.body[i]);

// ------------------------------------------------------------- carriers

/** What each hand-carried channel holds, in characters (`Carrier.capacity`). */
export const CARRIER_CAPACITY = {
  tweet: 280,
  dm: 10000,
  qr: 2953,
  urlBar: 2000,
  bio: 160,
  altText: 1000,
};

// ------------------------------------------------------------ the mailbag

export const TAG_BAG = asciiBytes("kzbag");

/** A batch of messages as one envelope (`ofBag`). */
export const ofBag = (ms) => ({
  tag: TAG_BAG,
  fields: ms.map((m) => asciiBytes(printMsg(m))),
});

/** Read the fields of a bag, refusing the whole bag if any line fails to
 *  certify itself (`readMsgs`, `toBag`). */
export function toBag(e) {
  if (!e || !eqBytes(e.tag, TAG_BAG)) return null;
  const out = [];
  for (const f of e.fields) {
    const m = parseMsg(asciiChars(f));
    if (!m) return null;
    out.push(m);
  }
  return out;
}

/** The text you paste into a DM or a tweet (`packBag`). */
export const packBag = (ms) => envelopeEncode(ofBag(ms));

/** Read a pasted bag (`openBag`). */
export const openBag = (s) => toBag(envelopeDecode(typeof s === "string" ? s.trim() : s));

/** A bag as the fragment of a link (`bagUrl`). */
export const bagUrl = (base, ms) => shareUrl(base, ofBag(ms));

/** Read a bag out of a pasted link (`readBagUrl`). */
export const readBagUrl = (u) => toBag(parseShareUrl(typeof u === "string" ? u.trim() : u));

/** Does a bag fit in this carrier as it stands? */
export const bagFits = (text, carrier) => text.length <= CARRIER_CAPACITY[carrier];

// -------------------------------------------------- bags too big for one tweet

export const TAG_PART = asciiBytes("kzleg");

export const ofPart = (f) => ({
  tag: TAG_PART,
  fields: [natToBytesBE(f.seq), natToBytesBE(f.total), Array.from(f.payload)],
});

export function toPart(e) {
  if (!e || !eqBytes(e.tag, TAG_PART) || e.fields.length !== 3) return null;
  const [s, t, p] = e.fields;
  return { seq: Number(bytesBEToNat(s)), total: Number(bytesBEToNat(t)), payload: p };
}

/** Cut a text into numbered parts of at most `limit` payload bytes
 *  (`thread`).  With `limit = 100` every part fits in a tweet. */
export const thread = (limit, s) =>
  frames(limit, asciiBytes(s)).map((f) => envelopeEncode(ofPart(f)));

/** Put a threaded bag back together, in whatever order the parts were
 *  collected (`readThread`). */
export function readThread(parts) {
  const fs = [];
  for (const t of parts) {
    const f = toPart(envelopeDecode(typeof t === "string" ? t.trim() : t));
    if (!f) return null;
    fs.push(f);
  }
  if (fs.length === 0) return null;
  return asciiChars(reassemble(fs));
}

/** How many parts a text needs at this payload size. */
export const threadLength = (limit, s) => chunk(limit, asciiBytes(s)).length;

/** Split a bag for a carrier: one code if it fits, otherwise a thread. */
export function bagForCarrier(text, carrier = "tweet") {
  if (bagFits(text, carrier)) return [text];
  // 100 payload bytes per part keeps a part inside a tweet
  // (`Kant.Uucp.thread_fits_tweet`); larger carriers get proportionally
  // bigger parts, with the same 2·payload + framing headroom.
  const limit = Math.max(16, Math.floor((CARRIER_CAPACITY[carrier] - 40) / 2.4));
  return thread(limit, text);
}

// ------------------------------------------------------------------ nodes

/** Add a message to a spool unless it is already there (`insertMsg`).
 *  New messages go in front, exactly as `m :: acc` does in Lean, so the
 *  bags the two sides produce are byte-for-byte identical. */
export const insertMsg = (acc, m) => (acc.some((x) => sameMsg(x, m)) ? acc : [m, ...acc]);

/** Fold messages into a spool (`absorb`). */
export const absorb = (spool, ms) => ms.reduce(insertMsg, spool);

/** A sneakernet node: a name, a spool, and its own counter (`Node`). */
export class SneakerNode {
  constructor(name, spool = [], clock = 0) {
    this.name = name;
    this.spool = spool;
    this.clock = clock;
  }

  static blank(name) { return new SneakerNode(name, [], 0); }

  /** Write a line of your own, with nobody connected (`Node.write`). */
  write(room, body) {
    const m = message(room, this.name, this.clock, typeof body === "string" ? utf8(body) : body);
    this.spool = absorb(this.spool, [m]);
    this.clock += 1;
    return m;
  }

  /** The bag you hand out (`Node.bag`).  It is built from the displayed
   *  order, so two nodes that know the same lines emit the same code
   *  (`Kant.Uucp.bag_canonical`). */
  bag() { return packBag(this.view()); }

  /** The bag as a link you can pin, tweet or print (`bagUrl`). */
  bagLink(base) { return bagUrl(base, this.view()); }

  /** Paste a code somebody sent you.  Anything that does not certify
   *  itself leaves the node untouched (`Node.paste`). */
  paste(text) {
    const ms = openBag(text) ?? readBagUrl(text) ?? readThreadBag(text);
    if (!ms) return { accepted: false, added: 0 };
    const before = this.spool.length;
    this.spool = absorb(this.spool, ms);
    return { accepted: true, added: this.spool.length - before };
  }

  /** Paste a pile of codes, in any order (`Node.sneakernet`). */
  sneakernet(texts) {
    let added = 0, accepted = 0;
    for (const t of texts) {
      const r = this.paste(t);
      if (r.accepted) { accepted += 1; added += r.added; }
    }
    return { accepted, added };
  }

  /** What the node displays (`Node.view`). */
  view() { return transcript(this.spool); }

  /** Is this node at least as up to date as that one (`Fresher`)? */
  fresherThan(other) { return other.spool.every((x) => this.spool.some((y) => sameMsg(x, y))); }

  toJSON() {
    return { name: this.name, clock: this.clock, bag: this.bag() };
  }

  static fromJSON(o) {
    const spool = openBag(o.bag) ?? [];
    return new SneakerNode(o.name, spool, o.clock ?? 0);
  }
}

/** Read a bag that arrived as several parts, or as one. */
export function readThreadBag(text) {
  const parts = String(text).split(/\s*\n\s*\n|\s*\n/).map((s) => s.trim()).filter(Boolean);
  if (parts.length === 0) return null;
  const joined = readThread(parts);
  if (!joined) return null;
  return openBag(joined);
}

/** Two nodes swap bags (`exchange`). */
export function exchange(a, b) {
  const bagA = a.bag(), bagB = b.bag();
  a.paste(bagB);
  b.paste(bagA);
  return [a, b];
}

/** Carry a bag along a bang path a!c!b (`route`). */
export function route(start, hops) {
  let carried = start.bag();
  let last = start;
  for (const hop of hops) {
    hop.paste(carried);
    carried = hop.bag();
    last = hop;
  }
  return last;
}

// ---------------------------------------------------------- the static site

/** A static site: a read-only map from path to text (`Site`). */
export class Site {
  constructor(files = new Map()) { this.files = files; }

  get(path) { return this.files.has(path) ? this.files.get(path) : null; }

  put(path, body) { this.files.set(path, body); return this; }

  /** Serving a request never changes the site (`Site.serve_static`). */
  serve(path) { return [this, this.get(path)]; }

  /** Publish a node's bag at a path (`Site.publish`). */
  publish(path, node) { return this.put(path, node.bag()); }

  /** Fetch a page and paste what it holds (`Site.visit`). */
  visit(path, node) {
    const body = this.get(path);
    if (body === null) return { accepted: false, added: 0 };
    return node.paste(body);
  }
}

/** Fetch a bag published as a static file over plain HTTP — no API, no
 *  server logic, just a file. */
export async function fetchBag(url, fetchImpl = globalThis.fetch) {
  const res = await fetchImpl(url, { cache: "no-store" });
  if (!res.ok) throw new Error(`fetch ${url}: ${res.status}`);
  const text = (await res.text()).trim();
  return openBag(text) ?? readThreadBag(text);
}

// -------------------------------------------------------------- persistence

const STORE_KEY = "kant-sneakernet";

/** Load the node this browser keeps, or start a fresh one. */
export function loadNode(name, storage = globalThis.localStorage) {
  try {
    const raw = storage?.getItem(STORE_KEY);
    if (raw) return SneakerNode.fromJSON(JSON.parse(raw));
  } catch { /* fall through to a fresh node */ }
  return SneakerNode.blank(name);
}

/** Save the node so the next visit starts where this one stopped. */
export function saveNode(node, storage = globalThis.localStorage) {
  try { storage?.setItem(STORE_KEY, JSON.stringify(node.toJSON())); } catch { /* ignore */ }
  return node;
}

/** Everything a share sheet needs: the code, how it must travel, and the
 *  ready-made links for a DM or a tweet. */
export function shareKit(node, { base = "", carrier = "tweet" } = {}) {
  const bag = node.bag();
  const parts = bagForCarrier(bag, carrier);
  const link = base ? node.bagLink(base) : "";
  return {
    bag,
    parts,
    link,
    fitsOne: parts.length === 1,
    carrier,
    capacity: CARRIER_CAPACITY[carrier],
    tweetIntent: (text) => `https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}`,
  };
}
