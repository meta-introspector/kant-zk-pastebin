// kant-sharelog.mjs — share the run, post it to the store, and run the
// whole thing by hand in a chat with no server anywhere.
//
// An unverified transcription of `RequestProject/Kant/ShareLog.lean` and
// `RequestProject/Kant/Handoff.lean`.  Every pure function here matches a
// Lean definition of the same name, and `web/sharelog-test.mjs` pins them
// against the same vectors the Lean file checks with `#guard`.
//
// Three ways out of the app, none of which needs a server:
//
//   * `logText`      — the run as text, for a chat window or a bug report;
//   * `postLog`      — the run as a post in the content-addressed store,
//                      so it gets a witness, a page and a link;
//   * `chatParts`    — the run as numbered chat messages, each inside a
//                      tweet, collected on the other side in any order.
//
// And one procedure: `script` / `logScript` are the numbered steps a
// person follows to carry a conversation, or a run, by hand.

import {
  asciiBytes, asciiChars, makePaste, copyText, pasteText, witness,
  copyAll, pasteAll, Store,
} from "./kantzk.mjs";
import { ref, renderReport, parseReport, findReport, reportText } from "./kant-diag.mjs";
import { thread, readThread, threadLength, CARRIER_CAPACITY } from "./kant-uucp.mjs";

// ------------------------------------------------------- the shared run

/** What the "Share the log" button hands over (`Kant.ShareLog.shareReport`):
 *  the verdict, the room's eight-character handle — never the room — the
 *  relay in use, and every event that quotes none of the secrets held. */
export function shareReport({ log, verdict = "ok", room = "", relay = "", secrets = [] }) {
  const held = room ? [room, ...secrets] : secrets;
  return {
    verdict,
    room: room ? ref(room) : "",
    relay,
    events: typeof log?.share === "function" ? log.share(held) : (log?.events ?? []),
    dropped: log?.dropped ?? 0,
  };
}

/** The machine-readable text of a shared run (`logText`). */
export const logText = (r) => renderReport(r);

/** The same run with a human-readable header on top; the block underneath
 *  is exactly `logText`, so it reads back. */
export const shareText = (r, opts) => reportText(r, opts);

/** Read a run back, however much chat window is wrapped around it. */
export const readShared = (text) => findReport(text) ?? parseReport(text);

// --------------------------------------------- the run as a post

/** The title a posted run carries (`Kant.ShareLog.logTitle`). */
export const LOG_TITLE = "the run so far";

/** The run as a post (`logPaste`). */
export const logPaste = (r, { id = "", timestamp = "" } = {}) =>
  makePaste({
    id: id || `run_${timestamp || "0"}`,
    title: LOG_TITLE,
    content: asciiBytes(logText(r)),
    timestamp,
  });

/** Post the run to the store (`postLog`).  Content-addressed, so posting
 *  the same run twice is a no-op and two people who share the same run
 *  post the same block. */
export function postLog(store, r, opts = {}) {
  const p = logPaste(r, opts);
  const already = store.has(p.witness);
  store.put(p);
  return { paste: p, witness: p.witness, already };
}

/** Read a posted run back out of the block that was stored. */
export const readPostedLog = (p) => (p ? readShared(asciiChars(p.content)) : null);

/** The link that resolves a posted run on a given origin. */
export const logLink = (base, p) => `${String(base).split("#")[0]}#${p.witness}`;

// ------------------------------------- the run as messages in a chat

/** The run cut into numbered chat messages (`chatParts`).  At 100 payload
 *  bytes every message fits in a tweet (`chatParts_fit_tweet`). */
export const chatParts = (limit, r) => thread(limit, logText(r));

/** How many messages the run needs. */
export const chatPartCount = (limit, r) => threadLength(limit, logText(r));

/** Read a run out of the messages that were pasted back, in any order
 *  (`readChatParts`). */
export function readChatParts(parts) {
  const joined = readThread(parts.map((p) => String(p).trim()).filter(Boolean));
  if (joined === null) return null;
  return parseReport(joined);
}

/** Payload size for a carrier, keeping every message inside its cap. */
export const partLimitFor = (carrier = "tweet") =>
  Math.max(16, Math.floor(((CARRIER_CAPACITY[carrier] ?? 280) - 40) / 2.4));

// ----------------------------------------------- the manual procedure

/** The two moves a person can be asked to make (`Kant.Handoff.Move`).
 *  Neither needs a server, which is the whole point. */
export const copyOut = (code) => ({ kind: "copyOut", code });
export const PASTE_IN = { kind: "pasteIn" };

/** `Move.needsServer` — always false. */
export const needsServer = () => false;

/** `Move.payload`. */
export const payload = (m) => (m.kind === "copyOut" ? m.code : null);

/** `Serverless`: no step of any script asks for anything running anywhere. */
export const serverless = (steps) => steps.every((s) => !needsServer(s.move));

/** The codes a script asks you to send (`codes`). */
export const codes = (steps) => steps.map((s) => payload(s.move)).filter((c) => c !== null);

export const SAY_COPY = "copy this and send it in the chat";
export const SAY_PASTE = "paste what they sent you into the box";
export const SAY_PART = "send this message, then the next one";

/** The four steps that connect two people through any chat
 *  (`Kant.Handoff.script`).  `mine` is your bag; `theirsAfter` is the bag
 *  they will hand back once they have pasted yours. */
export const script = ({ me = "you", them = "them", mine, theirsAfter }) => [
  { number: 1, actor: me, instruction: SAY_COPY, move: copyOut(mine) },
  { number: 2, actor: them, instruction: SAY_PASTE, move: PASTE_IN },
  { number: 3, actor: them, instruction: SAY_COPY, move: copyOut(theirsAfter ?? "") },
  { number: 4, actor: me, instruction: SAY_PASTE, move: PASTE_IN },
];

/** The steps that hand the run over as numbered chat messages
 *  (`Kant.Handoff.logScript`). */
export const logScript = (limit, who, r) =>
  chatParts(limit, r).map((code, i) => ({
    number: i + 1,
    actor: who,
    instruction: SAY_PART,
    move: copyOut(code),
  }));

/** One line of instructions, as a person reads it. */
export const stepLine = (s) =>
  `${s.number}. ${s.actor}: ${s.instruction}` +
  (s.move.kind === "copyOut" ? ` (${s.move.code.length} characters)` : "");

// --------------------------------- carrying a post by hand

/** Paste a copied post into your own store (`Kant.Handoff.carry`).
 *  Anything that does not read back, or whose content and witness
 *  disagree, leaves the store alone. */
export function carry(store, text) {
  const p = pasteText(String(text).trim());
  if (!p) return { accepted: false, witness: null };
  store.put(p);
  return { accepted: true, witness: p.witness, paste: p };
}

/** The clipboard text of a post, for sending it through a chat. */
export const carryText = (p) => copyText(p);

/** Two stores that both answer an address answer with the same block:
 *  agreement is by content, not by trust (`carry_agrees`). */
export const agrees = (p, q) => !!p && !!q && p.witness === q.witness &&
  p.witness === witness(p.content);

// ------------------------------------------- the store, kept on this device
//
// There is no server, so "the store" is this browser's own copy: a list of
// blocks written down as one bundle (`Kant.Clipboard.copyAll`) and read back
// with `pasteAll`.  Every page of the app uses the same key, so a run posted
// in one is a block the other holds.

export const STORE_KEY = "kant-store";

/** Read this device's store. */
export function loadStore(storage = globalThis.localStorage, key = STORE_KEY) {
  const st = new Store();
  try {
    const text = storage?.getItem(key);
    if (text) for (const p of pasteAll(text) ?? []) st.put(p);
  } catch { /* a forbidden or corrupt store must not break the page */ }
  return st;
}

/** Write it back. */
export function saveStore(st, storage = globalThis.localStorage, key = STORE_KEY) {
  try { storage?.setItem(key, copyAll(st.entries)); }
  catch { /* a full store must not break the page */ }
  return st;
}
