// Drives addRow() from web/p2p.html in a hand-rolled DOM.
//
// Every field of an artifact record (name, cid, size) comes from another
// peer's room line, so addRow must render it as text. The shim below never
// parses HTML: any write to innerHTML/outerHTML/insertAdjacentHTML is recorded
// as a markup sink, and the test fails if a record value reaches one.
// The payloads are inert strings; nothing is sent anywhere.
//
//   node web/p2p-page-test.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };
const eq = (name, got, want) =>
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, "p2p.html"), "utf8");

// ------------------------------------------------------------- a tiny DOM

const markupSinks = [];   // every string handed to an HTML-parsing API
const created = [];       // every element tag the page created

class Text {
  constructor(data) { this.data = String(data); }
  get textContent() { return this.data; }
}

class El {
  constructor(tag = "div", id = "") {
    this.tagName = tag.toUpperCase();
    this.id = id;
    this.childNodes = [];
    this.dataset = {};
    this.value = "";
    this.href = "";
    this.onclick = null;
  }
  get children() { return this.childNodes.filter((n) => n instanceof El); }
  get textContent() { return this.childNodes.map((n) => n.textContent).join(""); }
  set textContent(v) { this.childNodes = [new Text(v)]; }
  set innerHTML(v) { markupSinks.push(String(v)); }
  get innerHTML() { return ""; }
  set outerHTML(v) { markupSinks.push(String(v)); }
  insertAdjacentHTML(_, v) { markupSinks.push(String(v)); }
  static node(n) { return n instanceof El || n instanceof Text ? n : new Text(n); }
  append(...ns) { this.childNodes.push(...ns.map(El.node)); }
  appendChild(n) { this.childNodes.push(n); return n; }
  prepend(...ns) { this.childNodes.unshift(...ns.map(El.node)); }
  querySelector(sel) {
    // only what addRow's own lookups need: a tag name
    const walk = (el) => {
      for (const c of el.children) {
        if (c.tagName === sel.toUpperCase()) return c;
        const hit = walk(c);
        if (hit) return hit;
      }
      return null;
    };
    return walk(this);
  }
  click() { return this.onclick?.({ preventDefault() {} }); }
}

globalThis.document = {
  createElement: (tag) => { created.push(tag.toLowerCase()); return new El(tag); },
  createTextNode: (t) => new Text(t),
};

const arts = new El("table", "arts");
const tbody = new El("tbody");
arts.appendChild(tbody);
const text = new El("input", "text");
const byId = { arts, text };
const $ = (id) => byId[id];

// ------------------------------------------------------ the page's addRow

const start = html.indexOf("function addRow(rec) {");
ok("p2p.html defines addRow", start >= 0);
const end = html.indexOf("\n}\n", start);
const src = html.slice(start, end + 2);
const fetched = [], pinned = [];
const addRow = new Function("$", "doGet", "doPin", `${src}\nreturn addRow;`)(
  $, (r) => fetched.push(r), (r) => pinned.push(r));

// ------------------------------------------------------------- the checks

const NAME = `<img src=x onerror="window.pwned=1">&amp;<script>window.pwned=2</script>`;
const CID = `b"><img src=x onerror="window.pwned=3">`;
const SIZE = `<b onmouseover="window.pwned=4">9</b>`;
const rec = { tag: "kzcid", peer: "p", name: NAME, cid: CID, size: SIZE, pinned: false, b64: "" };

// The shim does not parse HTML, so a row built through innerHTML has no
// <a>/<button> to wire and addRow may throw; record that, then report the sink.
let thrown = null;
try { addRow(rec); } catch (e) { thrown = e; }

const payloadSink = markupSinks.find((s) => [NAME, CID, SIZE].some((p) => s.includes(p)) ||
  /onerror|<script|onmouseover/i.test(s));
ok(`no record value reaches an HTML-parsing sink (saw ${JSON.stringify(payloadSink)})`, !payloadSink);

ok(`addRow builds the row without throwing (${thrown?.message})`, !thrown);
if (thrown) report();  // the row was never built; the remaining checks are noise
eq("one row added", tbody.children.length, 1);
const tr = tbody.children[0];
const tds = tr?.children ?? [];
eq("five cells", tds.length, 5);
eq("name rendered verbatim as text", tds[0]?.textContent, NAME);
eq("size rendered verbatim as text", tds[2]?.textContent, SIZE);
eq("via column", tds[3]?.textContent, "room");
const link = tds[1]?.children[0];
eq("cid cell holds a link", link?.tagName, "A");
eq("link text is the cid prefix", link?.textContent, `${CID.slice(0, 16)}…`);
eq("link carries the cid as data, not markup", link?.dataset.cid, CID);
eq("row is keyed by cid", tr?.dataset.cid, CID);
eq("action cell text", tds[4]?.textContent, "fetch repin");
const [getB, pinB] = tds[4]?.children ?? [];
eq("fetch button", getB?.dataset.act, "get");
eq("repin button", pinB?.dataset.act, "pin");

const unexpected = created.filter((t) => !["tr", "td", "a", "button"].includes(t));
ok(`only tr/td/a/button elements are created (saw ${unexpected})`, unexpected.length === 0);

link?.click();
eq("clicking the cid copies it into the text box", text.value, CID);
getB?.click();
eq("fetch button fetches this record", fetched[0], rec);
pinB?.click();
eq("repin button repins this record", pinned[0], rec);

addRow({ ...rec });
eq("same cid is not added twice", tbody.children.length, 1);

addRow({ tag: "kzcid", cid: "bafkplain", pinned: true });
eq("missing name falls back to ?", tbody.children[0]?.children[0]?.textContent, "?");
eq("missing size falls back to ?", tbody.children[0]?.children[2]?.textContent, "?");
eq("pinned record shows ipfs", tbody.children[0]?.children[3]?.textContent, "ipfs");

ok("globalThis.pwned never set", globalThis.pwned === undefined);

function report() {
  if (!fail.length) {
    console.log(`p2p-page-test: ${checks} checks ok`);
    process.exit(0);
  }
  console.error(`p2p-page-test: ${fail.length} of ${checks} checks failed`);
  for (const f of fail) console.error(`  FAIL ${f}`);
  process.exit(1);
}
report();
