// Drives web/diag.html itself, in a hand-rolled DOM just big enough for it.
//
//   node web/diagpage-test.mjs

import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import * as D from "./kant-diag.mjs";
import * as SL from "./kant-sharelog.mjs";

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, "diag.html"), "utf8");

class El {
  constructor(id = "", tag = "div") {
    this.id = id;
    this.tagName = tag.toUpperCase();
    this.textContent = "";
    this.innerHTML = "";
    this.value = "";
    this.href = "";
    this.download = "";
    this.files = [];
  }
  appendChild() {}
  remove() {}
  select() {}
  click() { if (this.onclick) return this.onclick(); }
  addEventListener() {}
}

const elements = new Map();
for (const id of [...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1])) {
  elements.set(id, new El(id));
}
const $ = (id) => elements.get(id);

const clipboard = { last: "" };
globalThis.document = {
  body: new El("", "body"),
  getElementById: (id) => elements.get(id) ?? null,
  createElement: (tag) => new El("", tag),
  execCommand: () => true,
};
globalThis.location = {
  origin: "https://example.test", pathname: "/kant/diag.html",
  protocol: "https:", hash: "", href: "https://example.test/kant/diag.html",
};
Object.defineProperty(globalThis, "navigator", {
  configurable: true,
  value: { clipboard: { writeText: async (t) => { clipboard.last = t; } } },
});
globalThis.Blob = class { constructor(parts) { this.parts = parts; } };
globalThis.URL = { createObjectURL: () => "blob:diag", revokeObjectURL: () => {} };

const local = new Map();
globalThis.localStorage = {
  getItem: (k) => (local.has(k) ? local.get(k) : null),
  setItem: (k, v) => local.set(k, v),
};
local.set("kant-diag-previous", D.renderLog([
  D.event(0, 1, "info", "app", "page opened", ""),
  D.event(1, 9, "error", "relay", "the relay went away", "status=502"),
]));

const session = new Map();
globalThis.sessionStorage = {
  getItem: (k) => (session.has(k) ? session.get(k) : null),
  setItem: (k, v) => session.set(k, v),
};

// The app left a run behind, as the "Open the diagnostics page" button does.
const handed = {
  verdict: "onlyThisBrowser",
  room: D.ref("a room"),
  relay: "",
  events: [
    D.event(0, 3, "info", "app", "page opened", "https://example.test/kant/"),
    D.event(1, 41, "warn", "config", "no relay configured", ""),
    D.event(2, 88, "error", "relay", "the line did not reach the relay", "status=404"),
  ],
};
session.set("kant-diag", D.renderReport(handed));

const CONFIG_TEXT = readFileSync(join(here, "kant.config"), "utf8");
globalThis.fetch = async (url) => {
  if (String(url).endsWith("kant.config")) return { ok: true, text: async () => CONFIG_TEXT };
  if (String(url).includes("/health")) throw new Error("nothing is listening here");
  throw new Error(`unexpected fetch ${url}`);
};

const src = /<script type="module">([\s\S]*?)<\/script>/.exec(html)[1];
const scratch = join(here, ".diag-under-test.mjs");
writeFileSync(scratch, src);
try {
  await import("./.diag-under-test.mjs");
  await new Promise((r) => setTimeout(r, 30));

  ok("the run handed over is shown", $("rows").innerHTML.includes("the line did not reach"));
  ok("every event is a row", ($("rows").innerHTML.match(/<tr/g) ?? []).length === 3);
  ok("errors are marked as errors", $("rows").innerHTML.includes('class="error"'));
  ok("the verdict is explained", $("verdict").innerHTML.includes("only-this-browser"));
  ok("the counts are shown", $("counts").textContent.includes("3 events"));

  await $("btn-copy").onclick();
  ok("copying gives a readable run", clipboard.last.startsWith("kant-zk diagnostics"));
  ok("...that reads back", D.findReport(clipboard.last)?.events.length === 3);

  $("btn-save").click();
  ok("saving says so", /kant-diagnostics\.txt/.test($("sharemsg").textContent));

  await $("btn-link").onclick();
  ok("a link carries the run", clipboard.last.startsWith("https://example.test/kant/diag.html#"));
  ok("...and reads back out of the link",
    D.findReport(decodeURIComponent(clipboard.last.split("#")[1]))?.events.length === 3);

  // The run cut into chat messages, and pasted back in as such: the whole
  // trip through a chat window, with nothing running anywhere.
  await $("btn-chat").onclick();
  ok("the run cuts into chat messages", /message\(s\)/.test($("sharemsg").textContent));
  const chatText = $("chatparts").value;
  ok("...each inside a tweet", chatText.split(/^--- \d+\/\d+ ---$/m)
    .map((t) => t.trim()).filter(Boolean).every((t) => t.length <= 280));
  ok("...copied ready to send", clipboard.last === chatText);
  $("paste").value = chatText;
  $("btn-load").click();
  ok("pasted-back messages load as the run", $("loadmsg").textContent.includes("3 events"));
  ok("...with the events in them", $("rows").innerHTML.includes("the line did not reach"));

  // Posting the run to this device's store.
  $("btn-post").click();
  ok("the run posts to the store", $("sharemsg").innerHTML.includes("posted to the store"));
  const held = SL.loadStore(globalThis.localStorage);
  ok("...which now holds it", held.entries.length === 1);
  ok("...as a readable run", (SL.readPostedLog(held.entries[0])?.events?.length ?? 0) === 3);
  ok("...and the block itself can be carried by hand",
    SL.carry(new (await import("./kantzk.mjs")).Store(), $("chatparts").value).witness
      === held.entries[0].witness);

  // Somebody else's run, pasted with a message around it.
  const theirs = {
    verdict: "relayDown", room: D.ref("theirs"), relay: "https://relay.example",
    events: [D.event(0, 7, "error", "probe", "cannot reach that relay", "TypeError: fetch failed")],
  };
  $("paste").value = `it will not connect, here is my run:\n${D.renderReport(theirs)}\nthanks!`;
  $("btn-load").click();
  ok("a pasted run loads", $("rows").innerHTML.includes("cannot reach that relay"));
  ok("...with their verdict", $("verdict").innerHTML.includes("relay-down"));
  ok("...and says how much", $("loadmsg").textContent.includes("1 events"));

  $("paste").value = "this is not a run at all";
  $("btn-load").click();
  ok("junk does not load", $("loadmsg").innerHTML.includes("no run found"));

  // The run from before the last reload is still there.
  $("btn-previous").click();
  ok("the earlier run can be read", $("rows").innerHTML.includes("the relay went away"));

  // The page can check this machine by itself.
  await $("btn-check").onclick();
  await new Promise((r) => setTimeout(r, 30));
  ok("the checks write their own run", $("rows").innerHTML.includes("checks started here"));
  ok("...and reach a verdict", $("verdict").innerHTML.length > 0);
  ok("...naming what is missing",
    /no-transport|only-this-browser|room-mismatch|no-room|relay-down/.test($("verdict").innerHTML));
  ok("...having probed this origin", $("rows").innerHTML.includes("example.test"));

  // The code inspector: the two blocks that were reported as "not connecting".
  const CARD_TEXT =
    "kant-zk-pastebin\n" +
    "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605\n" +
    "6b7a63617264:68747470733a2f2f6b616e742e63696361646137312e6e65742f236666383130663239" +
    "3166313837623830386130313833663833633034363638373435373365663563346336643764396564" +
    "343330633666376437313066363035:6b616e742d7a6b2d706173746562696e:2e2f6b616e742d6c6f" +
    "676f2e737667:746865204b616e7420706173746562696e206c6f676f";
  const INVITE =
    "6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c65:7365637265742d6f6e65:706565722d61";

  $("code-a").value = CARD_TEXT;
  $("code-b").value = CARD_TEXT;
  await $("btn-codes").onclick();
  ok("two cards are one code", $("codemsg").innerHTML.includes("verdict: same-code"));
  ok("...and are named as cards", $("codemsg").innerHTML.includes("first: card"));
  ok("...with the relative-picture warning",
    $("codemsg").innerHTML.includes("relative-picture"));

  $("code-b").value = "";
  await $("btn-codes").onclick();
  ok("one card on its own is explained", $("codemsg").innerHTML.includes("carries no room"));

  $("code-a").value = INVITE;
  $("code-b").value = INVITE;
  await $("btn-codes").onclick();
  ok("two copies of one invitation connect",
    $("codemsg").innerHTML.includes("verdict: connectable"));

  $("code-a").value = "";
  $("code-b").value = "";
  await $("btn-codes").onclick();
  ok("nothing pasted is said so", $("codemsg").innerHTML.includes("paste a code"));
} finally {
  unlinkSync(scratch);
}

console.log(`${checks - fail.length}/${checks} checks passed`);
for (const f of fail) console.error(`FAIL: ${f}`);
process.exit(fail.length ? 1 : 0);
