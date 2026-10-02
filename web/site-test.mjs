// Conformance checks for web/kant-site.mjs against the vectors computed by
// Lean in RequestProject/Kant/Demo.lean (the `SiteCard` section).
//
//   node web/site-test.mjs

import * as S from "./kant-site.mjs";
import * as K from "./kantzk.mjs";
import { qrEncode } from "./kant-qr.mjs";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

let checks = 0;
const fail = [];
function ok(name, cond) {
  checks += 1;
  if (!cond) fail.push(name);
}
function eq(name, got, want) {
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);
}

const here = dirname(fileURLToPath(import.meta.url));

// The configuration this checkout ships, and the Lean golden vectors.
const CONFIG = {
  origin: "https://kant.cicada71.net/",
  caption: "kant-zk-pastebin",
  picture: "./kant-logo.svg",
  alt: "the Kant pastebin logo",
};
const CONFIG_TEXT =
  "origin = https://kant.cicada71.net/\n" +
  "caption = kant-zk-pastebin\n" +
  "picture = ./kant-logo.svg\n" +
  "alt = the Kant pastebin logo\n";
const SAMPLE = K.makePaste({
  id: "paste_20260902_000000",
  title: "Kant <ZK> Pastebin",
  content: K.utf8("The Critique of Pure Paste"),
  timestamp: "20260902_000000",
});
const SAMPLE_URL =
  "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605";
const CARD_LINE =
  "6b7a63617264:68747470733a2f2f6b616e742e63696361646137312e6e65742f23666638313066323931" +
  "66313837623830386130313833663833633034363638373435373365663563346336643764396564343330" +
  "633666376437313066363035:6b616e742d7a6b2d706173746562696e:2e2f6b616e742d6c6f676f2e737667" +
  ":746865204b616e7420706173746562696e206c6f676f";
const CARD_WITNESS = "fe2f60c16f4c13313602b158fd9e158a01f33032d2041c97fa1d8f5f8e9bc970";

// --- the configuration file ------------------------------------------------

eq("renderConfig", S.renderConfig(CONFIG), CONFIG_TEXT);
ok("parseConfig round trip", JSON.stringify(S.parseConfig(CONFIG_TEXT)) === JSON.stringify(CONFIG));
ok("configWf", S.configWf(CONFIG));
ok("comments ignored", JSON.stringify(S.parseConfig("# a comment\n\n" + CONFIG_TEXT)) ===
  JSON.stringify(CONFIG));
ok("missing key rejected", S.parseConfig("origin = https://x/\n") === null);
ok("an origin with a fragment is refused", !S.configWf({ ...CONFIG, origin: "https://x/#y" }));

// The file this checkout actually ships parses, and is the one above.
const shipped = S.parseConfig(readFileSync(join(here, "kant.config"), "utf8"));
ok("web/kant.config parses", shipped !== null && S.configWf(shipped));
eq("web/kant.config origin", shipped.origin, CONFIG.origin);
eq("web/kant.config caption", shipped.caption, CONFIG.caption);
eq("web/kant.config picture", shipped.picture, CONFIG.picture);
eq("web/kant.config alt", shipped.alt, CONFIG.alt);

// --- the whole URL ---------------------------------------------------------

eq("pasteUrl matches Lean", S.pasteUrl(CONFIG, SAMPLE), SAMPLE_URL);
eq("pasteUrl length", S.pasteUrl(CONFIG, SAMPLE).length, 91);
eq("urlAddress", S.urlAddress(SAMPLE_URL), K.witness(SAMPLE.content));
ok("the code carries the whole URL", S.qrPayload(CONFIG, K.ofPaste(SAMPLE)).startsWith(CONFIG.origin));
ok(
  "the payload survives the URL",
  JSON.stringify(S.parseQrPayload(S.qrPayload(CONFIG, K.ofPaste(SAMPLE)))) ===
    JSON.stringify(K.ofPaste(SAMPLE)),
);
ok("a page URL fits in one code", S.pasteUrl(CONFIG, SAMPLE).length <= K.CHANNEL_CAPACITY.qr);

// --- the card --------------------------------------------------------------

const card = S.cardOf(CONFIG, SAMPLE);
eq("card url", card.url, SAMPLE_URL);
eq("cardLine matches Lean", S.cardLine(card), CARD_LINE);
eq("cardLine length", S.cardLine(card).length, 304);
eq("cardLine witness matches Lean", K.witness(K.asciiBytes(S.cardLine(card))), CARD_WITNESS);
ok("cardLine round trip", JSON.stringify(S.readCardLine(S.cardLine(card))) === JSON.stringify(card));
ok("a doctored card line is refused", S.readCardLine("not a card") === null);
ok("a chat line of the wrong kind is refused", S.readCardLine(K.copyText(SAMPLE)) === null);

const qr = qrEncode(card.url);
const svg = S.cardSvg(card, qr, { scale: 8, border: 4 });
ok("the picture carries the card", JSON.stringify(S.readCard(svg)) === JSON.stringify(card));
ok("the caption is printed", svg.includes(K.escapeHtml(card.caption)));
ok("the picture is placed", svg.includes(K.escapeHtml(card.picture)));
ok("the whole URL is printed", svg.includes(K.escapeHtml(card.url)));
ok("the code links to the page", svg.includes(`<a href="${K.escapeHtml(card.url)}">`));
eq("logo side (fifth of the code)", S.logoSide(qr.size), Math.floor(qr.size / 5));
ok("the logo covers at most a 25th", 25 * S.logoSide(qr.size) ** 2 <= qr.size ** 2);
eq("renderCard agrees with cardSvg", S.renderCard(card, { scale: 8, border: 4 }), svg);

// Injection: a caption full of markup cannot break the document.
const nasty = { ...card, caption: "</svg><script>alert(1)</script>" };
const nastySvg = S.cardSvg(nasty, qr);
ok("markup is escaped", !nastySvg.includes("<script>"));
ok("a nasty caption still round trips",
  JSON.stringify(S.readCard(nastySvg)) === JSON.stringify(nasty));

// A scanner reading the code gets a URL a browser can open.
eq("the code encodes the whole URL", card.url, SAMPLE_URL);

// --- sharing in chat -------------------------------------------------------

const text = S.chatText(card);
eq("chat text has three lines", text.split("\n").length, 3);
eq("chat text starts with the caption", text.split("\n")[0], card.caption);
eq("chat text shows the URL", text.split("\n")[1], SAMPLE_URL);
ok("chat text round trip", JSON.stringify(S.readChatText(text)) === JSON.stringify(card));
ok(
  "chat body round trip",
  JSON.stringify(S.readChatBody(S.chatBody(card))) === JSON.stringify(card),
);
ok("a chat line that is not a card is ignored", S.readChatText("hello\nthere") === null);

const bundle = S.shareBundle(card);
eq("share bundle url", bundle.url, SAMPLE_URL);
eq("share bundle title", bundle.title, card.caption);
ok("share bundle carries the card", S.readCardLine(bundle.card) !== null);

// --- a card in a real chat room --------------------------------------------

import * as N from "./kant-net.mjs";
const msg = { room: "room7", sender: "alice", seq: 3, body: S.chatBody(card) };
const line = N.printMsg({ ...msg, witness: N.msgWitness(msg) });
const back = N.parseMsg(line);
ok("the chat line parses", back !== null);
ok(
  "a card shared in a room arrives whole",
  back !== null && JSON.stringify(S.readChatBody(back.body)) === JSON.stringify(card),
);
const doctored = line.slice(0, -2) + (line.endsWith("00") ? "11" : "00");
ok("a doctored chat line is refused", N.parseMsg(doctored) === null);

// --- where links point when no kant.config can be read -------------------
// The stack self-deploys, so the built-in configuration must not name a
// host: a copy served from somewhere else has to mint links for where it
// is actually being served, not where the file was written.
eq("the built-in origin is empty", S.DEFAULT_CONFIG.origin, "");
ok("the built-in config names no deployment host",
  !/^https?:\/\//.test(S.originOf(S.DEFAULT_CONFIG)) ||
  globalThis.location?.origin === "https://kant.cicada71.net");
eq("a configured origin wins", S.originOf(CONFIG), CONFIG.origin);
eq("a blank origin means same-origin",
  S.originOf({ origin: "  " }), globalThis.location?.origin
    ? `${globalThis.location.origin}/` : "");
eq("links are relative when there is no origin at all",
  S.addressUrl({ origin: "" }, SAMPLE_URL.replace(CONFIG.origin, "")),
  `#${SAMPLE_URL.replace(CONFIG.origin, "")}`);
ok("a configured origin still builds the whole URL",
  S.addressUrl(CONFIG, "abc").startsWith(CONFIG.origin));

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  process.exit(1);
}
