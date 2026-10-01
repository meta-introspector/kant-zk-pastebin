// Conformance checks for web/kant-carddebug.mjs against the golden vectors
// Lean checks in RequestProject/Kant/CardDebug.lean (the `#guard` block), and
// against the two blocks that were reported as "not connecting".
//
//   node web/carddebug-test.mjs

import * as D from "./kant-carddebug.mjs";
import { execFileSync } from "node:child_process";
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

// ------------------------------------------------- the report's own two blocks

const CARD_LINE =
  "6b7a63617264:68747470733a2f2f6b616e742e63696361646137312e6e65742f236666383130663239" +
  "3166313837623830386130313833663833633034363638373435373365663563346336643764396564" +
  "343330633666376437313066363035:6b616e742d7a6b2d706173746562696e:2e2f6b616e742d6c6f" +
  "676f2e737667:746865204b616e7420706173746562696e206c6f676f";
const PAGE_URL =
  "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605";
const CARD_TEXT = `kant-zk-pastebin\n${PAGE_URL}\n${CARD_LINE}`;
const ADDRESS = "ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605";

const card = D.classify(CARD_TEXT);
eq("the pasted block is a card", card.kind, "card");
eq("its url", card.card.url, PAGE_URL);
eq("its caption", card.card.caption, "kant-zk-pastebin");
eq("its picture", card.card.picture, "./kant-logo.svg");
eq("its description", card.card.alt, "the Kant pastebin logo");
ok("a card names no room", D.roomOf(card) === null);
ok("a card names no relay", D.relayOf(card) === null);

// The bare code line on its own reads as the same card.
eq("the bare card line is the same card", JSON.stringify(D.classify(CARD_LINE)),
  JSON.stringify(card));
// So does the card with a trailing newline, spaces, or CRLF line endings.
eq("trailing whitespace is tolerated", D.classify(`${CARD_TEXT}   \n\n`).kind, "card");
eq("CRLF is tolerated", D.classify(CARD_TEXT.replace(/\n/g, "\r\n")).kind, "card");

const page = D.classify(PAGE_URL);
eq("the link on its own is a page", page.kind, "page");
eq("its address", page.addr, ADDRESS);
ok("a page link names no room", D.roomOf(page) === null);

eq("two copies of the card are one code", D.pair(CARD_TEXT, CARD_TEXT), "same-code");
eq("card and link are both pages", D.pair(CARD_TEXT, PAGE_URL), "not-invites");
eq("two copies of the link are one code", D.pair(PAGE_URL, PAGE_URL), "same-code");
ok("the reported pair is not connectable", D.pair(CARD_TEXT, CARD_TEXT) !== "connectable");

eq("the card earns a relative-picture warning",
  D.cardWarnings("https://kant.cicada71.net/", card.card).join(","), "relative-picture");
eq("a card on another site earns a foreign-origin warning",
  D.cardWarnings("https://example.org/", card.card).join(","),
  "relative-picture,foreign-origin");
eq("a full picture URL on this site earns nothing",
  D.cardWarnings("https://kant.cicada71.net/",
    { ...card.card, picture: "https://kant.cicada71.net/kant-logo.svg" }).join(","), "");
ok("a data: URI counts as absolute", D.relative("data:image/svg+xml;base64,AAA") === false);

// --------------------------------------- the invitation vectors Lean pins

const INV_A =
  "6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c65:7365637265742d6f6e65:706565722d61";
const INV_B =
  "6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c65:7365637265742d74776f:706565722d62";
const INV_NO_RELAY = "6b7a696e76697465::7365637265742d6f6e65:706565722d63";
const INV_OTHER_RELAY =
  "6b7a696e76697465:68747470733a2f2f6f746865722e6578616d706c65:7365637265742d6f6e65:706565722d64";
const ROOM_A = "aff4dd0dc912a426f8014bb2870bc8e50c6cdb7039d9f3a86c84b5004f61cdb7";
const ROOM_B = "8885040e43bcf5dc594b34b2beb87fef21d2826fb4c4344e1d0f5e0021f39801";

eq("an invitation is an invitation", D.classify(INV_A).kind, "invite");
eq("its room (Lean vector)", D.roomOf(D.classify(INV_A)), ROOM_A);
eq("the other room (Lean vector)", D.roomOf(D.classify(INV_B)), ROOM_B);
eq("its relay", D.relayOf(D.classify(INV_A)), "https://relay.example");

eq("one invitation, both sides: connectable", D.pair(INV_A, INV_A), "connectable");
eq("two secrets, two rooms", D.pair(INV_A, INV_B), "different-rooms");
eq("no relay, nowhere to meet", D.pair(INV_NO_RELAY, INV_NO_RELAY), "no-meeting-point");
eq("two relays, nowhere to meet", D.pair(INV_A, INV_OTHER_RELAY), "no-meeting-point");
eq("a card and an invitation", D.pair(CARD_TEXT, INV_A), "one-not-invite");
eq("an invitation and a card", D.pair(INV_A, CARD_TEXT), "one-not-invite");

// An invitation also travels inside the whole page URL.
eq("an invitation inside a link is an invitation",
  D.classify(`https://kant.cicada71.net/#${INV_A}`).kind, "invite");
eq("and it still connects", D.pair(`https://kant.cicada71.net/#${INV_A}`, INV_A), "connectable");
// And inside a sentence a human wrote around it.
eq("an invitation on the last line of a message",
  D.pair(`join me\n${INV_A}`, INV_A), "connectable");

eq("junk is junk", D.classify("hello there").kind, "unknown");
eq("empty text is junk", D.classify("").kind, "unknown");
eq("two pieces of junk", D.pair("hello", "hello"), "same-code");
eq("two unreadable pastes are both 'unknown', so neither can connect",
  D.pair("hello", "goodbye"), "same-code");

eq("the last non-blank line is the code", D.codeLine("  a  \n  b \n   \n"), "b");
eq("trim", D.trim("  x \t"), "x");

// ------------------------------------------------------------- the sentences

for (const p of D.PAIRINGS) {
  ok(`${p} has a sentence`, D.explain(p).length > 0);
  ok(`${p} starts with its own name`, D.explain(p).startsWith(p + ":"));
  ok(`${p} has advice`, D.advise(p).length > 0);
}
ok("the six sentences are six different sentences",
  new Set(D.PAIRINGS.map(D.explain)).size === D.PAIRINGS.length);

// -------------------------------------------------------------- the report

const r = D.report(CARD_TEXT, CARD_TEXT, "https://kant.cicada71.net/");
eq("the report's verdict", r.verdict, "same-code");
eq("the report names both sides", `${r.left.kind}/${r.right.kind}`, "card/card");
ok("the report carries the warning", r.warnings.includes("relative-picture"));
const text = D.renderReport(r).join("\n");
ok("the printed report says the verdict", text.includes("verdict: same-code"));
ok("the printed report says there is no room", text.includes("room    (none"));
ok("the printed report says what to do", text.includes("kzinvite"));

ok("a single card is explained", D.single(card).includes("carries no room"));
ok("a single page link is explained", D.single(page).includes("page link"));
ok("a single invitation is explained", D.single(D.classify(INV_A)).includes("invitation"));
ok("an invitation with no relay is explained",
  D.single(D.classify(INV_NO_RELAY)).includes("nowhere to meet"));

// ----------------------------------------------------------- the command line

const cli = (...args) =>
  execFileSync(process.execPath, [join(here, "..", "scripts", "kant-debug.mjs"), ...args],
    { encoding: "utf8", cwd: join(here, "..") });

ok("the command line reports the pair",
  cli(CARD_TEXT, CARD_TEXT).includes("verdict: same-code"));
ok("the command line reports one code",
  cli(PAGE_URL).includes("page link"));
ok("the command line can speak JSON",
  JSON.parse(cli("--json", CARD_TEXT, INV_A)).verdict === "one-not-invite");
ok("the command line says where the log is",
  cli("--where-is-the-log").includes("diag.html"));

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  process.exit(1);
}
