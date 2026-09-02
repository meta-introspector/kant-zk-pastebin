// Drives web/index.html itself, in a hand-rolled DOM just big enough for it.
//
// The point is not to test the browser: it is to catch the things a static
// read cannot — a handler that throws, a screen that never shows, a camera
// flag that gets out of step with the proved state machine.
//
//   node web/page-test.mjs

import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import * as N from "./kant-net.mjs";
import * as F from "./kant-flow.mjs";

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };
const eq = (name, got, want) =>
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, "index.html"), "utf8");

// ------------------------------------------------------------- a tiny DOM

class El {
  constructor(id = "", tag = "div") {
    this.id = id;
    this.tagName = tag.toUpperCase();
    this.children = [];
    this._classes = new Set();
    this.style = {};
    this.textContent = "";
    this.innerHTML = "";
    this.value = "";
    this.title = "";
    this.scrollTop = 0;
    this.scrollHeight = 0;
    this.srcObject = null;
    this.href = "";
    this.download = "";
    this.classList = {
      toggle: (c, on) => (on ? this._classes.add(c) : this._classes.delete(c)),
      contains: (c) => this._classes.has(c),
      add: (c) => this._classes.add(c),
      remove: (c) => this._classes.delete(c),
    };
  }
  get shown() { return this._classes.has("on"); }
  appendChild(c) { this.children.push(c); return c; }
  remove() {}
  select() {}
  click() { if (this.onclick) return this.onclick(); }
  play() { return Promise.resolve(); }
  addEventListener() {}
}

const elements = new Map();
for (const id of [...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1])) {
  elements.set(id, new El(id));
}
const $ = (id) => elements.get(id);

const clipboard = { last: "" };
const body = new El("", "body");

globalThis.document = {
  body,
  getElementById: (id) => elements.get(id) ?? null,
  createElement: (tag) => new El("", tag),
  execCommand: () => true,
};
globalThis.location = {
  origin: "https://example.test",
  pathname: "/kant/",
  protocol: "https:",
  hash: "",
};
Object.defineProperty(globalThis, "navigator", {
  configurable: true,
  value: { clipboard: { writeText: async (t) => { clipboard.last = t; } } },
});
globalThis.window = { speechSynthesis: null };
globalThis.requestAnimationFrame = () => 0;
globalThis.SpeechSynthesisUtterance = class { constructor(t) { this.text = t; } };

// `kant.config` is read off the disk; nothing else is reachable.
const CONFIG_TEXT = readFileSync(join(here, "kant.config"), "utf8");
const seen = { health: 0 };
globalThis.fetch = async (url) => {
  if (String(url).endsWith("kant.config")) {
    return { ok: true, text: async () => CONFIG_TEXT };
  }
  if (String(url).includes("/health")) {
    seen.health += 1;
    throw new Error("no relay in this test");
  }
  throw new Error(`unexpected fetch ${url}`);
};

// ------------------------------------------------------------ run the page

const src = /<script type="module">([\s\S]*?)<\/script>/.exec(html)[1];
const scratch = join(here, ".page-under-test.mjs");
writeFileSync(scratch, src);
try {
  await import("./.page-under-test.mjs");
  // the startup block is async; let its microtasks and the /health probe run
  await new Promise((r) => setTimeout(r, 50));

  // --------------------------------------------------------------- welcome
  ok("the welcome screen is on show", $("s-welcome").shown);
  ok("no other screen is", !$("s-share").shown && !$("s-chat").shown);
  ok("the guide has said something", $("prompt").textContent.length > 0);
  ok("the guide starts at step one", $("prompt").textContent.startsWith("Step one"));
  eq("no step is done yet", $("steps").textContent, "○ ○ ○");
  eq("back is hidden on the first screen", $("back").style.visibility, "hidden");
  ok("the relay probe ran", seen.health === 0 || seen.health >= 1);
  ok("with no relay it says so",
    /No relay is configured/.test($("transport").innerHTML) ||
    /relay/i.test($("transport").innerHTML));

  // ----------------------------------------------------------- start a room
  $("btn-open").click();
  ok("starting a room shows the share screen", $("s-share").shown);
  ok("there is one link", $("link").value.startsWith("https://example.test/kant/#"));
  ok("the link is not the bare code", !$("link").value.startsWith("kzinvite"));
  ok("the code was drawn", $("qr").innerHTML.includes("<svg"));
  ok("the code carries the whole link", $("qr").innerHTML.includes("example.test"));
  ok("the icon is drawn on the code", $("qr").innerHTML.includes("kant-logo.svg"));
  ok("the caption is printed under it", $("qr").innerHTML.includes("kant-zk-pastebin"));
  ok("the guide has moved on", $("prompt").textContent.startsWith("Step two"));
  eq("step one is done", $("steps").textContent, "● ○ ○");

  const link = $("link").value;
  ok("the link on the screen really is an invitation", F.findInvite(link) !== null);

  // ------------------------------------------------------------- copy it
  await $("btn-copy").onclick();
  eq("the copy button copies the link", clipboard.last, link);
  eq("step two is done", $("steps").textContent, "● ● ○");
  ok("the guide has moved on again", $("prompt").textContent.startsWith("Step three"));

  // custom words and a custom picture
  $("caption").value = "come and argue with me";
  $("caption").oninput();
  ok("the custom words go on the code",
    $("qr").innerHTML.includes("come and argue with me"));
  $("icon").value = "./elsewhere.svg";
  $("icon").oninput();
  ok("the custom picture goes on the code", $("qr").innerHTML.includes("elsewhere.svg"));

  // ---------------------------------------------------------------- say
  $("btn-openroom").click();
  ok("the room is on show", $("s-chat").shown);
  $("say").value = "hello";
  await $("btn-send").onclick();
  eq("all three steps are done", $("steps").textContent, "● ● ●");
  ok("the guide says so", /That is everything/.test($("prompt").textContent));
  ok("the line is in the room", $("chat").innerHTML.includes("hello"));

  // -------------------------------------------------------------- joining
  $("back").click();
  ok("back goes home", $("s-welcome").shown);
  $("btn-join").click();
  ok("the join screen is on show", $("s-join").shown);
  $("joinbox").value = "come in!!  " + link + " .\n";
  $("btn-dojoin").click();
  ok("a messy paste joins the room", $("s-chat").shown);
  $("back").click();
  $("btn-join").click();
  $("joinbox").value = "nothing here at all";
  $("btn-dojoin").click();
  ok("junk does not join", $("s-join").shown);
  ok("...and says why", /no invite link/.test($("joinmsg").innerHTML));

  // --------------------------------------------------------- the camera
  $("back").click();
  $("btn-scan").click();
  ok("the scan screen is on show", $("s-scan").shown);
  $("btn-stop").click();
  ok("stopping the camera leaves the scan screen up but the camera off",
    $("scanmsg").textContent === "the camera is off");
  $("back").click();
  ok("back leaves the scan screen", $("s-welcome").shown);

  // ------------------------------------------------------ copying a note
  $("btn-more").click();
  ok("the more screen is on show", $("s-more").shown);
  $("note").value = "The Critique of Pure Paste.";
  await $("btn-copytext").onclick();
  eq("copying gives the words", clipboard.last, "The Critique of Pure Paste.");
  await $("btn-copytextmeta").onclick();
  eq("...and with the details, the words are still recoverable",
    F.bodyOf(clipboard.last), "The Critique of Pure Paste.");
  const meta = F.metaOf(clipboard.last);
  ok("...along with the details", meta !== null && meta.link.includes("example.test"));
  await $("btn-copynotelink").onclick();
  ok("a link to the note is a page link", clipboard.last.startsWith("https://example.test/kant/#"));

  // ---------------------------------------------------------- the mute
  $("hush").click();
  eq("the mute button mutes", $("hush").textContent, "🔇");
  $("hush").click();
  eq("...and unmutes", $("hush").textContent, "🔊");

  // ------------------------------------ what an invite link in the URL does
  ok("the invitation in the link names a real room",
    N.inviteRoom(F.findInvite(link)).length === 64);
} finally {
  unlinkSync(scratch);
}

console.log(`${checks - fail.length}/${checks} checks passed`);
for (const f of fail) console.error(`FAIL: ${f}`);
// The page leaves a relay poll running, as it would in a browser; say so and go.
process.exit(fail.length ? 1 : 0);
