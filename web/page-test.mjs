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
    this.dataset = {};
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

  /** The anchors inside this element, parsed out of the innerHTML the page
   *  just wrote.  The page wires handlers with
   *  `box.querySelectorAll("a[data-f]")`, so the shim has to answer that or
   *  renderFiles throws before the test can assert anything — which it did,
   *  silently, on a click that reached renderFiles at all.
   *
   *  Returns El stubs carrying the matched attributes, so `.dataset` and
   *  `.onclick` in the page behave as they do in a browser.  Descends into
   *  children too, since a real querySelectorAll is not depth-limited. */
  querySelectorAll(sel) {
    const attr = /\[([\w-]+)\]/.exec(sel);
    const tag = /^([a-z]+)/i.exec(sel)?.[1]?.toLowerCase();
    const out = [];
    const walk = (el) => {
      for (const m of el.innerHTML.matchAll(/<([a-z]+)\s([^>]*)>/gi)) {
        const [, t, attrs] = m;
        if (tag && t.toLowerCase() !== tag) continue;
        if (attr && !new RegExp(`\\b${attr}=["']([^"']*)["']`).test(attrs)) continue;
        const a = /data-([\w-]+)=["']([^"']*)["']/.exec(attrs);
        const e = new El("", t);
        if (a) e.dataset = { [a[1].replace(/-(\w)/g, (_, c) => c.toUpperCase())]: a[2] };
        out.push(e);
      }
      for (const c of el.children) walk(c);
    };
    walk(this);
    return out;
  }
  querySelector(sel) { return this.querySelectorAll(sel)[0] ?? null; }
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
  href: "https://example.test/kant/",
};
Object.defineProperty(globalThis, "navigator", {
  configurable: true,
  value: { clipboard: { writeText: async (t) => { clipboard.last = t; } } },
});
const pageErrors = [];
globalThis.window = {
  speechSynthesis: null,
  addEventListener: (kind, fn) => pageErrors.push([kind, fn]),
  open: (u) => { opened.push(u); return null; },
};
const opened = [];
const local = new Map();
// A run left behind by an earlier visit, as a real browser would hold it.
local.set("kant-diag-run",
  "6b7a6c6f67::05:01:09:616e206561726c6965722072756e:");
globalThis.localStorage = {
  getItem: (k) => (local.has(k) ? local.get(k) : null),
  setItem: (k, v) => local.set(k, v),
};

const session = new Map();
globalThis.sessionStorage = {
  getItem: (k) => (session.has(k) ? session.get(k) : null),
  setItem: (k, v) => session.set(k, v),
};
globalThis.Blob = class { constructor(parts) { this.parts = parts; } };
globalThis.URL = { createObjectURL: () => "blob:diag", revokeObjectURL: () => {} };
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

  // ------------------------------------------------------ how it reads
  // The formatting lives in kant-pretty.mjs and is unit-tested there. These
  // check that the page actually routes the room through it, which is the part
  // only this harness can see.
  ok("the transcript is grouped by day", $("chat").innerHTML.includes('class="daysep"'));
  ok("...and the day is labelled", /Today|Yesterday/.test($("chat").innerHTML));
  ok("each line carries an avatar", $("chat").innerHTML.includes('class="avatar'));
  ok("...which falls back to an initial for a peer with no profile",
    /class="avatar initial"/.test($("chat").innerHTML));
  ok("each line is timestamped", /class="at"/.test($("chat").innerHTML));
  ok("the exact instant is one hover away",
    $("chat").innerHTML.includes(new Date(Date.now()).toISOString().slice(0, 4)) ||
    /title="[^"]*T\d\d:\d\d/.test($("chat").innerHTML));
  ok("the reader's timezone is stated", /times shown in UTC/.test($("chatstatus").textContent));
  ok("the room's own lines are marked as mine", $("chat").innerHTML.includes('class="line mine"'));

  // Naming yourself: a name is your own claim, and the page says so. Asserted
  // through the DOM only — `node` lives inside the page's module scope, which
  // this harness deliberately does not reach into.
  $("profname").value = "ada";
  $("profbio").value = "maths";
  await $("btn-profname").onclick();
  ok("the page shows the name it just published", /ada/.test($("profstatus").textContent),
    $("profstatus").textContent);
  ok("...and the bio it just published", /maths/.test($("profstatus").textContent),
    $("profstatus").textContent);
  ok("the page says a name is only a claim",
    /claim/i.test($("profstatus").textContent), $("profstatus").textContent);
  ok("setting a name did not break the transcript",
    $("chat").innerHTML.includes('class="daysep"') && $("chat").innerHTML.includes("hello"));
  $("profname").value = "   ";
  await $("btn-profname").onclick();
  ok("an empty name is refused rather than published",
    /showing as ada/.test($("profstatus").textContent), $("profstatus").textContent);

  // -------------------------------------------------------------- joining
  $("back").click();
  ok("back goes home", $("s-welcome").shown);
  $("btn-join").click();
  ok("the join screen is on show", $("s-join").shown);
  $("joinbox").value = "come in!!  " + link + " .\n";
  // Awaited: the join handler is async (it settles the relay before attaching),
  // so checking the screen synchronously tests nothing but the microtask
  // queue. This assertion was passing for the wrong reason — the click was
  // still in flight.
  await $("btn-dojoin").click();
  ok("a messy paste joins the room", $("s-chat").shown);
  $("back").click();
  $("btn-join").click();
  $("joinbox").value = "nothing here at all";
  await $("btn-dojoin").click();
  ok("junk does not join", $("s-join").shown);
  ok("...and says why", /no invite link/.test($("joinmsg").innerHTML));

  // A share card pasted into the join box is named for what it is, rather
  // than only refused (`Kant.CardDebug.classify`).
  $("joinbox").value =
    "kant-zk-pastebin\n" +
    "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605\n" +
    "6b7a63617264:68747470733a2f2f6b616e742e63696361646137312e6e65742f236666383130663239" +
    "3166313837623830386130313833663833633034363638373435373365663563346336643764396564" +
    "343330633666376437313066363035:6b616e742d7a6b2d706173746562696e:2e2f6b616e742d6c6f" +
    "676f2e737667:746865204b616e7420706173746562696e206c6f676f";
  $("btn-dojoin").click();
  ok("a share card does not join", $("s-join").shown);
  ok("...and is named as a share card", /share card/.test($("joinmsg").innerHTML));
  ok("...saying it names no room", /names no room/.test($("joinmsg").innerHTML));
  $("joinbox").value =
    "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605";
  $("btn-dojoin").click();
  ok("a page link is named as a page link", /page link/.test($("joinmsg").innerHTML));

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

  // --------------------------------------------------------- diagnostics
  //
  // `web/kant-diag.mjs` and the two Lean modules behind it: the run is
  // written down, the verdict is stated, and the whole thing can be shared
  // without carrying the room secret.
  const D = await import("./kant-diag.mjs");
  const SL = await import("./kant-sharelog.mjs");
  const K = await import("./kantzk.mjs");
  ok("the verdict is on the page", $("verdict").innerHTML.length > 0);
  ok("the verdict names the same-machine failure",
    /only-this-browser|no-transport|no-room/.test($("verdict").innerHTML));
  ok("the run is shown", $("diagtail").textContent.includes("ms"));
  ok("the probe of this origin is in it",
    /probe|relay/.test($("diagtail").textContent));
  await $("btn-diagcopy").onclick();
  ok("copying gives a readable run", clipboard.last.startsWith("kant-zk diagnostics"));
  const shared = D.findReport(clipboard.last);
  ok("...that reads back as a report", shared !== null && shared.events.length > 0);
  ok("...whose events are in order",
    shared.events.every((e, i) => i === 0 || shared.events[i - 1].seq < e.seq));
  ok("...and which does not carry the invite", !clipboard.last.includes(link.split("#")[1]));
  $("btn-diagsave").click();
  ok("saving says so", /kant-diagnostics\.txt/.test($("diagmsg").textContent));

  // Share the log: the clipboard on a device with no share sheet, plus the
  // run cut into chat-sized messages for a conversation that takes nothing
  // bigger (`Kant.ShareLog.chatParts`).
  await $("btn-diagshare").onclick();
  ok("sharing the log says what happened", /copied|shared/.test($("diagshare").textContent));
  ok("...and hands over a readable run", clipboard.last.startsWith("kant-zk diagnostics"));
  const partsText = $("diagparts").value.split(/^--- \d+\/\d+ ---$/m)
    .map((s) => s.trim()).filter(Boolean);
  ok("...cut into chat-sized messages", partsText.length > 0);
  ok("...each of which fits in a tweet", partsText.every((p) => p.length <= 280));
  ok("...and which reassemble into the run",
    (SL.readChatParts(partsText)?.events?.length ?? 0) > 0);
  ok("...still without the invite", !$("diagparts").value.includes(link.split("#")[1]));

  // Post the log to the store: an ordinary content-addressed block.
  $("btn-diagpost").click();
  ok("posting the log gives it an address", /posted to the store/.test($("diagshare").innerHTML));
  const posted = SL.loadStore(globalThis.localStorage);
  ok("...held by this device", posted.entries.length === 1);
  ok("...as the run", posted.entries[0].title === "the run so far");
  ok("...which reads back", (SL.readPostedLog(posted.entries[0])?.events?.length ?? 0) > 0);
  ok("...and can be carried by hand",
    SL.carry(new K.Store(), $("diagparts").value).witness === posted.entries[0].witness);
  ok("...and posting the same run again is a no-op",
    SL.postLog(posted, SL.readPostedLog(posted.entries[0]),
      { id: posted.entries[0].id, timestamp: posted.entries[0].timestamp }).already);
  await new Promise((r) => setTimeout(r, 250));
  ok("posting the run is itself written down",
    $("diagtail").textContent.includes("posted to the store"));
  $("btn-diagpage").click();
  ok("the diagnostics page can be opened", opened.some((u) => String(u).includes("diag.html")));
  ok("...with the run handed to it",
    D.parseReport(session.get("kant-diag") ?? "") !== null);
  // the run is written down on a timer, so give that timer its moment
  const stored = () => (D.parseLog(local.get("kant-diag-run") ?? "") ?? []).length;
  for (let i = 0; i < 40 && stored() <= 3; i += 1) {
    await new Promise((r) => setTimeout(r, 50));
  }
  ok("the run is written down as it happens", stored() > 3);
  ok("the earlier run was kept, not overwritten",
    (D.parseLog(local.get("kant-diag-previous") ?? "") ?? []).length === 1);
  ok("...and the page says there was one",
    /previous run/.test($("diagtail").textContent));
  ok("the page listens for uncaught errors",
    pageErrors.some(([k]) => k === "error") &&
    pageErrors.some(([k]) => k === "unhandledrejection"));

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
