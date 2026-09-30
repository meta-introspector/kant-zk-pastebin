/**
 * What is this code I pasted, and why will these two not connect?
 *
 * A transcription of `RequestProject/Kant/CardDebug.lean`.  The Lean module
 * is the specification; this file is the thing that runs in a browser and on
 * the command line, and `web/carddebug-test.mjs` pins it to the vectors Lean
 * computes.
 *
 * Three codes exist in this system and they are not interchangeable:
 *
 *   kzcard:…    a share card - a page URL, a caption, a picture.  No room.
 *   kzinvite:…  an invitation - a relay and a secret whose digest is a room.
 *   <origin>#<64 hex>   a page link - an address.  No room.
 *
 * Only an invitation can connect two clients.  `classify` says which of the
 * three you are holding; `pair` says what happens when two of them are held
 * up against each other; `explain` says it in a sentence.
 */
import { envelopeDecode, fragment } from "./kantzk.mjs";
import { toCard } from "./kant-site.mjs";
import { toInvite, inviteRoom } from "./kant-net.mjs";

// ------------------------------------------------------ reading the paste

const isBlank = (c) => c === " " || c === "\t" || c === "\r";

/** Drop the spaces at both ends of a line. */
export function trim(s) {
  let i = 0;
  let j = s.length;
  while (i < j && isBlank(s[i])) i++;
  while (j > i && isBlank(s[j - 1])) j--;
  return s.slice(i, j);
}

/**
 * The line a pasted block's meaning is in: the last non-blank one.  A card
 * pasted as text is caption, link, then the machine-readable line; a bare
 * code is that line on its own; a link is the link.
 */
export function codeLine(s) {
  const ls = String(s).split("\n").map(trim).filter((l) => l.length > 0);
  return ls.length ? ls[ls.length - 1] : "";
}

/** A line as an envelope: either it is one, or it is a URL whose fragment is. */
export function envelopeOf(line) {
  const direct = envelopeDecode(line);
  if (direct) return direct;
  return envelopeDecode(fragment(line));
}

const isHex = (c) => (c >= "0" && c <= "9") || (c >= "a" && c <= "f");

/** A content address: exactly 64 lower-case hex characters. */
export const isAddress = (f) => f.length === 64 && [...f].every(isHex);

// ------------------------------------------------------------- classifying

/**
 * An envelope is one of our codes when it is a card or an invitation.
 * Anything else - including the bare 32-byte field a page link's fragment
 * happens to decode to - is not.
 */
export function codeOfEnvelope(e) {
  if (!e) return null;
  const k = toCard(e);
  if (k) return { kind: "card", card: k };
  const i = toInvite(e);
  if (i) return { kind: "invite", invite: i };
  return null;
}

/** `{ kind: "card" | "invite" | "page" | "unknown", … }` */
export function classify(s) {
  const line = codeLine(s);
  const c = codeOfEnvelope(envelopeOf(line));
  if (c) return c;
  const f = fragment(line);
  if (isAddress(f)) return { kind: "page", addr: f };
  return { kind: "unknown" };
}

/** The room a pasted code leads to - only an invitation has one. */
export const roomOf = (c) => (c.kind === "invite" ? inviteRoom(c.invite) : null);

/** The relay a pasted code names - only an invitation has one. */
export const relayOf = (c) => (c.kind === "invite" ? c.invite.relay : null);

/** Two codes are the same code when they carry the same thing. */
export function sameCode(u, v) {
  if (u.kind !== v.kind) return false;
  if (u.kind === "card") return JSON.stringify(u.card) === JSON.stringify(v.card);
  if (u.kind === "invite") return JSON.stringify(u.invite) === JSON.stringify(v.invite);
  if (u.kind === "page") return u.addr === v.addr;
  return true;
}

// --------------------------------------------------------------- pairing

export const PAIRINGS = Object.freeze([
  "connectable",
  "same-code",
  "not-invites",
  "one-not-invite",
  "different-rooms",
  "no-meeting-point",
]);

/** Diagnose two already-classified codes. */
export function pairCodes(u, v) {
  if (u.kind === "invite" && v.kind === "invite") {
    if (inviteRoom(u.invite) !== inviteRoom(v.invite)) return "different-rooms";
    if (u.invite.relay === "" || u.invite.relay !== v.invite.relay) return "no-meeting-point";
    return "connectable";
  }
  if (u.kind === "invite" || v.kind === "invite") return "one-not-invite";
  return sameCode(u, v) ? "same-code" : "not-invites";
}

/** Diagnose two pasted blocks. */
export const pair = (x, y) => pairCodes(classify(x), classify(y));

/** The sentence printed for each outcome. */
export const EXPLAIN = Object.freeze({
  "connectable": "connectable: two invitations, one room, one relay - these two meet",
  "same-code":
    "same-code: both pastes are the same code, so there are not two things here to " +
    "connect; ask the other side for their own invite",
  "not-invites":
    "not-invites: this is a share card or a page link - it names a page, never a room; " +
    "connecting needs a kzinvite code from the share screen",
  "one-not-invite":
    "one-not-invite: only one of these is an invitation; the other names a page, " +
    "so there is nothing for it to join",
  "different-rooms":
    "different-rooms: two invitations, but to two different rooms; both sides must use " +
    "the same invite",
  "no-meeting-point":
    "no-meeting-point: the invitations agree on the room but name no relay, or two " +
    "different ones; set `relay =` in kant.config and re-share",
});

export const explain = (p) => EXPLAIN[p] ?? "";

/** What to do about each outcome. */
export const ADVICE = Object.freeze({
  "connectable": "Open the link on both devices; the diagnostics card should read ok.",
  "same-code":
    "These are one code, not two. A card or a page link is a page, not a meeting: on " +
    "one device use Share -> Invite someone to chat, and let the other device scan or " +
    "paste that kzinvite code.",
  "not-invites":
    "A card or a page link is a page, not a meeting: on one device use Share -> Invite " +
    "someone to chat, and let the other device scan or paste that kzinvite code.",
  "one-not-invite": "Both sides need the same kzinvite code; a page link will not join a room.",
  "different-rooms": "Re-share one invite and have the other side paste exactly that.",
  "no-meeting-point":
    "Set `relay = https://<your relay>` in web/kant.config and re-share, or serve the " +
    "page with `node server/relay.mjs --static web` so the origin is itself the relay.",
});

export const advise = (p) => ADVICE[p] ?? "";

// -------------------------------------------------------- card warnings

const startsWith = (p, s) => s.slice(0, p.length) === p;

/** A picture reference that only resolves next to the page. */
export const relative = (p) =>
  p !== "" && !(startsWith("http://", p) || startsWith("https://", p) || startsWith("data:", p));

/** What is worth saying about a card, given the configured origin. */
export function cardWarnings(origin, k) {
  const out = [];
  if (relative(k.picture)) out.push("relative-picture");
  if (!startsWith(origin, k.url)) out.push("foreign-origin");
  return out;
}

export const WARNING_TEXT = Object.freeze({
  "relative-picture":
    "relative-picture: the card's picture is a relative reference, so away from the " +
    "site itself the logo does not load; use a full https:// URL or a data: URI",
  "foreign-origin":
    "foreign-origin: the card's link is not on the configured origin, so it points at " +
    "a different deployment",
});

// ----------------------------------------------------------- the report

/** A whole report on two pasted blocks, ready to print. */
export function report(x, y, origin = "") {
  const u = classify(x);
  const v = classify(y);
  const p = pairCodes(u, v);
  const warnings = [];
  for (const c of [u, v]) {
    if (c.kind !== "card") continue;
    for (const w of cardWarnings(origin, c.card)) if (!warnings.includes(w)) warnings.push(w);
  }
  return {
    left: describe(u),
    right: describe(v),
    verdict: p,
    explain: explain(p),
    advice: advise(p),
    warnings,
    warningText: warnings.map((w) => WARNING_TEXT[w]),
  };
}

/** A one-object description of a classified code. */
export function describe(c) {
  switch (c.kind) {
    case "card":
      return {
        kind: "card",
        url: c.card.url,
        caption: c.card.caption,
        picture: c.card.picture,
        alt: c.card.alt,
        room: null,
        relay: null,
      };
    case "invite":
      return {
        kind: "invite",
        peer: c.invite.peer,
        room: inviteRoom(c.invite),
        relay: c.invite.relay,
        addrs: c.invite.addrs.map((a) => `${a.transport}:${a.locator}`),
      };
    case "page":
      return { kind: "page", addr: c.addr, room: null, relay: null };
    default:
      return { kind: "unknown", room: null, relay: null };
  }
}

/** The report as lines of text. */
export function renderReport(r) {
  const side = (name, d) => {
    const bits = [`${name}: ${d.kind}`];
    if (d.kind === "card") {
      bits.push(`  url     ${d.url}`);
      bits.push(`  caption ${d.caption}`);
      bits.push(`  picture ${d.picture}`);
      bits.push(`  alt     ${d.alt}`);
      bits.push("  room    (none - a card names a page, not a room)");
    } else if (d.kind === "invite") {
      bits.push(`  peer    ${d.peer}`);
      bits.push(`  room    ${d.room}`);
      bits.push(`  relay   ${d.relay === "" ? "(none)" : d.relay}`);
      if (d.addrs.length) bits.push(`  addrs   ${d.addrs.join(", ")}`);
    } else if (d.kind === "page") {
      bits.push(`  address ${d.addr}`);
      bits.push("  room    (none - a page link names a page, not a room)");
    } else {
      bits.push("  not a code this system issued");
    }
    return bits;
  };
  return [
    ...side("first", r.left),
    ...side("second", r.right),
    "",
    `verdict: ${r.verdict}`,
    r.explain,
    ...(r.advice ? ["", `what to do: ${r.advice}`] : []),
    ...(r.warningText.length ? ["", ...r.warningText.map((w) => `warning: ${w}`)] : []),
  ];
}

/** What a single pasted code can and cannot do, on its own. */
export function single(c) {
  switch (c.kind) {
    case "card":
      return "This is a share card: a page, a caption and a picture. It carries no room " +
        "and no relay, so nothing about it can connect to anything. To connect, share an " +
        "invitation (kzinvite) instead.";
    case "invite":
      return c.invite.relay === ""
        ? "This is an invitation, but it names no relay, so two devices have nowhere to " +
          "meet. Set `relay =` in kant.config and re-share."
        : "This is an invitation: give this same code to the other device, and both land " +
          "in room " + inviteRoom(c.invite).slice(0, 8) + "\u2026 via " + c.invite.relay + ".";
    case "page":
      return "This is a page link: the address of a paste. It carries no room and no " +
        "relay, so it cannot connect anything; it only opens the page.";
    default:
      return "This is not a code this system issued. Paste the whole card, the kzinvite " +
        "line, or the page link.";
  }
}
