// kant-cli.mjs — the command-line client, function for function.
//
// An unverified transcription of `RequestProject/Kant/Cli.lean`.  Every
// definition below has the same name as the Lean one, and `web/cli-test.mjs`
// checks it against vectors Lean itself computed.
//
// The point of the module: an agent at a terminal, a person in a browser and
// somebody typing `curl` by hand are all doing the same thing.  The requests
// are the same requests (`curlArgv`), the relay routes them the same way
// (`route`), and the state each side ends in is the same state
// (`say_eq_browserSay`, `poll_eq_browserPoll` in the Lean).

import { witness, hexEncode, hexDecode, utf8, fromUtf8 } from "./kantzk.mjs";
import {
  roomOf, invite, copyInvite, pasteInvite, parseInviteUrl, inviteRoom,
  printMsg, parseMsg, sayText, msgText, accept, receive, transcript,
  printAnnounce, parseAnnounce, announce,
  printTimed, parseTimed, sayTextAt, receiveTimed, sayQuote, quoteWitness,
  quotedText,
} from "./kant-net.mjs";
import {
  encryptFile, decryptFile, manifest, printManifest, parseManifest,
  manifestWitness, cidOf, CHUNK_SIZE,
} from "./kant-file.mjs";
import { findInvite } from "./kant-flow.mjs";
import { bagUrl, readBagUrl, packBag, openBag } from "./kant-uucp.mjs";

// ------------------------------------------------------------- numerals

/** The character of a decimal digit (`digitChar`). */
export const digitChar = (k) => String.fromCharCode(48 + k);

/** A number written out in decimal (`decNum`). */
export function decNum(n) {
  const k = Math.trunc(Number(n));
  if (!Number.isFinite(k) || k < 0) return "0";
  return k < 10 ? digitChar(k) : decNum(Math.floor(k / 10)) + digitChar(k % 10);
}

/** The numeric value of the decimal digits in a string (`digitsValue`). */
export const digitsValue = (s) =>
  Array.from(String(s)).reduce(
    (acc, c) => (c >= "0" && c <= "9" ? acc * 10 + (c.charCodeAt(0) - 48) : acc),
    0,
  );

// ------------------------------------------------------- command lines

/** Join words with single spaces (`joinSp`). */
export const joinSp = (ws) => ws.join(" ");

/** Split a command line into words (`splitCh ' '`). */
export const splitSp = (s) => String(s).split(" ");

// --------------------------------------------------------- the requests

/** A read (`getReq`). */
export const getReq = (url) => ({ method: "get", url, body: "" });

/** A write (`postReq`). */
export const postReq = (url, body) => ({ method: "post", url, body });

/** The `curl` command line for a request, as arguments (`curlArgv`). */
export function curlArgv(r) {
  return r.method === "get"
    ? ["curl", "-sS", r.url]
    : ["curl", "-sS", "-X", "POST", "-H", "content-type:text/plain",
       "--data-binary", r.body, r.url];
}

/** Read a `curl` command line back as the request it makes (`reqOfArgv`). */
export function reqOfArgv(ws) {
  if (ws.length === 3) {
    return ws[0] === "curl" && ws[1] === "-sS" ? getReq(ws[2]) : null;
  }
  if (ws.length === 9) {
    const ok = ws[0] === "curl" && ws[1] === "-sS" && ws[2] === "-X" && ws[3] === "POST" &&
      ws[4] === "-H" && ws[5] === "content-type:text/plain" && ws[6] === "--data-binary";
    return ok ? postReq(ws[8], ws[7]) : null;
  }
  return null;
}

/** The command line as one string (`curlLine`). */
export const curlLine = (r) => joinSp(curlArgv(r));

/** Read a command line back (`parseCurlLine`). */
export const parseCurlLine = (s) => reqOfArgv(splitSp(s));

// --------------------------------------------------------- the routes

/** The path of a room (`roomPath`). */
export const roomPath = (room) => `/room/${room}`;

/** The query string that asks for everything after a cursor (`cursorQuery`). */
export const cursorQuery = (cursor) => `?cursor=${decNum(cursor)}`;

/** Strip a known prefix (`afterPrefix`). */
export const afterPrefix = (p, s) => (s.startsWith(p) ? s.slice(p.length) : null);

/** The relay's router (`route`). */
export function route(path) {
  const rest = afterPrefix("/room/", path);
  if (rest === null) return null;
  const at = rest.indexOf("?");
  if (at < 0) return { room: rest, cursor: 0 };
  return { room: rest.slice(0, at), cursor: digitsValue(rest.slice(at + 1)) };
}

/** Everything before the `'#'`: all a static host ever sees (`pageOf`). */
export const pageOf = (u) => {
  const at = String(u).indexOf("#");
  return at < 0 ? String(u) : String(u).slice(0, at);
};

// ------------------------------------------------------------ the client

/** A brand new client holding a brand new room (`openRoom`). */
export const openRoom = (self, relay, secret) => ({
  self, relay, secret: Array.from(secret), seq: 0, cursor: 0, lines: [],
});

/** The room a client is in (`Client.room`). */
export const clientRoom = (c) => roomOf(c.secret);

/** The invitation this client hands out (`Client.invite`). */
export const clientInvite = (c) => invite(c.relay, c.secret, c.self, []);

/** The link it prints: the site, and the invitation in the fragment
 *  (`Client.link`). */
export const clientLink = (cfg, c) => `${cfg.origin}#${copyInvite(clientInvite(c))}`;

/** Join whatever room a pasted message names (`joinText`).  A whole link,
 *  a bare code, or either of them inside a sentence somebody sent you. */
export function joinText(self, text) {
  const i = findInvite(String(text)) ?? pasteInvite(String(text).trim()) ??
    parseInviteUrl(String(text).trim());
  if (!i) return null;
  return { self, relay: i.relay, secret: Array.from(i.secret), seq: 0, cursor: 0, lines: [] };
}

/** The request that posts a line (`postLine`). */
export const postLine = (c, line) => postReq(`${c.relay}${roomPath(clientRoom(c))}`, line);

/** The request that pins one encrypted chunk under its witness
 *  (`/room/<addr>/block/<cid>`).  Binary, so the content type is octet-stream
 *  rather than the text/plain a line uses — the relay reads the body either
 *  way, but saying so keeps it honest for anything reading the logs. */
export const blockUrl = (c, cid) => `${c.relay}${roomPath(clientRoom(c))}/block/${cid}`;

export const postBlock = (c, cid, bytes) => ({
  method: "post",
  url: blockUrl(c, cid),
  body: bytes,
  binary: true,
});

/** The request that reads everything new (`pollFrom`). */
export const pollFrom = (c) =>
  getReq(`${c.relay}${roomPath(clientRoom(c))}${cursorQuery(c.cursor)}`);

/** The request that fetches one chunk back by its witness
 *  (`/room/<addr>/block/<cid>`). */
export const getBlock = (c, cid) => getReq(blockUrl(c, cid));

/** The message a client is about to write (`Client.compose`). */
export const compose = (c, text) => sayText(clientRoom(c), c.self, c.seq + 1, text);

/** The messages a client holds, from the lines it has kept. */
export const messagesOf = (c) => receive([], c.lines);

/** The conversation it displays (`Client.view`). */
export const view = (c) => transcript(messagesOf(c));

/** The conversation as plain text lines, newest last. */
export const viewText = (c) =>
  view(c).map((m) => `${m.sender.slice(0, 8)}: ${msgText(m)}`);

// ------------------------------------------------------------------ files

/** A timestamped message: what `compose` writes when the client has a
 *  clock.  Kept beside `compose` so the two cannot drift apart — the CLI and
 *  the browser must produce the same line for the same words. */
export const composeAt = (c, text, at) => sayTextAt(clientRoom(c), c.self, c.seq + 1, text, at);

/** Cut and encrypt a file for this room (`Kant.File.encrypt`).  The caller
 *  pins the chunks; this only ever returns ciphertext. */
export const encryptFor = (secret, name, mime, data) => encryptFile(secret, name, mime, data);

/** The manifest line announcing those chunks (`Kant.File.manifest`). */
export const manifestLine = (c, enc, ipfs = []) =>
  printManifest(manifest(clientRoom(c), c.self, c.seq + 1,
    enc.name, enc.mime, enc.size, enc.nonce, enc.cids, ipfs));

/** The files announced in this room, in the order they were announced. */
export function filesOf(c) {
  const out = [];
  for (const l of c.lines) {
    const f = parseManifest(l);
    if (f && !out.some((x) => printManifest(x) === l)) out.push(f);
  }
  return out;
}

/** Fetch and decrypt a dropped file (`Kant.File.decrypt`).  `fetchChunk`
 *  takes a *witness*, not an IPFS CID: no CID can be derived from a witness,
 *  so the caller resolves witness -> CID (see `kant-file-ipfs.mjs`). */
export const takeFile = (secret, f, fetchChunk) => decryptFile(secret, f, fetchChunk);

/** Every chunk of a manifest, for a caller that wants to pin them. */
export const chunksOf = (enc) => enc.chunks;

/** The chunking constant, so a caller sizes its requests the same way. */
export { CHUNK_SIZE, cidOf, manifestWitness };

/** What a URL turns out to carry (`loadUrl`).  A link points at the static
 *  page, and the information the sender added to it — a room to join, or a
 *  whole conversation carried with no relay at all — is after the `'#'`. */
export function loadUrl(u) {
  const text = String(u);
  const i = findInvite(text) ?? pasteInvite(text.trim()) ?? parseInviteUrl(text.trim());
  if (i) return { kind: "invitation", invite: i, room: inviteRoom(i), relay: i.relay };
  const ms = readBagUrl(text.trim()) ?? openBag(text.trim());
  if (ms) return { kind: "bag", messages: ms };
  return { kind: "nothing" };
}

/** This client's conversation as a link anybody can open (`bagUrl`).  The
 *  base is the origin string, as in the Lean `Kant.Uucp.bagUrl`. */
export const clientBagUrl = (cfg, c) => bagUrl(cfg.origin ?? String(cfg), view(c));

/** Take lines that came by hand rather than off the relay: keep every line
 *  that certifies itself, whatever room it names (`Kant.Uucp.Node.absorb`).
 *  Returns how many were new.
 *
 *  Every self-certifying line type is kept, not just chat: a dropped file
 *  (`kzfile`) and a timestamped line (`kzat`) were both being discarded here,
 *  which meant the CLI could post a file and then be unable to see its own
 *  announcement come back.  The room filter stays with `ingest`; here the
 *  point is only "does it certify itself". */
export function absorb(c, lines) {
  let taken = 0;
  for (const l of lines) {
    if (!certifies(l)) continue;
    if (c.lines.includes(l)) continue;
    c.lines.push(l);
    taken += 1;
  }
  return taken;
}

/** Does this line certify itself, whatever it is?  The four room line types
 *  the CLI understands: chat, timestamped chat, a peer announcement, and a
 *  dropped file.  Anything else — a signal, a mangled line — is refused. */
export const certifies = (l) =>
  parseMsg(l) !== null || parseTimed(l) !== null ||
  parseAnnounce(l) !== null || parseManifest(l) !== null;

/** Take a line the way the client takes it: keep it only if it certifies
 *  itself and names this room. */
export function ingest(c, line) {
  const m = parseMsg(line);
  const t = parseTimed(line);
  const a = parseAnnounce(line);
  const f = parseManifest(line);
  // Only chat and files are room-scoped; an announcement names a peer, not a
  // room, and is kept wherever it turns up.
  if ((m || t || f) && (m ?? t ?? f).room !== clientRoom(c)) return false;
  if (!m && !t && !a && !f) return false;
  if (c.lines.includes(line)) return false;
  c.lines.push(line);
  return true;
}

export { roomOf, copyInvite, pasteInvite, parseInviteUrl, inviteRoom, findInvite,
  printMsg, parseMsg, msgText, sayText, accept, receive, transcript, witness,
  hexEncode, hexDecode, utf8, fromUtf8, printAnnounce, parseAnnounce, announce,
  bagUrl, readBagUrl, packBag, openBag,
  printTimed, parseTimed, sayTextAt, receiveTimed, sayQuote, quoteWitness,
  quotedText, printManifest, parseManifest, encryptFile, decryptFile };
