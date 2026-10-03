// Drives web/hand.html itself — the no-server, chat-only mode — in a
// hand-rolled DOM just big enough for it, and then drives two of them
// against each other: two "devices" that never touch a network and only
// ever move text the way a person would.
//
//   node web/handpage-test.mjs

import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import * as K from "./kantzk.mjs";
import * as U from "./kant-uucp.mjs";
import * as SL from "./kant-sharelog.mjs";
import * as D from "./kant-diag.mjs";

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };
const eq = (name, got, want) =>
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, "hand.html"), "utf8");

class El {
  constructor(id = "", tag = "div") {
    this.id = id;
    this.tagName = tag.toUpperCase();
    this.textContent = "";
    this.innerHTML = "";
    this.value = "";
  }
  appendChild() {}
  remove() {}
  select() {}
  click() { if (this.onclick) return this.onclick(); }
  addEventListener() {}
}

const ids = [...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1]);
const elements = new Map(ids.map((id) => [id, new El(id)]));
const $ = (id) => elements.get(id);

const clipboard = { last: "" };
globalThis.document = {
  body: new El("", "body"),
  getElementById: (id) => elements.get(id) ?? null,
  createElement: (tag) => new El("", tag),
  execCommand: () => true,
};
globalThis.location = {
  origin: "https://example.test", pathname: "/kant/hand.html",
  protocol: "https:", hash: "", href: "https://example.test/kant/hand.html",
};
Object.defineProperty(globalThis, "navigator", {
  configurable: true,
  value: { clipboard: { writeText: async (t) => { clipboard.last = t; } } },
});

const local = new Map();
globalThis.localStorage = {
  getItem: (k) => (local.has(k) ? local.get(k) : null),
  setItem: (k, v) => local.set(k, v),
};

// Nothing on this page may reach the network: any fetch at all is a failure.
let fetches = 0;
globalThis.fetch = async (url) => { fetches += 1; throw new Error(`no server: ${url}`); };

const src = /<script type="module">([\s\S]*?)<\/script>/.exec(html)[1];
const scratch = join(here, ".hand-under-test.mjs");
writeFileSync(scratch, src);
try {
  await import("./.hand-under-test.mjs");

  ok("the page opens with no passphrase yet", $("who").textContent.includes("pick a name"));
  ok("and nothing said", $("chat").innerHTML.includes("nothing said yet"));

  // --- step 1: who you are ------------------------------------------------
  $("name").value = "alice";
  $("passphrase").value = "the same words on both devices";
  $("btn-start").click();
  ok("the passphrase names a room", $("who").textContent.includes("room "));
  ok("and you are named", $("who").textContent.includes("alice"));
  eq("the steps are the four", ($("steps").innerHTML.match(/<li>/g) ?? []).length, 4);
  ok("the first step is yours", $("steps").innerHTML.includes("<b>alice</b>"));
  ok("nothing on the page needs a server",
    $("codemsg").textContent.includes("contacts a server"));

  // --- step 2: say something ----------------------------------------------
  $("say").value = "is anyone there?";
  $("btn-say").click();
  ok("what you said is held", $("chat").innerHTML.includes("is anyone there?"));
  ok("…and attributed", $("chat").innerHTML.includes("alice"));
  ok("…and it says to send the code", $("saymsg").textContent.includes("send your code"));

  const aliceCode = $("mycode").value;
  ok("your code is a bag", aliceCode.startsWith(K.hexEncode(K.asciiBytes("kzbag"))));
  ok("your code is plain text", K.isAscii(aliceCode));

  await $("btn-copycode").onclick();
  eq("copying gives exactly that code", clipboard.last, aliceCode);

  await $("btn-split").onclick();
  ok("it can also go as chat-sized messages", clipboard.last.includes("--- 1/"));

  // --- the other device ----------------------------------------------------
  // Bob is the same page, run again: a second node, no connection of any kind.
  const bob = U.SneakerNode.blank("bob");
  const room = K.witness(Array.from("the same words on both devices"));
  bob.paste(aliceCode);
  eq("bob hears alice from the pasted code alone", bob.view().length, 1);
  bob.write(room, "yes, right here");

  // --- step 4: paste theirs back -------------------------------------------
  $("theircode").value = bob.bag();
  $("btn-paste").click();
  ok("their code is taken in", $("pastemsg").innerHTML.includes("taken in"));
  ok("and their line is on screen", $("chat").innerHTML.includes("yes, right here"));
  eq("both sides now hold the same conversation",
    JSON.stringify(bob.view().map((m) => K.fromUtf8(m.body)).sort()),
    JSON.stringify(["is anyone there?", "yes, right here"].sort()));

  // an edited code changes nothing at all
  const held = $("chat").innerHTML;
  $("theircode").value = `${bob.bag().slice(0, -4)}dead`;
  $("btn-paste").click();
  ok("an edited code is refused", $("pastemsg").innerHTML.includes("did not read back"));
  eq("…and changes nothing", $("chat").innerHTML, held);

  // the numbered messages may arrive in any order
  for (let i = 0; i < 30; i += 1) bob.write(room, `a further line, number ${i}`);
  const parts = U.bagForCarrier(bob.bag(), "tweet");
  ok("a long conversation needs several messages", parts.length > 1);
  $("theircode").value = [...parts].reverse().join("\n");
  $("btn-paste").click();
  ok("shuffled messages still arrive", $("pastemsg").innerHTML.includes("taken in"));
  ok("…with everything in them", $("chat").innerHTML.includes("a further line, number 29"));

  // --- carrying a block, and somebody's run, by hand ------------------------
  const note = K.makePaste({ id: "n1", title: "a note", content: "hello", timestamp: "t" });
  $("carry").value = SL.carryText(note);
  $("btn-carry").click();
  ok("a block carried by hand is held", $("carrymsg").innerHTML.includes(note.witness.slice(0, 16)));
  ok("…and listed", $("storelist").textContent.includes("a note"));

  const theirRun = {
    verdict: "relayDown",
    room: D.ref("their room"),
    relay: "https://relay.example.org",
    events: [D.event(0, 9, "error", "probe", "cannot reach that relay", "fetch failed")],
  };
  $("carry").value = `it will not connect:\n${D.renderReport(theirRun)}\nany ideas?`;
  $("btn-carry").click();
  ok("a run pasted in is recognised", $("carrymsg").innerHTML.includes("somebody's run"));
  ok("…and posted to the store", $("carrymsg").innerHTML.includes("posted to your store"));
  ok("…and listed as the run", $("storelist").textContent.includes("the run so far"));

  $("carry").value = "this is neither";
  $("btn-carry").click();
  ok("junk is refused", $("carrymsg").innerHTML.includes("neither a block nor a run"));

  await $("btn-copystore").onclick();
  ok("everything held copies as one bundle", (K.pasteAll(clipboard.last) ?? []).length === 2);

  // --- the whole point ------------------------------------------------------
  eq("not one request was made to anything", fetches, 0);

  // --- the state survives a reload ------------------------------------------
  const saved = JSON.parse(local.get("kant-hand-node"));
  const reloaded = U.SneakerNode.fromJSON(saved);
  eq("the conversation is still there after a reload",
    reloaded.view().length, bob.view().length);
} finally {
  unlinkSync(scratch);
}

console.log(`${checks - fail.length}/${checks} checks passed`);
for (const f of fail) console.error(`FAIL: ${f}`);
process.exit(fail.length ? 1 : 0);
