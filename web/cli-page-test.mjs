// The page, opened at the link a command-line agent printed.
//
//   node web/cli-page-test.mjs
//
// A terminal client opens a room on a real relay and says something.  Its
// link — the static page, with the room after the `#` — is then handed to
// `web/index.html` itself, running in a hand-rolled DOM, exactly as if it had
// been pasted into a browser's address bar from a chat window.  The page must
// load the URL, land in the same room, show the same line, and be heard back
// by the terminal.
//
// This is the "the same on the command line as in the browser" claim, checked
// against the page the site actually serves.

import { spawn, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, unlinkSync, mkdtempSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };
const eq = (name, got, want) =>
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`,
    JSON.stringify(got) === JSON.stringify(want));

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const CLI = join(root, "scripts", "kant-cli.mjs");
const html = readFileSync(join(here, "index.html"), "utf8");

// ------------------------------------------------------------- the relay

// Its own pass database. The relay's `passDb` defaults to
// /var/lib/kant-zk/passes.sqlite, so spawning it without `--pass-db` made this
// suite append its lines to a live relay's rate-limit ledger — three rows a run.
// Passing it explicitly also stops the relay falling back to a shared tmpdir
// copy if the path is unusable.
const passDb = join(tmpdir(), `kant-cli-page-test-${process.pid}.sqlite`);
function startRelay(port) {
  const proc = spawn(process.execPath,
    [join(root, "server", "relay.mjs"), "--port", String(port), "--static", here,
      "--pass-db", passDb],
    { stdio: ["ignore", "pipe", "pipe"] });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("relay did not start")), 8000);
    proc.stdout.on("data", (d) => {
      if (String(d).includes("listening")) { clearTimeout(timer); resolve(proc); }
    });
    proc.on("error", reject);
  });
}

const port = 9101 + Math.floor(Math.random() * 90);
const relay = await startRelay(port);
const base = `http://127.0.0.1:${port}`;
const origin = `${base}/`;
const dir = mkdtempSync(join(tmpdir(), "kant-page-"));

// -------------------------------------------------- the terminal client

const cli = (args) => {
  const out = spawnSync("node",
    [CLI, "--state", join(dir, "agent.json"), "--origin", origin, "--json", ...args],
    { encoding: "utf8", cwd: root });
  if (out.status !== 0) throw new Error(`cli ${args[0]} failed: ${out.stderr}`);
  return JSON.parse(out.stdout);
};

const opened = cli(["open", "--relay", base, "--name", "agent-term"]);
ok("the terminal agent opened a room", opened.ok === true);
cli(["say", "hello from the terminal"]);

const link = opened.link;
ok("its link is the static page with the room after the hash",
  link.startsWith(`${origin}#`));

// --------------------------------------------------------- a tiny DOM

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
   *  `box.querySelectorAll("a[data-q]")` and `box.querySelectorAll("a[data-f]")`
   *  (web/index.html), so the shim has to answer that or renderFiles throws
   *  before the test can assert anything — which it did, silently, on a click
   *  that reached renderFiles at all.
   *
   *  Returns El stubs carrying the matched attributes, so `.dataset` and
   *  `.onclick` in the page behave as they do in a browser.  Descends into
   *  children too, since a real querySelectorAll is not depth-limited.
   *
   *  Ported from web/page-test.mjs, whose shim had the same gap and had it
   *  fixed; this suite is a second copy of that shim, and the two had drifted. */
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

globalThis.document = {
  body: new El("", "body"),
  getElementById: (id) => elements.get(id) ?? null,
  createElement: (tag) => new El("", tag),
  execCommand: () => true,
};
// The browser is pointed at the link the terminal printed: same origin, and
// the room in the fragment.  Nothing after the `#` is ever sent to the host.
globalThis.location = {
  origin: base,
  pathname: "/",
  protocol: "http:",
  hash: link.slice(link.indexOf("#")),
  href: link,
};
Object.defineProperty(globalThis, "navigator", {
  configurable: true,
  value: { clipboard: { writeText: async () => {} } },
});
globalThis.window = {
  speechSynthesis: null,
  addEventListener: () => {},
  open: () => null,
};
const local = new Map();
globalThis.localStorage = {
  getItem: (k) => (local.has(k) ? local.get(k) : null),
  setItem: (k, v) => local.set(k, v),
};
const sess = new Map();
globalThis.sessionStorage = {
  getItem: (k) => (sess.has(k) ? sess.get(k) : null),
  setItem: (k, v) => sess.set(k, v),
};
globalThis.Blob = class { constructor(parts) { this.parts = parts; } };
globalThis.URL = globalThis.URL ?? {};
globalThis.requestAnimationFrame = () => 0;
globalThis.SpeechSynthesisUtterance = class { constructor(t) { this.text = t; } };

// The page's own fetch: `kant.config` off the disk, everything else against
// the real relay.  Long polls are shortened so the test does not sit waiting.
const CONFIG_TEXT = readFileSync(join(here, "kant.config"), "utf8");
const realFetch = globalThis.fetch.bind(globalThis);
const seen = [];
globalThis.fetch = async (url, init) => {
  const u = String(url);
  if (u.endsWith("kant.config")) return { ok: true, text: async () => CONFIG_TEXT };
  const trimmed = u.replace(/([?&])wait=\d+/, "$1wait=0");
  seen.push(trimmed);
  return realFetch(trimmed, init);
};

// --------------------------------------------------------- run the page

const scratch = join(here, ".cli-page-under-test.mjs");
writeFileSync(scratch, /<script type="module">([\s\S]*?)<\/script>/.exec(html)[1]);
let status = 0;
try {
  await import("./.cli-page-under-test.mjs");
  await new Promise((r) => setTimeout(r, 400));

  ok("the page loaded the URL and walked into the room", $("s-chat").shown);
  ok("the page says which room it joined", /joined room/.test($("joinmsg").textContent));
  ok("the page shows the terminal's line",
    $("chat").innerHTML.includes("hello from the terminal"));
  ok("the page is using the relay from the link",
    $("chatstatus").textContent.includes(base));
  ok("the page really talked to the relay",
    seen.some((u) => u.startsWith(`${base}/room/`)));
  ok("the room never appears in a path the static host is asked for",
    !seen.some((u) => u === origin || u === base));

  // The page answers, and the terminal hears it.
  $("say").value = "hello from the browser";
  await $("btn-send").onclick();
  const read = cli(["read"]);
  const texts = read.view.map((m) => m.text);
  eq("the terminal hears the browser",
    texts, ["hello from the terminal", "hello from the browser"]);

  // Both sides display the same conversation.
  //
  // The transcript is rendered by `lineHtml` in web/kant-pretty.mjs: each line is
  // `<div class="line...">` wrapping `<span class="who">`, `<span class="at">` and
  // `<span class="body">`, the last holding markup (`<span class="ktext">` for a
  // code span), so the tags have to be stripped rather than read as plain text.
  //
  // This used to be read with /<div[^>]*>[^:]*: ([^<]*)<\/div>/, a pattern for the
  // old flat "name: text" markup. After the pretty-printing rewrite it matched
  // nothing, so the comparison reported `[]` and failed for a reason that had
  // nothing to do with the page and the terminal disagreeing.
  const stripTags = (html) => html.replace(/<[^>]*>/g, "");
  const shown = $("chat").innerHTML
    .split(/<div class="line/)
    .slice(1)
    .map((chunk) => {
      const m = /<span class="body">([\s\S]*?)<\/span><\/div>/.exec(chunk);
      return m ? stripTags(m[1]) : undefined;
    });

  // Order is compared as a multiset, not positionally, because the two sides
  // do not promise the same order and one of them says so. The terminal's
  // `read` walks the store in arrival order; the page reads `viewByDay()`, and
  // web/index.html states that an untimed line "still shows, sorted last and
  // marked, rather than vanishing". `kant-cli.mjs say` sends no clock, so the
  // terminal's own line is untimed and the page puts it last — the documented
  // behaviour, not a disagreement. What must hold is that the page shows every
  // message the terminal shows, and nothing it does not.
  eq("the page shows every message the terminal shows",
    [...shown].sort(), [...texts].sort());
  ok("the page shows nothing the terminal does not", shown.length === texts.length,
    `page ${shown.length} vs terminal ${texts.length}`);
} catch (e) {
  ok(`the page ran without throwing (${e.message})`, false);
} finally {
  try { unlinkSync(scratch); } catch { /* already gone */ }
  relay.kill();
  // The relay holds the handle, so its database goes after the kill.
  for (const s of ["", "-wal", "-shm"]) rmSync(`${passDb}${s}`, { force: true });
  rmSync(dir, { recursive: true, force: true });
}

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  status = 1;
}
// The page keeps a polling loop running; nothing else is left to do.
process.exit(status);
