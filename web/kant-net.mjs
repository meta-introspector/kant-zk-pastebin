// kant-net.mjs — discovery, rendezvous and chat for the browser client.
//
// This is an unverified transcription of the Lean modules
// `RequestProject/Kant/Rendezvous.lean` (peers, rosters, gossip, the chat
// QR invite) and `RequestProject/Kant/Relay.lean` (the room mailbox, chat
// messages, transcripts).  Every pure function below corresponds to a
// Lean definition of the same name, and `web/net-test.mjs` checks it
// against vectors computed by Lean itself.
//
// The transports at the bottom of the file (relay client, BroadcastChannel
// bus, WebRTC mesh) are plumbing: they move the strings produced by the
// pure layer around.  Nothing they do can change what a client accepts,
// because every accepted line is re-checked against its own witness.

import {
  asciiBytes, asciiChars, hexEncode, witness, utf8, fromUtf8,
  envelopeEncode, envelopeDecode, natToBytesBE, bytesBEToNat,
  shareUrl, parseShareUrl, CHANNEL_CAPACITY,
} from "./kantzk.mjs";
import { DiagLog, ref as diagRef, diagnose, effectiveRelay, clientOf, probeRelay } from "./kant-diag.mjs";
import { parseManifest, printManifest, manifestWitness } from "./kant-file.mjs";

/** The witness a manifest is named by — re-exported so a caller quoting a
 *  file does not have to import both modules. */
const manifestWitnessOf = manifestWitness;

/** A log that keeps nothing: used when a caller supplies none.  Every
 *  transport below writes to `log` instead of swallowing its errors —
 *  the silence was the whole reason a failure to connect was so hard to
 *  explain (`RequestProject/Kant/Diagnostics.lean`). */
const NULL_LOG = {
  record() {}, info() {}, warn() {}, error() {},
  events: [], dropped: 0, total: 0, share: () => [], render: () => "",
};

const eqBytes = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

// ------------------------------------------------------------- addresses

/** Transport tags, mirroring `Kant.Sync.Source`. */
export const SOURCE_CODE = {
  ipfs: 1, iroh: 2, libp2p: 3, torrent: 4,
  archiveOrg: 5, uucp: 6, qrBurst: 7, localDisk: 8,
};

export const CODE_SOURCE = Object.fromEntries(
  Object.entries(SOURCE_CODE).map(([k, v]) => [v, k]),
);

/** An address as one byte field: transport byte, then the locator. */
export const addrField = (a) => [SOURCE_CODE[a.transport] & 0xff, ...asciiBytes(a.locator)];

/** Read an address back out of a byte field. */
export function parseAddrField(bs) {
  if (!bs || bs.length === 0) return null;
  const t = CODE_SOURCE[bs[0]];
  if (!t) return null;
  return { transport: t, locator: asciiChars(bs.slice(1)) };
}

function parseAddrFields(fs) {
  const out = [];
  for (const f of fs) {
    const a = parseAddrField(f);
    if (!a) return null;
    out.push(a);
  }
  return out;
}

// --------------------------------------------------------- announcements

export const TAG_PEER = asciiBytes("kzpeer");

/** "Peer `peer`, at revision `seq`, can be reached at `addrs`." */
export const announce = (peer, seq, addrs) => ({ peer, seq, addrs });

export const ofAnnounce = (a) => ({
  tag: TAG_PEER,
  fields: [asciiBytes(a.peer), natToBytesBE(a.seq), ...a.addrs.map(addrField)],
});

export function toAnnounce(e) {
  if (!e || !eqBytes(e.tag, TAG_PEER) || e.fields.length < 2) return null;
  const [p, s, ...rest] = e.fields;
  const addrs = parseAddrFields(rest);
  if (!addrs) return null;
  return { peer: asciiChars(p), seq: Number(bytesBEToNat(s)), addrs };
}

/** An announcement as one line of text. */
export const printAnnounce = (a) => envelopeEncode(ofAnnounce(a));

/** Read an announcement off the wire. */
export const parseAnnounce = (s) => toAnnounce(envelopeDecode(s));

// ---------------------------------------------------------------- roster

const sameAnnounce = (a, b) =>
  a.peer === b.peer && a.seq === b.seq &&
  a.addrs.length === b.addrs.length &&
  a.addrs.every((x, i) => x.transport === b.addrs[i].transport && x.locator === b.addrs[i].locator);

/** Record an announcement.  Hearing the same one twice changes nothing. */
export function rosterInsert(r, a) {
  return r.some((x) => sameAnnounce(x, a)) ? r : [...r, a];
}

/** Fold a batch of announcements into a roster. */
export const rosterMerge = (r, as) => as.reduce(rosterInsert, r);

/** Does the client know any address for this peer? */
export const rosterKnows = (r, p) => r.some((a) => a.peer === p);

/** The freshest announcement held for a peer (`Roster.best`). */
export function rosterBest(r, p) {
  let best = null;
  for (const a of r) {
    if (a.peer !== p) continue;
    if (best === null || best.seq < a.seq) best = a;
  }
  return best;
}

/** The peers a roster knows about, freshest announcement each. */
export function rosterPeers(r) {
  const names = [...new Set(r.map((a) => a.peer))];
  return names.map((p) => rosterBest(r, p));
}

/** Fold announcement lines from a poll into a roster (`acceptPeers`). */
export function acceptPeers(r, lines) {
  const as = [];
  for (const l of lines) {
    const a = parseAnnounce(l);
    if (a) as.push(a);
  }
  return rosterMerge(r, as);
}

// -------------------------------------------------------- the chat invite

/** The room named by a shared secret: 64 hex characters. */
export const roomOf = (secret) => witness(Array.from(secret));

export const TAG_INVITE = asciiBytes("kzinvite");

export const invite = (relay, secret, peer, addrs = []) => ({ relay, secret, peer, addrs });

/** The room an invitation leads to. */
export const inviteRoom = (i) => roomOf(i.secret);

export const ofInvite = (i) => ({
  tag: TAG_INVITE,
  fields: [asciiBytes(i.relay), Array.from(i.secret), asciiBytes(i.peer), ...i.addrs.map(addrField)],
});

export function toInvite(e) {
  if (!e || !eqBytes(e.tag, TAG_INVITE) || e.fields.length < 3) return null;
  const [r, s, p, ...rest] = e.fields;
  const addrs = parseAddrFields(rest);
  if (!addrs) return null;
  return { relay: asciiChars(r), secret: s, peer: asciiChars(p), addrs };
}

/** The text a chat QR code carries. */
export const copyInvite = (i) => envelopeEncode(ofInvite(i));

/** Read a scanned or pasted invitation. */
export const pasteInvite = (s) => toInvite(envelopeDecode(s));

/** The same invitation as a link. */
export const inviteUrl = (base, i) => shareUrl(base, ofInvite(i));

/** Read an invitation out of a link. */
export const parseInviteUrl = (u) => toInvite(parseShareUrl(u));

/** Does the printed invitation fit in a single QR code? */
export const inviteFitsQr = (i) => copyInvite(i).length <= CHANNEL_CAPACITY.qr;

/** A fresh random secret for a new room (32 bytes). */
export function freshSecret(n = 32) {
  const b = new Uint8Array(n);
  (globalThis.crypto ?? { getRandomValues: () => b }).getRandomValues(b);
  return Array.from(b);
}

/** A peer identifier derived from a local key: 64 hex characters. */
export const peerIdOf = (seed) => witness(Array.from(seed));

// ------------------------------------------------------------- chat lines

export const TAG_CHAT = asciiBytes("kzchat");

export const message = (room, sender, seq, body) => ({ room, sender, seq, body });

/** The bytes a message commits to (`Msg.core`). */
export const msgCore = (m) => [
  ...asciiBytes(m.room), 0, ...asciiBytes(m.sender), 0,
  ...natToBytesBE(m.seq), 0, ...Array.from(m.body),
];

/** The self-certifying witness of a message. */
export const msgWitness = (m) => witness(msgCore(m));

export const ofMsg = (m) => ({
  tag: TAG_CHAT,
  fields: [
    asciiBytes(m.room), asciiBytes(m.sender), natToBytesBE(m.seq),
    Array.from(m.body), asciiBytes(msgWitness(m)),
  ],
});

/** Read a message back, refusing anything whose witness does not match. */
export function toMsg(e) {
  if (!e || !eqBytes(e.tag, TAG_CHAT) || e.fields.length !== 5) return null;
  const [r, s, q, b, w] = e.fields;
  const m = {
    room: asciiChars(r), sender: asciiChars(s),
    seq: Number(bytesBEToNat(q)), body: b,
  };
  return msgWitness(m) === asciiChars(w) ? m : null;
}

/** A message as one line of text. */
export const printMsg = (m) => envelopeEncode(ofMsg(m));

/** Read a line of text as a message. */
export const parseMsg = (s) => toMsg(envelopeDecode(s));

/** The readable text of a message body. */
export const msgText = (m) => fromUtf8(m.body);

/** Write a message from plain text. */
export const sayText = (room, sender, seq, text) => message(room, sender, seq, utf8(text));

const sameMsg = (a, b) =>
  a.room === b.room && a.sender === b.sender && a.seq === b.seq &&
  a.body.length === b.body.length && a.body.every((x, i) => x === b.body[i]);

/** Take one line from anywhere, dropping anything that does not certify
 *  itself (`accept`). */
export function accept(ms, line) {
  const m = parseMsg(line);
  if (!m) return ms;
  return ms.some((x) => sameMsg(x, m)) ? ms : [...ms, m];
}

/** Take a batch of lines (`receive`). */
export const receive = (ms, lines) => lines.reduce(accept, ms);

/** The display order: by counter, then by the line itself (`leMsg`). */
export function leMsg(a, b) {
  if (a.seq !== b.seq) return a.seq < b.seq;
  const x = printMsg(a), y = printMsg(b);
  return x <= y;
}

/** The transcript a client displays: its messages, in display order. */
export function transcript(ms) {
  const out = [];
  for (const m of ms) if (!out.some((x) => sameMsg(x, m))) out.push(m);
  return out.sort((a, b) => (leMsg(a, b) ? (leMsg(b, a) ? 0 : -1) : 1));
}

// ------------------------------------------------- time-stamped chat lines

/** A chat line that also carries *when* its sender wrote it.
 *
 *  `kzchat` orders by a per-sender counter and nothing else, which is the
 *  right total order for agreeing on what was said but useless for reading:
 *  a peer that joins late, or reconnects after six hours, has no idea which
 *  of yesterday's messages came first. `kzat` adds a sender-declared
 *  millisecond timestamp to the committed bytes, so the time is covered by
 *  the same witness as everything else.
 *
 *  Deliberately a *new tag* rather than a sixth field on `kzchat`: an old
 *  peer parses `kzchat` strictly (five fields, exact tag) and would drop a
 *  six-field line, whereas it ignores `kzat` entirely — and this file has to
 *  keep working with peers that predate the file drop.
 *
 *  The clock is the sender's, not the relay's. The relay stores lines it
 *  never parses, so a server timestamp would mean trusting one relay over
 *  another; two peers with skewed clocks may disagree about order, which is
 *  why `transcriptAt` sorts by time but breaks ties on `leMsg` and never
 *  *rejects* a line for having a strange time.
 */
export const TAG_AT = asciiBytes("kzat");

/** The wall clock, in milliseconds. Isolated so a test can pin it. */
export const now = () => Date.now();

export const timed = (room, sender, seq, body, at) => ({ room, sender, seq, body, at });

/** The bytes a timed message commits to — the tag, then `Msg.core`, then
 *  its `at`.
 *
 *  The tag is in here, unlike in `msgCore`/`manifestCore` (which leave it
 *  out and so let a `kzchat` line be re-tagged as a `kzfile` one).  Nothing
 *  depends on that looseness for `kzat`: it is a new tag, so binding it
 *  breaks no stored line, and it means a timestamp cannot be attached to an
 *  existing untimed message after the fact — re-tagging now invalidates the
 *  witness instead of quietly inventing a time the sender never claimed. */
export const timedCore = (m) => [...TAG_AT, 0, ...msgCore(m), 0, ...natToBytesBE(m.at)];

export const timedWitness = (m) => witness(timedCore(m));

export const ofTimed = (m) => ({
  tag: TAG_AT,
  fields: [
    asciiBytes(m.room), asciiBytes(m.sender), natToBytesBE(m.seq),
    Array.from(m.body), natToBytesBE(m.at), asciiBytes(timedWitness(m)),
  ],
});

/** Read a timed message back, refusing anything whose witness does not match. */
export function toTimed(e) {
  if (!e || !eqBytes(e.tag, TAG_AT) || e.fields.length !== 6) return null;
  const [r, s, q, b, t, w] = e.fields;
  const m = {
    room: asciiChars(r), sender: asciiChars(s),
    seq: Number(bytesBEToNat(q)), body: b,
    at: Number(bytesBEToNat(t)),
  };
  return timedWitness(m) === asciiChars(w) ? m : null;
}

export const printTimed = (m) => envelopeEncode(ofTimed(m));
export const parseTimed = (s) => toTimed(envelopeDecode(s));

/** Write a timestamped message from plain text, at `at` (default: now). */
export const sayTextAt = (room, sender, seq, text, at = now()) =>
  timed(room, sender, seq, utf8(text), at);

const sameTimed = (a, b) =>
  a.room === b.room && a.sender === b.sender && a.seq === b.seq &&
  a.at === b.at && a.body.length === b.body.length &&
  a.body.every((x, i) => x === b.body[i]);

/** Take one timed line, dropping anything that does not certify itself. */
export function acceptTimed(ms, line) {
  const m = parseTimed(line);
  if (!m) return ms;
  return ms.some((x) => sameTimed(x, m)) ? ms : [...ms, m];
}

export const receiveTimed = (ms, lines) => lines.reduce(acceptTimed, ms);

/** Order by declared time, breaking ties on `leMsg` so two peers with the
 *  same clock still agree.
 *
 *  A line with no declared time (`at === null`, an untimed `kzchat` line
 *  from a peer that predates `kzat`) sorts *after* every timed one and keeps
 *  `leMsg` order among itself.  It is not given a synthetic time: a counter
 *  is not a clock, and `at = seq` would file a message under 1970-01-01,
 *  which is a date nobody said.  Ordering it after is a choice, stated here
 *  because it is one — the alternative, dropping it, loses chat outright.
 *
 *  A line with a time in the future or the distant past is kept and ordered
 *  as given: a peer cannot prove a sender's clock is wrong, so it has no
 *  business discarding the message.  Sender clocks do jump backwards, so the
 *  sort is stable on input order within equal times rather than trying to
 *  repair the sender's clock. */
export function transcriptAt(ms) {
  const out = [];
  for (const m of ms) if (!out.some((x) => sameTimed(x, m))) out.push(m);
  return out
    .map((m, i) => ({ m, i }))
    .sort((x, y) => {
      const xt = x.m.at, yt = y.m.at;
      if (xt === null && yt === null) return leMsg(x.m, y.m) ? (leMsg(y.m, x.m) ? x.i - y.i : -1) : 1;
      if (xt === null) return 1;
      if (yt === null) return -1;
      if (xt !== yt) return xt < yt ? -1 : 1;
      return leMsg(x.m, y.m) ? (leMsg(y.m, x.m) ? x.i - y.i : -1) : 1;
    })
    .map((x) => x.m);
}

/** A day's worth of a transcript, for the time-stored view. */
export const DAY_MS = 86400000;

/** The label used for lines that carry no declared time, so they are never
 *  filed under a day nobody claimed. */
export const UNTITLED = "untitled";

/** The transcript grouped into days, newest first, each day in time order.
 *  A day is named in UTC: two peers on either side of a date line must land
 *  in the same bucket, and a local-midnight boundary would not.
 *
 *  Untimed lines get their own bucket named `UNTITLED`, placed last — they
 *  belong to no day, and inventing one would be a lie in the only place the
 *  view claims to be a record of when things happened. */
export function byDay(ms) {
  const days = new Map();
  let untitled = null;
  for (const m of transcriptAt(ms)) {
    if (m.at === null) {
      if (!untitled) untitled = [];
      untitled.push(m);
      continue;
    }
    const d = new Date(m.at).toISOString().slice(0, 10);
    if (!days.has(d)) days.set(d, []);
    days.get(d).push(m);
  }
  const out = [...days.entries()].map(([day, messages]) => ({ day, messages }));
  if (untitled) out.push({ day: UNTITLED, messages: untitled, untimed: true });
  return out.sort((a, b) => {
    // Untimed last, and oldest day first within the timed ones reversed:
    // newest first, except the bucket that is not a day at all.
    if (a.untimed) return 1;
    if (b.untimed) return -1;
    return a.day < b.day ? 1 : -1;
  });
}

// ---------------------------------------------------------- quoting a file

/** A chat line that quotes a dropped file back.
 *
 *  A `kzfile` manifest announces a file; this is the other direction — a
 *  reader saying something *about* it, in the room, without re-sending the
 *  bytes.  The quote rides in the body as `kzquote:<witness> <text>` rather
 *  than in a field of its own, so it is covered by the ordinary message
 *  witness and needs no new trust: a peer renders it as a quote of that file
 *  only if it has actually seen a manifest with that witness, and shows the
 *  text plainly when it has not.
 *
 *  The witness is truncated in the prefix purely so the prefix stays short
 *  to read; `quoteWitness` still matches on the full value, so a truncated
 *  collision would render as plain text rather than as a quote of the wrong
 *  file. */
export const QUOTE_PREFIX = "kzquote:";

/** The prefix a quoting line starts with, for a file's witness. */
export const quotePrefix = (witnessStr) => `${QUOTE_PREFIX}${witnessStr} `;

/** The text a quoting line carries, or null if it is not quoting. */
export function quotedText(m) {
  const t = msgText(m);
  return t.startsWith(QUOTE_PREFIX) ? t.slice(t.indexOf(" ") + 1) : null;
}

/** The witness a quoting line names, or null. */
export function quoteWitness(m) {
  const t = msgText(m);
  if (!t.startsWith(QUOTE_PREFIX)) return null;
  const end = t.indexOf(" ");
  return end < 0 ? null : t.slice(QUOTE_PREFIX.length, end);
}

/** Write a line quoting a manifest, as ordinary timestamped chat. */
export const sayQuote = (room, sender, seq, f, text, at = now()) =>
  sayTextAt(room, sender, seq, `${quotePrefix(manifestWitnessOf(f))}${text}`, at);

// ------------------------------------------------- signalling for WebRTC

// Direct browser-to-browser links need one round of introductions.  The
// offer, the answer and the ICE candidates travel as ordinary lines in the
// same room, so the relay needs no WebRTC support at all: it is still just
// a mailbox.

export const TAG_SIGNAL = asciiBytes("kzsig");

export const ofSignal = (s) => ({
  tag: TAG_SIGNAL,
  fields: [asciiBytes(s.room), asciiBytes(s.from), asciiBytes(s.to), asciiBytes(s.kind),
           utf8(s.payload)],
});

export function toSignal(e) {
  if (!e || !eqBytes(e.tag, TAG_SIGNAL) || e.fields.length !== 5) return null;
  const [room, from, to, kind, payload] = e.fields;
  return {
    room: asciiChars(room), from: asciiChars(from), to: asciiChars(to),
    kind: asciiChars(kind), payload: fromUtf8(payload),
  };
}

export const printSignal = (s) => envelopeEncode(ofSignal(s));
export const parseSignal = (s) => toSignal(envelopeDecode(s));

// --------------------------------------------------- the in-memory relay

/** The relay semantics of `Kant.Relay.Server`: one append-only log per
 *  room.  The browser uses it as a local mirror; `server/relay.mjs` and
 *  `server/worker.js` implement the same thing over HTTP. */
export class Server {
  constructor() { this.rooms = new Map(); }

  lines(room) { return this.rooms.get(room) ?? []; }

  post(room, line) {
    const ls = this.lines(room);
    this.rooms.set(room, [...ls, line]);
    return ls.length + 1;
  }

  /** Everything from `cursor` onwards, plus the new cursor. */
  fetch(room, cursor = 0) {
    const ls = this.lines(room);
    return { lines: ls.slice(cursor), cursor: ls.length };
  }
}

// ------------------------------------------------------ relay transports

/** An HTTP client for a `kant-zk` relay (Cloudflare Worker or Node).
 *
 *  Protocol, deliberately tiny:
 *    GET  {base}/health                       -> { ok, name, version }
 *    POST {base}/room/{room}   body: lines    -> { cursor }
 *    GET  {base}/room/{room}?cursor=N[&wait=S]-> { cursor, lines, truncated }
 */
export class RelayClient {
  constructor(base, { fetchImpl = globalThis.fetch?.bind(globalThis), log = NULL_LOG } = {}) {
    this.base = base.replace(/\/+$/, "");
    this.fetchImpl = fetchImpl;
    this.log = log ?? NULL_LOG;
    this.cursors = new Map();
    if (!this.fetchImpl) this.log.error("relay", "this runtime has no fetch", this.base);
  }

  url(room, extra = "") { return `${this.base}/room/${encodeURIComponent(room)}${extra}`; }

  async health() {
    const r = await this.fetchImpl(`${this.base}/health`);
    return r.json();
  }

  /** Every request goes through here, so every request is logged: the URL,
   *  the status, and the error if it never got that far. */
  async request(url, init, what) {
    this.log.info("relay", `${what}…`, url);
    let r;
    try {
      r = await this.fetchImpl(url, init);
    } catch (e) {
      this.log.error("relay", `${what} could not reach the relay`, `${url} — ${e.message ?? e}`);
      throw e;
    }
    if (!r.ok) {
      this.log.error("relay", `${what} was refused (${r.status})`, url);
      throw new Error(`relay ${what} failed: ${r.status}`);
    }
    return r;
  }

  /** Post one or more lines into a room.
   *
   *  `extraHeaders` carries a `x-kant-invite` (or `x-kant-pass`) for a
   *  client that writes on someone else's behalf. Without one the relay
   *  charges the post to an anonymous sender and holds it to the per-sender
   *  rate limit, which a bridge carrying a backlog will hit immediately. */
  async post(room, lines, extraHeaders = null) {
    const body = (Array.isArray(lines) ? lines : [lines]).join("\n");
    const r = await this.request(this.url(room), {
      method: "POST",
      headers: { "content-type": "text/plain", ...(extraHeaders ?? {}) },
      body,
    }, `post ${body.split("\n").length} line(s)`);
    const out = await r.json();
    this.log.info("relay", "the relay took the line(s)", `cursor=${out.cursor ?? "?"}`);
    return out;
  }

  /** Poll a room.  `wait` seconds asks the relay to hold the request open
   *  until something arrives (long polling). */
  async poll(room, { wait = 0 } = {}) {
    const cursor = this.cursors.get(room) ?? 0;
    const q = `?cursor=${cursor}${wait ? `&wait=${wait}` : ""}`;
    const r = await this.request(this.url(room, q), undefined, `poll from ${cursor}`);
    const out = await r.json();
    this.cursors.set(room, out.cursor);
    if (out.lines?.length) {
      this.log.info("relay", `the relay had ${out.lines.length} new line(s)`,
        `cursor=${out.cursor}`);
    }
    return out;
  }

  /** Start again from the beginning of a room. */
  rewind(room) { this.cursors.set(room, 0); }
}

/** A WebSocket client for the same relay: `{base}/ws/{room}?cursor=N`.
 *  Lines are sent as text frames; the relay pushes `{cursor, lines}`. */
export class RelaySocket {
  constructor(base, room, { cursor = 0, onLines = () => {}, onOpen = () => {},
                            onClose = () => {}, WebSocketImpl = globalThis.WebSocket,
                            log = NULL_LOG } = {}) {
    this.log = log ?? NULL_LOG;
    const wsBase = base.replace(/^http/, "ws").replace(/\/+$/, "");
    this.url = `${wsBase}/ws/${encodeURIComponent(room)}?cursor=${cursor}`;
    this.room = room;
    this.onLines = onLines;
    this.WebSocketImpl = WebSocketImpl;
    this.onOpen = onOpen;
    this.onClose = onClose;
    this.queue = [];
    this.ws = null;
  }

  open() {
    if (typeof this.WebSocketImpl !== "function") {
      this.log.warn("socket", "this runtime has no WebSocket", this.url);
      return this;
    }
    this.log.info("socket", "opening the relay socket", this.url);
    const ws = new this.WebSocketImpl(this.url);
    this.ws = ws;
    ws.addEventListener("open", () => {
      this.log.info("socket", "the relay socket is open", this.url);
      for (const l of this.queue.splice(0)) ws.send(l);
      this.onOpen();
    });
    ws.addEventListener("error", (ev) =>
      this.log.error("socket", "the relay socket failed", ev?.message ?? this.url));
    ws.addEventListener("message", (ev) => {
      let msg = null;
      try { msg = JSON.parse(typeof ev.data === "string" ? ev.data : ""); } catch { return; }
      if (msg && Array.isArray(msg.lines)) this.onLines(msg.lines, msg.cursor);
    });
    ws.addEventListener("close", (ev) => {
      this.log.warn("socket", `the relay socket closed (${ev?.code ?? "?"})`, this.url);
      this.onClose();
    });
    return this;
  }

  send(line) {
    if (this.ws && this.ws.readyState === 1) this.ws.send(line);
    else this.queue.push(line);
  }

  close() { if (this.ws) this.ws.close(); }
}

/** Discovery with no server at all: other tabs of the same browser.
 *  Useful for testing, and genuinely useful for a user with two tabs. */
export class LocalBus {
  constructor(room, onLine, { Impl = globalThis.BroadcastChannel, log = NULL_LOG } = {}) {
    this.log = log ?? NULL_LOG;
    this.ok = typeof Impl === "function";
    this.name = `kantzk:${room}`;
    if (!this.ok) {
      this.log.warn("bus", "this browser has no BroadcastChannel: other tabs cannot be " +
        "found without a relay", this.name);
      return;
    }
    this.ch = new Impl(this.name);
    this.ch.onmessage = (ev) => {
      if (typeof ev.data === "string") {
        this.log.info("bus", "a line arrived from another tab", `${ev.data.length} chars`);
        onLine(ev.data);
      }
    };
    this.log.info("bus", "listening for other tabs of this browser", this.name);
  }

  send(line) {
    if (!this.ok) return false;
    this.ch.postMessage(line);
    return true;
  }

  close() {
    if (this.ok) { this.ch.close(); this.log.info("bus", "stopped listening", this.name); }
  }
}

// --------------------------------------------------------- the WebRTC mesh

/** Direct peer-to-peer data channels, introduced through the relay.
 *
 *  The relay only ever carries `kzsig` lines; once a channel is up, chat
 *  lines and announcements go straight between the browsers, and the same
 *  `accept` check applies to them.
 */
export class PeerMesh {
  constructor({ self, room, sendSignal, onLine, rtcConfig, log = NULL_LOG } = {}) {
    this.log = log ?? NULL_LOG;
    this.self = self;
    this.room = room;
    this.sendSignal = sendSignal;
    this.onLine = onLine ?? (() => {});
    this.rtcConfig = rtcConfig ?? { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
    this.peers = new Map();
  }

  get connected() {
    return [...this.peers.entries()]
      .filter(([, p]) => p.channel && p.channel.readyState === "open")
      .map(([id]) => id);
  }

  newConnection(other) {
    const RTC = globalThis.RTCPeerConnection;
    if (!RTC) {
      this.log.warn("mesh", "this runtime has no WebRTC: everything goes through the relay",
        other);
      return null;
    }
    const pc = new RTC(this.rtcConfig);
    const entry = { pc, channel: null };
    this.peers.set(other, entry);
    pc.oniceconnectionstatechange = () =>
      this.log.record(pc.iceConnectionState === "failed" ? "error" : "info", "mesh",
        `direct link to ${other}: ${pc.iceConnectionState}`, "");
    pc.onicecandidate = (ev) => {
      if (ev.candidate) {
        this.sendSignal({
          room: this.room, from: this.self, to: other,
          kind: "ice", payload: JSON.stringify(ev.candidate),
        });
      }
    };
    pc.ondatachannel = (ev) => this.attach(entry, ev.channel);
    return entry;
  }

  attach(entry, channel) {
    entry.channel = channel;
    channel.onopen = () => this.log.info("mesh", "a direct channel is open", channel.label);
    channel.onclose = () => this.log.warn("mesh", "a direct channel closed", channel.label);
    channel.onerror = (ev) =>
      this.log.error("mesh", "a direct channel failed", ev?.message ?? channel.label);
    channel.onmessage = (ev) => { if (typeof ev.data === "string") this.onLine(ev.data); };
  }

  /** Offer a direct channel to another peer (introduce ourselves). */
  async offer(other) {
    this.log.info("mesh", `offering a direct link to ${other}`, "");
    const entry = this.newConnection(other);
    if (!entry) return false;
    this.attach(entry, entry.pc.createDataChannel("kantzk"));
    const desc = await entry.pc.createOffer();
    await entry.pc.setLocalDescription(desc);
    this.sendSignal({
      room: this.room, from: this.self, to: other,
      kind: "offer", payload: JSON.stringify(desc),
    });
    return true;
  }

  /** Handle one signalling line addressed to us. */
  async onSignal(sig) {
    if (!sig || sig.to !== this.self || sig.from === this.self) return;
    if (sig.kind === "offer") {
      const entry = this.newConnection(sig.from);
      if (!entry) return;
      await entry.pc.setRemoteDescription(JSON.parse(sig.payload));
      const answer = await entry.pc.createAnswer();
      await entry.pc.setLocalDescription(answer);
      this.sendSignal({
        room: this.room, from: this.self, to: sig.from,
        kind: "answer", payload: JSON.stringify(answer),
      });
    } else if (sig.kind === "answer") {
      const entry = this.peers.get(sig.from);
      if (entry) await entry.pc.setRemoteDescription(JSON.parse(sig.payload));
    } else if (sig.kind === "ice") {
      const entry = this.peers.get(sig.from);
      if (entry) {
        try { await entry.pc.addIceCandidate(JSON.parse(sig.payload)); }
        catch (e) { this.log.warn("mesh", "an ICE candidate was refused", e?.message ?? ""); }
      }
    }
  }

  /** Send a line to every open channel; returns how many got it. */
  broadcast(line) {
    let n = 0;
    for (const [, p] of this.peers) {
      if (p.channel && p.channel.readyState === "open") { p.channel.send(line); n += 1; }
    }
    return n;
  }

  close() {
    for (const [, p] of this.peers) {
      try { p.pc.close(); }
      catch (e) { this.log.warn("mesh", "closing a direct link failed", e?.message ?? ""); }
    }
    this.peers.clear();
  }
}

// ------------------------------------------------------------- the client

/** A whole client: an identity, a room, a roster, a transcript, and every
 *  transport wired to the same `accept` check.
 *
 *  Lines that arrive — from the relay, from another tab, from a direct
 *  data channel, from a pasted string or a scanned code — all go through
 *  `ingest`, and only self-certifying ones are kept.  This is what makes
 *  the transport irrelevant to what is displayed
 *  (`Kant.Relay.clients_agree`).
 */
export class KantNode {
  constructor({ peer, relay = "", room = "", secret = null, addrs = [],
                fetchImpl, onChange = () => {}, log = null, reach = null } = {}) {
    this.self = peer ?? peerIdOf(freshSecret(16));
    this.log = log ?? new DiagLog({ cap: 2000 });
    this.relayBase = relay;
    this.secret = secret;
    this.room = room || (secret ? roomOf(secret) : "");
    this.addrs = addrs;
    this.seq = 0;
    this.roster = [];
    this.messages = [];
    // Chat that carries a sender-declared time (`kzat`), kept apart from
    // `messages` so an old peer still shows the room.
    this.timed = [];
    this.onChange = onChange;
    this.fetchImpl = fetchImpl;
    this.reach = reach;
    this.busWanted = true;
    this.client = relay ? new RelayClient(relay, { fetchImpl, log: this.log }) : null;
    this.bus = null;
    this.mesh = null;
    this.polling = false;
    this.log.info("app", `client ${this.self} started`,
      relay ? `relay=${relay}` : "no relay: only other tabs of this browser can find you");
  }

  /** The hex of the room secret, so the diagnostics can refuse to share
   *  any line quoting it. */
  get secretHex() { return this.secret ? hexEncode(Array.from(this.secret)) : ""; }

  /** Everything a shared run must never quote. */
  secrets() {
    const out = [];
    if (this.secretHex) out.push(this.secretHex);
    if (this.secret) out.push(copyInvite(invite(this.relayBase, this.secret, this.self,
      this.addrs)));
    return out;
  }

  /** The invitation to show as a QR code or a link. */
  inviteText() {
    if (!this.secret) return "";
    return copyInvite(invite(this.relayBase, this.secret, this.self, this.addrs));
  }

  /** Check that the relay we would actually talk to answers, and fall back
   *  to `fallback` when it does not.
   *
   *  `joinInvite` takes the relay from the invite without probing it, which
   *  is right — the invite is the only thing that knows where the room is —
   *  and is also how a room gets stranded. An invite minted while the
   *  deployment named a dead relay sends every joiner to that dead relay,
   *  even when the page is being served by a working one that has the same
   *  room: the banner is about the serving relay, the client is on the
   *  invite's, and nothing warns.
   *
   *  So probe, and if it does not answer, use `fallback` — but say so loudly.
   *  A room on the wrong relay is not the same room, so falling back is a
   *  visible event, never a quiet one.
   *
   *  Separate from `joinInvite` because that is synchronous and has callers
   *  that must stay so; this is the async half, run before the node attaches.
   */
  async settleRelay({ fallback = "", timeoutMs = 4000 } = {}) {
    const named = this.relayBase;
    if (!named || named === fallback) {
      return { used: named, fellBack: false, reason: named ? "same as the fallback" : "no relay named" };
    }
    const probe = await probeRelay(named, { fetchImpl: this.fetchImpl, log: this.log, timeoutMs });
    if (probe.ok) return { used: named, fellBack: false, probe };

    if (!fallback) {
      this.log.error("app",
        `the invitation names ${named} and it did not answer (${probe.reason}); ` +
        "there is no other relay to use", named);
      return { used: named, fellBack: false, probe, reason: probe.reason };
    }

    this.relayBase = fallback;
    this.client = new RelayClient(fallback, { fetchImpl: this.fetchImpl, log: this.log });
    this.relayWarned = named;
    this.log.error("app",
      `the invitation names ${named} and it did not answer (${probe.reason}); ` +
      `using ${fallback} instead — ask whoever sent it to send a fresh invite, ` +
      "or you may be in a different room than they are", named);
    this.onChange();
    return { used: fallback, fellBack: true, from: named, probe };
  }

  /** Join the room named by a scanned invitation. */
  joinInvite(text) {
    const i = pasteInvite(text) ?? parseInviteUrl(text);
    if (!i) return null;
    this.secret = i.secret;
    this.room = inviteRoom(i);
    if (i.relay) {
      this.relayBase = i.relay;
      this.client = new RelayClient(i.relay, { fetchImpl: this.fetchImpl, log: this.log });
      this.log.info("app", "the invitation names a relay", i.relay);
    } else if (!this.relayBase) {
      this.log.warn("app", "this invitation names no relay: unless you are in the same " +
        "browser as whoever sent it, there is nothing to meet on", "");
    }
    this.roster = rosterInsert(this.roster, announce(i.peer, 0, i.addrs));
    this.log.info("app", `joined room ${diagRef(this.room)} (invited by ${i.peer})`, "");
    // The bus and the mesh are named after the room, so a room change has
    // to move them; leaving them behind was a silent way of never meeting
    // anybody.
    if (this.bus || this.mesh) this.connect({ bus: this.busWanted });
    this.onChange();
    return i;
  }

  /** Start a brand new room and return the invitation for it. */
  createRoom(relayBase = this.relayBase) {
    this.secret = freshSecret();
    this.room = roomOf(this.secret);
    this.relayBase = relayBase;
    if (relayBase) {
      this.client = new RelayClient(relayBase, { fetchImpl: this.fetchImpl, log: this.log });
    } else {
      this.client = null;
      this.log.warn("app", "opening a room with no relay: only other tabs of this browser " +
        "will be able to join", "");
    }
    this.log.info("app", `opened room ${diagRef(this.room)}`, relayBase || "no relay");
    if (this.bus || this.mesh) this.connect({ bus: this.busWanted });
    this.onChange();
    return this.inviteText();
  }

  /** Our own announcement, at the current revision. */
  ownAnnounce() { return announce(this.self, this.seq, this.addrs); }

  /** Take a line from any transport. */
  ingest(line) {
    const before = this.messages.length + this.timed.length +
      this.roster.length + (this.files?.length ?? 0);
    if (typeof line !== "string" || line === "") {
      this.log.warn("ingest", "an empty line arrived", "");
      return { message: null, timed: null, announce: null, signal: null, file: null };
    }
    const m = parseMsg(line);
    if (m && m.room === this.room) this.messages = accept(this.messages, line);
    // A `kzat` line is chat that also carries the sender's clock. It lives
    // in its own list rather than in `messages` so that a peer which
    // predates it still shows a room with no times instead of no room at
    // all; `viewAt` merges the two for display.
    const t = parseTimed(line);
    if (t && t.room === this.room) this.timed = acceptTimed(this.timed, line);
    const a = parseAnnounce(line);
    if (a) this.roster = rosterInsert(this.roster, a);
    const sig = parseSignal(line);
    if (sig && this.mesh && sig.room === this.room) this.mesh.onSignal(sig);
    // A dropped file arrives as an ordinary room line: a kzfile manifest
    // naming the file, its size, and the digests its chunks are pinned
    // under.  It certifies itself exactly like a chat line, so a forged
    // or mangled announcement is refused before a single chunk is fetched.
    const file = parseManifest(line);
    if (file && file.room === this.room) {
      this.files = this.files ?? [];
      if (!this.files.some((f) => printManifest(f) === line)) this.files.push(file);
    }
    if (m && m.room !== this.room) {
      this.log.warn("ingest", "a line for another room was ignored", diagRef(m.room));
    }
    if (!m && !t && !a && !sig && !file) {
      this.log.warn("ingest", "a line was refused: it does not certify itself",
        `${line.slice(0, 24)}…`);
    }
    if (this.messages.length + this.timed.length + this.roster.length +
        (this.files?.length ?? 0) !== before) {
      this.log.info("ingest", "a line was accepted",
        m ? "chat" : t ? "chat (timed)" : a ? `peer ${a.peer}` : sig ? "signal" : "file");
      this.onChange();
    }
    return { message: m, timed: t, announce: a, signal: sig, file };
  }

  /** The chat as displayed. */
  view() { return transcript(this.messages); }

  /** Everything said, timed and untimed together, in declared time order.
   *
   *  An untimed `kzchat` line has no clock of its own, so it carries
   *  `at: null` and sorts after the timed ones rather than being dropped:
   *  dropping it would silently hide every message from a peer that predates
   *  `kzat`.  `viewByDay` puts them in their own untitled bucket, so the
   *  time-stored view never attributes a message to a day it was not sent
   *  on. */
  viewAt() {
    return transcriptAt([
      ...this.timed,
      ...this.messages.map((m) => ({ ...m, at: null })),
    ]);
  }

  /** The transcript grouped by UTC day, newest first, untimed last. */
  viewByDay() {
    return byDay([
      ...this.timed,
      ...this.messages.map((m) => ({ ...m, at: null })),
    ]);
  }

  /** Say something, timestamped, to everyone in the room. */
  async sayAt(text) {
    const line = printTimed(sayTextAt(this.room, this.self, this.seq, text));
    await this.publish(line);
    return line;
  }

  /** Announce a dropped file to the room: cut, encrypt, pin every chunk,
   *  then publish the manifest as one self-certifying line.  The relay and
   *  IPFS only ever see ciphertext.
   *
   *  `pin` puts each chunk on IPFS as well as the relay.  A partial pin is
   *  reported rather than announced as complete: `putChunks` stops at the
   *  first refusal, so the manifest carries no ipfs names at all unless
   *  every chunk landed — a half-pinned manifest would leave a reader
   *  fetching names that do not exist. */
  async dropFile(name, mime, data, { secret = this.secret, pin = false } = {}) {
    if (!secret) throw new Error("dropping a file needs the room secret");
    const { encryptFile, manifest } = await import("./kant-file.mjs");
    const enc = await encryptFile(secret, name, mime, data);
    let ipfs = [];
    if (pin) {
      const { putChunks } = await import("./kant-file-ipfs.mjs");
      const res = await putChunks(enc.chunks);
      if (res.complete) {
        ipfs = res.cids;
      } else {
        this.log.warn("file", `ipfs kept only ${res.cids.length}/${enc.chunks.length}` +
          " chunk(s); announcing without ipfs names so no reader chases a missing CID",
          `failed at chunk ${res.failedAt}`);
      }
    }
    this.seq += 1;
    const f = manifest(this.room, this.self, this.seq, name, mime,
      enc.size, enc.nonce, enc.cids, ipfs);
    await this.publish(printManifest(f));
    return f;
  }

  /** The peers known, freshest announcement each. */
  peers() { return rosterPeers(this.roster); }

  /** Send a line by every route we have: direct channels first, then the
   *  local bus, then the relay. */
  async publish(line) {
    this.ingest(line);
    let direct = 0;
    if (this.mesh) direct = this.mesh.broadcast(line);
    const onBus = this.bus ? this.bus.send(line) : false;
    let toRelay = false;
    if (this.client && this.room) {
      try {
        await this.client.post(this.room, line);
        toRelay = true;
      } catch (e) {
        this.log.error("relay", "the line did not reach the relay", e);
      }
    } else if (this.room) {
      this.log.warn("relay", "no relay to publish to", "");
    }
    this.log.info("app", "published a line",
      `direct=${direct} bus=${onBus} relay=${toRelay}`);
    if (!direct && !onBus && !toRelay) {
      this.log.error("app", "that line went nowhere: nobody can have received it", "");
    }
    return direct;
  }

  /** Announce ourselves into the room. */
  async announceSelf() {
    this.seq += 1;
    return this.publish(printAnnounce(this.ownAnnounce()));
  }

  /** Say something. */
  async say(text) {
    this.seq += 1;
    return this.publish(printMsg(sayText(this.room, this.self, this.seq, text)));
  }

  /** Say something with our own clock attached, so the room reads in the
   *  order it was talked.  `say` above stays on plain `kzchat` because that
   *  is what every peer already understands; this is the opt-in form. */
  async sayStamped(text) { return this.sayAt(text); }

  /** Reply to a dropped file, quoting it by its witness.  The quote is part
   *  of the message body, so it is covered by the ordinary witness and a
   *  peer can check it against a manifest it has actually seen. */
  async quoteFile(f, text) {
    this.seq += 1;
    const line = printTimed(sayQuote(this.room, this.self, this.seq, f, text));
    await this.publish(line);
    return line;
  }

  /** Attach the same-browser bus and the WebRTC mesh. */
  connect({ rtcConfig, bus = true } = {}) {
    if (!this.room) {
      this.log.warn("app", "connect() with no room: open a room or paste an invite first", "");
      return this;
    }
    this.busWanted = bus;
    if (this.bus) this.bus.close();
    if (this.mesh) this.mesh.close();
    this.bus = bus
      ? new LocalBus(this.room, (l) => this.ingest(l), { log: this.log })
      : null;
    this.mesh = new PeerMesh({
      self: this.self,
      room: this.room,
      rtcConfig,
      log: this.log,
      sendSignal: (s) => this.publishSignal(s),
      onLine: (l) => this.ingest(l),
    });
    if (!this.client) {
      this.log.warn("app", "no relay in use: anybody outside this browser will not see you",
        "");
    }
    return this;
  }

  /** Signalling lines go over the relay and the bus, never over the mesh
   *  itself. */
  async publishSignal(s) {
    const line = printSignal(s);
    if (this.bus) this.bus.send(line);
    if (this.client && this.room) {
      try { await this.client.post(this.room, line); }
      catch (e) { this.log.error("signal", "a signalling line did not reach the relay", e); }
    } else {
      this.log.warn("signal", "no relay: direct links cannot be introduced", s.kind);
    }
  }

  /** Try to open direct channels to everybody we know about. */
  async dialKnownPeers() {
    if (!this.mesh) return 0;
    let n = 0;
    for (const p of this.peers()) {
      if (!p || p.peer === this.self || this.mesh.peers.has(p.peer)) continue;
      if (await this.mesh.offer(p.peer)) n += 1;
    }
    return n;
  }

  /** One poll of the relay. */
  async pollOnce({ wait = 0 } = {}) {
    if (!this.client || !this.room) {
      this.log.warn("relay", "nothing to poll: no relay in use", "");
      return 0;
    }
    const out = await this.client.poll(this.room, { wait });
    for (const l of out.lines) this.ingest(l);
    return out.lines.length;
  }

  /** Keep polling until `stop()`.  Long polling when the relay supports
   *  it, plain polling otherwise. */
  async startPolling({ wait = 25, interval = 1000 } = {}) {
    if (this.polling) return;
    this.polling = true;
    let failures = 0;
    // Said once, not once per turn round the loop: with no relay there is
    // nothing to poll, and a client that says so a thousand times a second
    // is a busy loop that starves every timer on the page.
    let saidIdle = false;
    while (this.polling) {
      if (!this.client || !this.room) {
        if (!saidIdle) {
          saidIdle = true;
          this.log.warn("relay", "nothing to poll: no relay in use",
            "waiting in case one turns up");
        }
        await sleep(interval);
        continue;
      }
      saidIdle = false;
      try {
        await this.pollOnce({ wait });
        failures = 0;
      } catch (e) {
        failures += 1;
        if (failures <= 3 || failures % 5 === 0) {
          this.log.error("relay", `polling failed (${failures} in a row)`, e);
        }
        await sleep(Math.min(interval * failures, 15000));
      }
      // Always yield, even when the relay answers at once: a long poll that
      // returns immediately must not turn into a spin.
      await sleep(wait ? 25 : interval);
    }
  }

  stop() {
    this.polling = false;
    if (this.bus) this.bus.close();
    if (this.mesh) this.mesh.close();
    this.log.info("app", "left the room", "");
  }

  /** This client as the diagnostics see it (`Kant.Connectivity.Client`). */
  asClient({ browser = 1 } = {}) {
    return clientOf({
      room: this.room,
      reach: this.reach ?? {
        configured: this.relayBase, configuredUp: !!this.client,
        origin: "", originIsRelay: false,
      },
      bus: !!(this.bus && this.bus.ok),
      browser,
    });
  }

  /** What the diagnostics page shows and shares: the verdict against a
   *  second client (the other end, or this client seen from another
   *  browser), the room's handle, the relay in use, and every event that
   *  quotes no secret (`Kant.Diagnostics.Report`). */
  report({ other = null, browser = 1 } = {}) {
    const self = this.asClient({ browser });
    const them = other ?? { ...self, browser: browser + 1, bus: false };
    return {
      verdict: diagnose(self, them),
      room: this.room ? diagRef(this.room) : "",
      relay: effectiveRelay(self.reach),
      events: this.log.share(this.secrets()),
      dropped: this.log.dropped,
    };
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
