// The site configuration, the full page URL, and the share card.
//
// A transcription of `RequestProject/Kant/SiteCard.lean`; the Lean module is
// the specification and this file follows it function for function.  The
// conformance vectors in `web/site-test.mjs` are computed by Lean.
//
// The point of the module: every code, link and card carries the *whole*
// URL of the page,
//
//   https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605
//
// with the part before the `#` coming from `kant.config` rather than from
// the program.

import {
  asciiBytes,
  asciiChars,
  envelopeDecode,
  envelopeEncode,
  escapeHtml,
  fragment,
  witness,
} from "./kantzk.mjs";
import { qrEncode, qrSvg } from "./kant-qr.mjs";

// ---------------------------------------------------------------- config

/** The configuration used when no `kant.config` can be read. */
export const DEFAULT_CONFIG = Object.freeze({
  origin: "https://kant.cicada71.net/",
  caption: "kant-zk-pastebin",
  picture: "./kant-logo.svg",
  alt: "the Kant pastebin logo",
});

const KEYS = ["origin", "caption", "picture", "alt"];

/** Write the configuration file (`renderConfig`). */
export const renderConfig = (cfg) =>
  KEYS.map((k) => `${k} = ${cfg[k] ?? ""}\n`).join("");

/** Read one `key = value` line; `null` for a comment or a blank line. */
export function parseEntry(line) {
  const at = line.indexOf("=");
  if (at < 0) return null;
  return [line.slice(0, at).replace(/ +$/, ""), line.slice(at + 1).replace(/^ +/, "")];
}

/** Read the configuration file (`parseConfig`).  `null` if a key is missing. */
export function parseConfig(text) {
  const entries = String(text).split("\n").map(parseEntry).filter((e) => e !== null);
  const cfg = {};
  for (const key of KEYS) {
    const hit = entries.find(([k]) => k === key);
    if (!hit) return null;
    cfg[key] = hit[1];
  }
  return cfg;
}

/** Is this configuration one the proofs apply to? */
export function configWf(cfg) {
  if (!cfg) return false;
  if (cfg.origin.includes("#")) return false;
  for (const key of KEYS) {
    const v = cfg[key];
    if (typeof v !== "string") return false;
    if (v.includes("\n")) return false;
    if (v.startsWith(" ")) return false;
  }
  // eslint-disable-next-line no-control-regex
  return /^[\x00-\x7f]*$/.test(cfg.origin);
}

/**
 * Read `kant.config` next to the page, falling back to the built-in
 * configuration when there is none (a `file://` copy, an offline visit).
 * Returns `{ config, source }`.
 */
export async function loadConfig(url = "./kant.config", fetchImpl = globalThis.fetch) {
  try {
    const res = await fetchImpl(url, { cache: "no-cache" });
    if (!res || !res.ok) return { config: { ...DEFAULT_CONFIG }, source: "built-in" };
    const parsed = parseConfig(await res.text());
    if (!parsed || !configWf(parsed)) return { config: { ...DEFAULT_CONFIG }, source: "built-in" };
    return { config: parsed, source: url };
  } catch {
    return { config: { ...DEFAULT_CONFIG }, source: "built-in" };
  }
}

/**
 * The relay named by the configuration file, `""` when there is none.
 *
 * `relay` is deliberately *not* one of the four keys the Lean specification
 * fixes: a deployment without a relay is still a well-formed one, it just
 * cannot introduce two different devices to each other.
 */
export function parseRelay(text) {
  const entries = String(text).split("\n").map(parseEntry).filter((e) => e !== null);
  const hit = entries.find(([k]) => k === "relay");
  return hit ? hit[1].trim() : "";
}

/** Read the relay out of `kant.config`, `""` when there is none. */
export async function loadRelay(url = "./kant.config", fetchImpl = globalThis.fetch) {
  try {
    const res = await fetchImpl(url, { cache: "no-cache" });
    if (!res || !res.ok) return "";
    return parseRelay(await res.text());
  } catch {
    return "";
  }
}

// ------------------------------------------------------------------ URLs

/** `origin#address` — the whole address of a page. */
export const addressUrl = (cfg, addr) => `${cfg.origin}#${addr}`;

/** The address a URL points at. */
export const urlAddress = (u) => fragment(u);

/** The page URL of a post. */
export const pasteUrl = (cfg, p) => addressUrl(cfg, witness(p.content));

/** A whole envelope carried in the fragment of the configured site URL. */
export const shareUrl = (cfg, e) => addressUrl(cfg, envelopeEncode(e));

/** What a QR code carries: the entire URL. */
export const qrPayload = (cfg, e) => shareUrl(cfg, e);

/** Read the payload back out of a scanned URL. */
export const parseQrPayload = (u) => envelopeDecode(fragment(u));

// ------------------------------------------------------------------ card

/** The share card of a post: its page URL, plus the configured text and picture. */
export const cardOf = (cfg, p) => ({
  url: pasteUrl(cfg, p),
  caption: cfg.caption,
  picture: cfg.picture,
  alt: cfg.alt,
});

/** A card for any URL, with the configuration supplying the dressing. */
export const cardFor = (cfg, url, caption = cfg.caption, picture = cfg.picture, alt = cfg.alt) =>
  ({ url, caption, picture, alt });

export const TAG_CARD = asciiBytes("kzcard");

export const ofCard = (k) => ({
  tag: TAG_CARD,
  fields: [asciiBytes(k.url), asciiBytes(k.caption), asciiBytes(k.picture), asciiBytes(k.alt)],
});

export function toCard(e) {
  if (!e) return null;
  if (asciiChars(e.tag) !== "kzcard") return null;
  if (e.fields.length !== 4) return null;
  const [u, c, p, a] = e.fields.map(asciiChars);
  return { url: u, caption: c, picture: p, alt: a };
}

/** A card as one line of text. */
export const cardLine = (k) => envelopeEncode(ofCard(k));

/** Read a card out of a line of text. */
export const readCardLine = (s) => toCard(envelopeDecode(s));

// ------------------------------------------------- rendering the picture

export const CARD_MARKER = "<!--kzcard:";

/** The side, in modules, of the picture placed in the middle of the code. */
export const logoSide = (n) => Math.floor(n / 5);

/**
 * The card as one SVG document: a comment carrying the card itself, the code
 * as a clickable link, the picture in the middle, then the caption and the
 * URL as text.  Every interpolated string is escaped.
 */
export function cardSvg(k, qr, { scale = 8, border = 4, dark = "#000", light = "#fff" } = {}) {
  const n = qr.size;
  const side = (n + 2 * border) * scale;
  const height = side + 3 * scale;
  const logo = logoSide(n) * scale;
  const logoAt = Math.floor((side - logo) / 2);
  const rects = [];
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (qr.modules[r][c] !== 1) continue;
      rects.push(
        `<rect x="${(c + border) * scale}" y="${(r + border) * scale}" ` +
          `width="${scale}" height="${scale}"/>`,
      );
    }
  }
  return (
    `${CARD_MARKER}${cardLine(k)}\n-->\n` +
    `<svg xmlns="http://www.w3.org/2000/svg" width="${side}" height="${height}" ` +
    `viewBox="0 0 ${side} ${height}" shape-rendering="crispEdges" role="img" ` +
    `aria-label="${escapeHtml(k.alt)}">\n` +
    `<title>${escapeHtml(k.caption)}</title>\n` +
    `<rect width="100%" height="100%" fill="${light}"/>\n` +
    `<a href="${escapeHtml(k.url)}"><g fill="${dark}">${rects.join("")}</g></a>\n` +
    (k.picture
      ? `<image href="${escapeHtml(k.picture)}" x="${logoAt}" y="${logoAt}" ` +
        `width="${logo}" height="${logo}"/>\n`
      : "") +
    `<text x="${scale}" y="${side + scale}" font-family="monospace" ` +
    `font-size="${2 * scale}" fill="${dark}">${escapeHtml(k.caption)}</text>\n` +
    `<text x="${scale}" y="${side + 3 * scale}" font-family="monospace" ` +
    `font-size="${scale}" fill="#333">${escapeHtml(k.url)}</text>\n` +
    `</svg>\n`
  );
}

/** Encode the card's URL as a code and render the whole card. */
export const renderCard = (k, opts = {}) => cardSvg(k, qrEncode(k.url), opts);

/** Read the card out of a card picture. */
export function readCard(doc) {
  const text = String(doc);
  if (!text.startsWith(CARD_MARKER)) return null;
  const rest = text.slice(CARD_MARKER.length);
  const end = rest.indexOf("\n");
  return readCardLine(end < 0 ? rest : rest.slice(0, end));
}

/** The bare code for a URL, without caption or picture. */
export const urlQrSvg = (url, opts = {}) => qrSvg(qrEncode(url), opts);

/** Render a card as a PNG blob. */
export async function cardPng(k, qr, { scale = 8, border = 4, dark = "#000", light = "#fff" } = {}) {
  const svgStr = cardSvg(k, qr, { scale, border, dark, light });
  const blob = new Blob([svgStr], { type: "image/svg+xml;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = img.width;
      canvas.height = img.height;
      const ctx = canvas.getContext("2d");
      ctx.drawImage(img, 0, 0);
      URL.revokeObjectURL(url);
      canvas.toBlob(resolve, "image/png");
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("failed to load card SVG for PNG export"));
    };
    img.src = url;
  });
}

// ----------------------------------------------------------------- chat

/** A card for a chat that carries nothing but text. */
export const chatText = (k) => `${k.caption}\n${k.url}\n${cardLine(k)}`;

/** Read the card out of such a message: it is the last line. */
export function readChatText(s) {
  const lines = String(s).split("\n");
  return readCardLine(lines[lines.length - 1]);
}

/** The body of a chat message carrying a card. */
export const chatBody = (k) => asciiBytes(cardLine(k));

/** Read a card out of a chat message body, `null` if the message is not one. */
export const readChatBody = (body) => readCardLine(asciiChars(body));

/**
 * Everything needed to share a card by hand: the link, the text a human
 * reads, and the machine-readable line.  Suitable for `navigator.share`.
 */
export const shareBundle = (k) => ({
  title: k.caption,
  text: `${k.caption}\n${k.url}`,
  url: k.url,
  card: cardLine(k),
  chat: chatText(k),
});
