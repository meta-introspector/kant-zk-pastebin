// The guided flow: joining however a link arrives, the screens and the
// camera switch, the dressed invite code, and copying a post as plain text.
//
// A transcription of four Lean modules, which are the specification:
//
//   RequestProject/Kant/Join.lean       -> findInvite and friends
//   RequestProject/Kant/Onboarding.lean -> Screen / Event / State / step
//   RequestProject/Kant/InviteCard.lean -> inviteUrl, Dress, inviteCard
//   RequestProject/Kant/PlainText.lean  -> copyPlain, copyPlainWithMeta
//
// `web/flow-test.mjs` checks this file against the statements proved there.

import { asciiChars, fromUtf8, witness } from "./kantzk.mjs";
import { copyInvite, inviteRoom, pasteInvite } from "./kant-net.mjs";
import { cardLine, pasteUrl, readCard, renderCard } from "./kant-site.mjs";

// ============================================================ Kant.Join
//
// Somebody pastes a link into the join box.  It arrives wrapped in a
// sentence, with a full stop after it, inside angle brackets, with a
// trailing newline, or as the bare code.  All of those must work.

const HEX = "0123456789abcdef";

/** The field separator of an envelope. */
export const SEP = ":";

/** A character a code can contain: a lowercase hex digit or `':'`. */
export const isCodeChar = (c) => HEX.includes(c) || c === SEP;

/** A character that ends a word: any whitespace a chat window may add. */
export const isBlank = (c) => c === " " || c === "\n" || c === "\t" || c === "\r";

/** Every whitespace character rewritten as a space. */
export const deblank = (s) =>
  Array.from(String(s)).map((c) => (isBlank(c) ? " " : c)).join("");

/** The words of a piece of text. */
export const words = (s) => deblank(s).split(" ").filter((w) => w.length > 0);

/** Everything after the last `'#'`, or the whole word if there is none. */
export function afterLastHash(w) {
  const at = w.lastIndexOf("#");
  return at < 0 ? w : w.slice(at + 1);
}

/** Trim from both ends anything that cannot occur inside a code. */
export function codePart(w) {
  const s = afterLastHash(w);
  let i = 0;
  while (i < s.length && !isCodeChar(s[i])) i += 1;
  let j = i;
  while (j < s.length && isCodeChar(s[j])) j += 1;
  return s.slice(i, j);
}

/** Read one word as an invitation, `null` if it is not one. */
export const wordInvite = (w) => pasteInvite(codePart(w));

/**
 * **Find the invitation in whatever was pasted or scanned.**  Mirrors
 * `Kant.Join.findInvite`: try every word, keep the first that reads.
 */
export function findInvite(text) {
  for (const w of words(text)) {
    const i = wordInvite(w);
    if (i) return i;
  }
  return null;
}

/** The room a pasted link leads to, `null` if there is no link in it. */
export function findRoom(text) {
  const i = findInvite(text);
  return i ? inviteRoom(i) : null;
}

// ======================================================= Kant.InviteCard
//
// The code did not show the link — only the bare `kzinvite:…` payload.
// An invite code carries the whole page URL, and the card around it
// carries a picture and a line of text.

/** The dressing used when the configuration says nothing. */
export const DEFAULT_DRESS = Object.freeze({
  caption: "join my kant room",
  icon: "./kant-logo.svg",
  alt: "the Kant pastebin logo",
});

/** The dressing named by the deployment's configuration file. */
export const dressOfConfig = (cfg, caption = cfg.caption) => ({
  caption,
  icon: cfg.picture,
  alt: cfg.alt,
});

/**
 * **What an invite code carries: the whole page URL.**  The configured
 * origin, a `#`, and the invitation.  `Kant.InviteCard.inviteUrl`.
 */
export const inviteUrl = (cfg, i) => `${cfg.origin}#${copyInvite(i)}`;

/** **The invite card**: the whole link, a custom icon, a custom line. */
export const inviteCard = (cfg, dress, i) => ({
  url: inviteUrl(cfg, i),
  caption: dress.caption,
  picture: dress.icon,
  alt: dress.alt,
});

/** The card as one SVG document: code, icon in the middle, caption, link. */
export const inviteCardSvg = (cfg, dress, i, opts = {}) =>
  renderCard(inviteCard(cfg, dress, i), opts);

/** Read the invite card back out of an exported picture. */
export const readInviteCard = (doc) => readCard(doc);

/** The card shared as plain text: caption, whole link, machine line. */
export const inviteChatText = (cfg, dress, i) => {
  const k = inviteCard(cfg, dress, i);
  return `${k.caption}\n${k.url}\n${cardLine(k)}`;
};

// ======================================================= Kant.Onboarding

/** The screens of the client. */
export const Screen = Object.freeze({
  welcome: "welcome",
  share: "share",
  join: "join",
  scan: "scan",
  chat: "chat",
  more: "more",
});

export const SCREENS = Object.freeze(Object.values(Screen));

/** The tasks of the guided first run. */
export const Task = Object.freeze({
  getIn: "getIn",
  shareIt: "shareIt",
  sayHello: "sayHello",
});

/** A first visit. */
export const start = () => ({
  screen: Screen.welcome,
  camera: false,
  inRoom: false,
  hushed: false,
  demo: true,
  progress: { gotIn: false, sharedIt: false, saidHello: false },
});

const withProgress = (s, patch) => ({ ...s, progress: { ...s.progress, ...patch } });

/**
 * One event.  A faithful transcription of `Kant.Onboarding.step`; in
 * particular the camera is switched off by `back`, `leave`, `stopCamera`,
 * a successful join, and by tapping through to any screen but `scan`.
 */
export function step(s, ev) {
  const e = typeof ev === "string" ? { type: ev } : ev;
  switch (e.type) {
    case "goto":
      return { ...s, screen: e.screen, camera: s.camera && e.screen === Screen.scan };
    case "back":
      return { ...s, screen: Screen.welcome, camera: false };
    case "createRoom":
      return withProgress(
        { ...s, screen: Screen.share, camera: false, inRoom: true },
        { gotIn: true },
      );
    case "copyLink":
      return withProgress(s, { sharedIt: s.progress.sharedIt || s.inRoom });
    case "startCamera":
      return { ...s, screen: Screen.scan, camera: true };
    case "stopCamera":
      return { ...s, camera: false };
    case "joinText":
      return findInvite(e.text)
        ? withProgress(
            { ...s, screen: Screen.chat, camera: false, inRoom: true },
            { gotIn: true },
          )
        : s;
    case "say":
      return withProgress(s, { saidHello: s.progress.saidHello || s.inRoom });
    case "leave":
      return { ...s, screen: Screen.welcome, camera: false, inRoom: false };
    case "exitDemo":
      // The guided walkthrough is a demo: leaving it means the guide stops
      // talking, the progress dots go, and the app is just the room UI.
      return {
        ...s,
        demo: false,
        progress: { gotIn: true, sharedIt: true, saidHello: true },
      };
    case "restartDemo":
      return { ...s, demo: true, progress: { gotIn: false, sharedIt: false, saidHello: false } };
    case "hush":
      return { ...s, hushed: true };
    case "unhush":
      return { ...s, hushed: false };
    default:
      return s;
  }
}

/** A run of events. */
export const run = (s, evs) => evs.reduce(step, s);

/** The next thing the newcomer is asked to do, `null` when all is done. */
export function nextTask(p) {
  if (!p.gotIn) return Task.getIn;
  if (!p.sharedIt) return Task.shareIt;
  if (!p.saidHello) return Task.sayHello;
  return null;
}

/** The screen a task is done on. */
export const screenFor = (t) =>
  ({ getIn: Screen.welcome, shareIt: Screen.share, sayHello: Screen.chat })[t];

/** What the guide says out loud for each task. */
export const prompt = (t) =>
  ({
    getIn:
      "Step one of three. Tap Start a room to make a new room, or tap Join and paste the link somebody sent you.",
    shareIt:
      "Step two of three. This is your link and your code. Copy the link into any chat, or let the other person point their camera at the code.",
    sayHello:
      "Step three of three. Type a line and send it. Everyone who followed your link sees it.",
  })[t];

/** What the guide says when there is nothing left to do. */
export const doneWords =
  "That is everything. You have a room, you have shared it, and you have said something in it.";

/** The line the guide would say in this state. */
export function promptFor(s) {
  if (!s.demo) return "";
  const t = nextTask(s.progress);
  return t === null ? doneWords : prompt(t);
}

/** What is actually spoken: nothing at all when the voice is hushed. */
export const speech = (s) => (s.hushed ? "" : promptFor(s));

/** The one piece of text the share screen offers: the whole page link. */
export const shareText = (cfg, i) => inviteUrl(cfg, i);

/** What the one code on that screen carries — exactly the same text. */
export const qrText = (cfg, dress, i) => inviteCard(cfg, dress, i).url;

/** A short label for each screen, for the title bar. */
export const screenTitle = (t) =>
  ({
    welcome: "Kant",
    share: "Share this room",
    join: "Join a room",
    scan: "Scan a code",
    chat: "Room",
    more: "More",
  })[t];

// ========================================================= Kant.PlainText

/** The signature line that separates the text from its details. */
export const SIG_MARK = "-- ";

/**
 * **Copying the text gives the text**, not the envelope.
 *
 * The Lean specification reads the bytes as ASCII (`asciiChars`); here they
 * are decoded as UTF-8, which agrees with it exactly on the ASCII content the
 * proofs are about and is what a reader wants for anything else.
 */
export const plainText = (p) =>
  typeof p.content === "string" ? p.content : fromUtf8(p.content);

/** The same, read strictly as the Lean specification reads it. */
export const plainTextAscii = (p) =>
  typeof p.content === "string" ? p.content : asciiChars(p.content);

export const copyPlain = (p) => plainText(p);

/** One `key: value` line of the footer. */
export const entry = (key, value) => `${key}: ${value}\n`;

/** The footer: the details, one per line. */
export const metaText = (m) =>
  entry("title", m.title) + entry("link", m.link) + entry("address", m.address) +
  entry("posted", m.posted);

/** Read one `key: value` line. */
export function parseEntry(line) {
  const at = line.indexOf(": ");
  if (at < 0) return null;
  return [line.slice(0, at), line.slice(at + 2)];
}

const META_KEYS = ["title", "link", "address", "posted"];

/** Read the footer back, `null` if a detail is missing. */
export function parseMeta(text) {
  const entries = String(text).split("\n").map(parseEntry).filter((e) => e !== null);
  const m = {};
  for (const k of META_KEYS) {
    const hit = entries.find(([key]) => key === k);
    if (!hit) return null;
    m[k] = hit[1];
  }
  return m;
}

/** The text with the footer under it. */
export const render = (body, m) => `${body}\n${SIG_MARK}\n${metaText(m)}`;

/** The details of a post in a given deployment. */
export const metaFor = (cfg, p) => ({
  title: p.title,
  link: pasteUrl(cfg, p),
  address: p.witness ?? witness(p.content),
  posted: p.timestamp,
});

/** **Copying the text with its details.** */
export const copyPlainWithMeta = (cfg, p) => render(plainText(p), metaFor(cfg, p));

/** The text part of something copied this way. */
export const bodyOf = (s) => {
  const ls = String(s).split("\n");
  const at = ls.indexOf(SIG_MARK);
  return (at < 0 ? ls : ls.slice(0, at)).join("\n");
};

/** The footer part, if there is one. */
export const metaTextOf = (s) => {
  const ls = String(s).split("\n");
  const at = ls.indexOf(SIG_MARK);
  return at < 0 ? "" : ls.slice(at + 1).join("\n");
};

/** The details, if the text carries any. */
export const metaOf = (s) => parseMeta(metaTextOf(s));

/** Copy a post either way, depending on whether the details are wanted. */
export const copyPost = (cfg, p, withMeta = false) =>
  withMeta ? copyPlainWithMeta(cfg, p) : copyPlain(p);
