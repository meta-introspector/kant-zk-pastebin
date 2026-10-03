// kant-share.mjs — get this client's instructions into other hands.
//
// A client's one line of instructions is its link: the site, and after
// the `#`, the room.  Any channel that can move one line of text can
// move an invitation: the pastebin (kant-cli `pastebinit`), a tweet, a
// direct message, a QR code, a gist.  This module is the shared carrier
// layer over `kant-pastebin.mjs`: it turns "share my link" and "take in
// what was shared" into one-line calls for each channel, and keeps the
// same shape for the channels that are not built yet.
//
// Every channel is a record of two verbs, mirroring the UUCP carriers of
// `kant-uucp.mjs` (tweet, dm, qr, urlBar, bio, altText):
//
//   share(text)   -> what to put in that channel (a URL, a code, a file)
//   take(query)   -> the text somebody put there (or null)
//
// so a new channel is one function, not a new protocol.  The channels
// that need a network or a user account are stubs with a clear "not
// wired yet" answer, so callers can list what exists and what does not.
//
// Run the checks:  node web/share-test.mjs

import { pasteApi, pasteSpool, parsePasteUrl } from "./kant-pastebin.mjs";
import { qrEncode, qrSvg } from "./kant-qr.mjs";
import { CARRIER_CAPACITY } from "./kant-uucp.mjs";

// ---------------------------------------------------------------- helpers

/** Split one text into chunks that fit a carrier's capacity
 *  (`CARRIER_CAPACITY`: tweet 280, dm 10000, qr 2953, urlBar 2000,
 *  bio 160, altText 1000).  Returns the whole text as one chunk when it
 *  fits. */
export function chunksFor(text, carrier) {
  const cap = CARRIER_CAPACITY[carrier];
  if (!cap) throw new Error(`no such carrier: ${carrier}`);
  const t = String(text);
  const out = [];
  for (let i = 0; i < t.length; i += cap) out.push(t.slice(i, i + cap));
  return out;
}

// -------------------------------------------------------------- channels

/** The pastebin channel: put the link on any Kant pastebin, take in
 *  whatever paste a URL names — or, with no query at all, whatever the
 *  local spool holds (the `accept` flow of kant-cli.mjs).
 *
 *   const ch = pastebinChannel("https://solana.solfunmeme.com/pastebin",
 *                              "/var/spool/uucp/pastebin");
 *   const { url } = await ch.share(link);
 *   await ch.take(url);              // -> the link again
 *   await ch.take();                 // newest loadable paste in the spool
 */
export function pastebinChannel(backend, spoolDir = null, { takeFn } = {}) {
  const api = pasteApi(backend);
  const spool = spoolDir ? pasteSpool(spoolDir) : null;
  const canTake = (text) => (takeFn ? takeFn(text) : text);

  return {
    name: "pastebin",
    /** Put one text on the pastebin.  Returns the paste record: url,
     *  permalink, id, cid, witness. */
    async share(text, opts) {
      return api.put(text, opts);
    },
    /** Take one text in: a paste URL names it (on any pastebin — the
     *  URL says whose), a bare id names one on our backend, or with no
     *  argument the local spool is walked newest-first until `takeFn`
     *  accepts a paste (default: every paste is accepted).  Returns
     *  null when nothing loadable is there. */
    async take(query) {
      if (query != null && query !== "") {
        const p = parsePasteUrl(query);
        const origin = (u) => { try { return new URL(u).origin; } catch { return null; } };
        const sameHost = p && origin(p.backend) === origin(backend);
        if (p && p.backend && !sameHost) {
          const other = pasteApi(p.backend);   // a URL naming another pastebin
          return canTake(await other.get(query));
        }
        if (spool) {
          const local = spool.read(p ? p.id : query);
          if (local !== null) return canTake(local);
        }
        return canTake(await api.get(query));
      }
      if (!spool) return null;
      const got = spool.take((text) => canTake(text));
      return got ? got.value : null;
    },
    api,
    spool,
  };
}

/** The QR channel: no network at all, just light.  `share` renders the
 *  text as a self-contained SVG QR code (byte mode, level L — the
 *  2953-byte `Kant.Sneakernet.Channel.qr` bound); `take` is a stub: a
 *  camera is not a file, and scanning is the receiving client's job. */
export function qrChannel() {
  return {
    name: "qr",
    capacity: CARRIER_CAPACITY.qr,
    share(text) {
      const t = String(text);
      if (t.length > CARRIER_CAPACITY.qr) {
        throw new Error(`text is ${t.length} chars; a QR code holds ${CARRIER_CAPACITY.qr}`);
      }
      return qrSvg(qrEncode(t), { scale: 4, border: 4 });
    },
    take() { return null; }, // scanning a QR is the receiving side's job
  };
}

/** A channel that does not exist yet.  Every future carrier — twitter,
 *  discord, telegram, facebook, gists — gets one of these until it is
 *  wired: `share` and `take` both answer "not wired", and `channels()`
 *  below lists it as unavailable rather than pretending. */
export function unwiredChannel(name, { why = "not wired yet" } = {}) {
  return {
    name,
    unwired: true,
    why,
    share() { throw new Error(`${name}: ${why}`); },
    take() { return null; },
  };
}

/** Every channel this module knows about, wired or not.  The unwired
 *  ones are listed so a caller (or an agent asking itself what it can
 *  do) sees the full roadmap, not just what works today. */
export function channels({ backend, spoolDir, takeFn } = {}) {
  return {
    pastebin: pastebinChannel(backend, spoolDir, { takeFn }),
    qr: qrChannel(),
    tweet: unwiredChannel("tweet", { why: "no twitter client wired yet" }),
    discord: unwiredChannel("discord", { why: "no discord bot wired yet" }),
    telegram: unwiredChannel("telegram", { why: "no telegram bot wired yet" }),
    facebook: unwiredChannel("facebook", { why: "no facebook client wired yet" }),
    gist: unwiredChannel("gist", { why: "no github client wired yet" }),
  };
}
