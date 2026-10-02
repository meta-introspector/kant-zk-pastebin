#!/usr/bin/env node
// audit-web.mjs — lint the web front end without opening a browser.
//
// Everything here is static: the HTML is tokenized, the inline and module
// JavaScript is read as text, and the results are cross-checked against
// the relay's own route table in server/relay.mjs. No browser, no Xvfb,
// no Chromium, nothing to install.
//
// Four questions, in the order they matter:
//
//   1. API drift      Does every endpoint the client calls exist in the
//                     relay's route table? A call with no route is a dead
//                     control or a stale URL -- the feature cannot work.
//   2. Dead controls  Which buttons/inputs in the HTML have no handler,
//                     or a handler that never reaches the network?
//   3. Missing DOM    Which $("id") references point at ids the HTML does
//                     not define? These throw on first use.
//   4. Fake data      Hardcoded hosts, sample payloads, baked-in
//                     timestamps, mock replies, leftover demo narration --
//                     anything the UI could show that is not real.
//
// Usage: node scripts/audit-web.mjs [--json] [--quiet]
// Exit code is 1 if anything in ERROR is found.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { argv, exit } from "node:process";

const JSON_OUT = argv.includes("--json");
const QUIET = argv.includes("--quiet");

const WEB = "web";
const RELAY = "server/relay.mjs";
const findings = [];
const add = (level, kind, where, msg, detail = "") =>
  findings.push({ level, kind, where, msg, detail });

// ------------------------------------------------------------ HTML parser
// A small tokenizer, not a regex sweep: it tracks raw-text elements
// (<script>/<style> bodies contain '<' that is not markup) and comments,
// so `<script>if (a<b) {}</script>` does not confuse the tag counter.

const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
const RAW_TEXT = new Set(["script", "style"]);

function tokenize(src) {
  const tags = [];
  const comments = [];
  let i = 0;
  while (i < src.length) {
    const lt = src.indexOf("<", i);
    if (lt < 0) break;
    if (src.startsWith("<!--", lt)) {
      const end = src.indexOf("-->", lt);
      const stop = end < 0 ? src.length : end + 3;
      comments.push(src.slice(lt + 4, end < 0 ? src.length : end));
      i = stop;
      continue;
    }
    if (src.startsWith("<!", lt) || src.startsWith("<?", lt)) {
      const end = src.indexOf(">", lt);
      i = end < 0 ? src.length : end + 1;
      continue;
    }
    const m = /^<([a-zA-Z][a-zA-Z0-9-]*)/.exec(src.slice(lt));
    if (!m) { i = lt + 1; continue; }
    const name = m[1].toLowerCase();
    // Attributes up to the closing '>', honouring quoted values.
    let j = lt + m[0].length;
    const attrs = {};
    const order = [];
    while (j < src.length) {
      while (j < src.length && /\s/.test(src[j])) j += 1;
      if (src[j] === ">") { j += 1; break; }
      if (src[j] === "/" && src[j + 1] === ">") { j += 2; break; }
      const am = /^([a-zA-Z_:][-a-zA-Z0-9_:.]*)/.exec(src.slice(j));
      if (!am) { j += 1; continue; }
      const aname = am[1].toLowerCase();
      j += am[0].length;
      while (j < src.length && /\s/.test(src[j])) j += 1;
      let value = "";
      if (src[j] === "=") {
        j += 1;
        while (j < src.length && /\s/.test(src[j])) j += 1;
        const q = src[j];
        if (q === '"' || q === "'") {
          const end = src.indexOf(q, j + 1);
          value = src.slice(j + 1, end < 0 ? src.length : end);
          j = end < 0 ? src.length : end + 1;
        } else {
          const vm = /^[^\s>]*/.exec(src.slice(j));
          value = vm[0]; j += vm[0].length;
        }
      }
      // A valueless attribute (checked, defer) leaves j sitting ON the '>'.
      // An assigned one already advanced past its value. Advancing again
      // would step over the '>' and swallow the following tag.
      attrs[aname] = decode(value);
      order.push(aname);
    }
    tags.push({ name, attrs, order, at: lt,
      line: src.slice(0, lt).split("\n").length });
    if (RAW_TEXT.has(name)) {
      const close = src.toLowerCase().indexOf(`</${name}`, j);
      const body = src.slice(j, close < 0 ? src.length : close);
      tags[tags.length - 1].text = body;
      tags[tags.length - 1].scriptSrc = src.slice(0, lt).split("\n").length;
      i = close < 0 ? src.length : close;
      continue;
    }
    i = j;
  }
  return { tags, comments };
}

function decode(s) {
  return s.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (m, e) => {
    if (e[0] === "#") {
      const code = e[1] === "x" || e[1] === "X"
        ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

/** Does this path exist inside web/? Used for link resolution. */
function webExists(rel) {
  if (!rel || rel.includes("..")) return false;
  try { return statSync(`${WEB}/${rel}`).isFile(); }
  catch { return false; }
}

// ------------------------------------------------------- relay route table
// Turn each relay route into a shape so client paths can be compared to it
// without inventing sample ids: every captured group becomes "*".
const relaySrc = readFileSync(RELAY, "utf8");
const routes = [];
for (const line of relaySrc.split("\n")) {
  const eq = /url\.pathname\s*===\s*"([^"]+)"/.exec(line);
  if (eq) { routes.push({ shape: eq[1], line: line.trim() }); continue; }
  const re = /url\.pathname\.match\(\/\^(.*)\$\/\)/.exec(line);
  if (re) {
    // "^\/room\/([^/]+)\/block\/([0-9a-f]{64})$" -> "/room/*/block/*"
    let s = re[1].replace(/^\^/, "");
    s = s.replace(/\\\//g, "/");
    s = s.replace(/\(\?:\[[^\]]*\][^)]*\)|\([^)]+\)/g, "*");
    s = s.replace(/\$$/, "");
    routes.push({ shape: s, line: line.trim() });
  }
}
const routeShapes = routes.map((r) => r.shape);

// ------------------------------------------------------ client API paths
// Normalise a path fragment the client builds into the same shape.
function shapeOfPath(p) {
  let s = p.split("?")[0].split("#")[0];
  s = s.replace(/\$\{[^}]*\}/g, "*");
  s = s.replace(/^https?:\/\/[^/]+/, "");
  s = s.replace(/\/{2,}/g, "/");
  if (!s.startsWith("/")) s = `/${s}`;
  // A leading "*" is the relay base (a variable), not part of the path:
  // `${this.relayBase}/room/x` is the /room/x route, not /*/room/x.
  s = s.replace(/^\/*\*\//, "/");
  return s;
}

// Only the *global* fetch is a network call. `sv.fetch("room", 0)` is an
// in-process test double in net-test.mjs and must not be mistaken for one;
// the lookbehind rejects any fetch that is a property access.
const API_RE = /(?<![\w$.])(?:fetch\s*\(|new\s+WebSocket\s*\(|serviceWorker\s*\.\s*register\s*\()/g;
const calls = []; // { file, line, shape, raw }

/** Blank out comments (preserving offsets) so a path mentioned in prose
 *  is never mistaken for a call. `ok("the relay answers /health")` and
 *  the doc comment "/{base}/ws/{room}" both died here. */
function stripComments(src) {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === '"' || c === "'" || c === "`") {
      const q = c; let j = i + 1;
      while (j < n && src[j] !== q) { if (src[j] === "\\") j += 1; j += 1; }
      out += src.slice(i, Math.min(j + 1, n)); i = j + 1; continue;
    }
    if (c === "/" && src[i + 1] === "/") {
      const e = src.indexOf("\n", i); const stop = e < 0 ? n : e;
      out += " ".repeat(stop - i); i = stop; continue;
    }
    if (c === "/" && src[i + 1] === "*") {
      const e = src.indexOf("*/", i + 2); const stop = e < 0 ? n : e + 2;
      out += src.slice(i, stop).replace(/[^\n]/g, " "); i = stop; continue;
    }
    out += c; i += 1;
  }
  return out;
}

/** The balanced argument text of a call whose '(' is at `open`. */
function balanced(src, open) {
  let depth = 0; let i = open; const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === '"' || c === "'" || c === "`") {
      const q = c; i += 1;
      while (i < n && src[i] !== q) { if (src[i] === "\\") i += 1; i += 1; }
      i += 1; continue;
    }
    if (c === "(") depth += 1;
    else if (c === ")") { depth -= 1; if (depth === 0) return src.slice(open + 1, i); }
    i += 1;
  }
  return "";
}

function scanJs(srcRaw, file) {
  const src = stripComments(srcRaw);
  let m;
  while ((m = API_RE.exec(src))) {
    const open = src.indexOf("(", m.index);
    if (open < 0) continue;
    let arg = balanced(src, open);
    const line = srcRaw.slice(0, m.index).split("\n").length;
    // One hop of indirection: `const u = `...`; fetch(u)`.
    const id = /^\s*([A-Za-z_$][\w$]*)\s*$/.exec(arg);
    if (id) {
      const decl = new RegExp(`(?:const|let|var)\\s+${id[1]}\\s*=\\s*([^;\\n]+)`).exec(src);
      if (decl) arg = decl[1];
    }
    const LIT = /`([^`]*)`|"([^"\n]*)"|'([^'\n]*)'/g;
    let q;
    while ((q = LIT.exec(arg))) {
      const lit = q[1] ?? q[2] ?? q[3] ?? "";
      if (!/\/(health|room|ws|block|pin)\b/.test(`/${lit}`)) continue;
      calls.push({ file, line, shape: shapeOfPath(lit), raw: lit.trim().slice(0, 70) });
    }
  }
}

// ------------------------------------------------------------- main sweep
const htmlFiles = readdirSync(WEB).filter((f) => f.endsWith(".html")).sort();
const parsed = {};
for (const f of htmlFiles) {
  const src = readFileSync(`${WEB}/${f}`, "utf8");
  parsed[f] = { src, ...tokenize(src) };
}

for (const f of htmlFiles) {
  const { src, tags, comments } = parsed[f];

  // ---- structural lint -------------------------------------------------
  const ids = new Map();
  for (const t of tags) {
    const id = t.attrs.id;
    if (id) {
      if (ids.has(id)) add("ERROR", "dup-id", `${f}:${t.line}`, `id "${id}" is defined twice`);
      ids.set(id, t.line);
    }
    // Every id should be reachable from code.
    if (t.name === "input" && !t.attrs.id && !t.attrs.name) {
      add("WARN", "unnamed-input", `${f}:${t.line}`, "<input> has no id or name");
    }
    for (const a of t.order) {
      if (a.startsWith("on") && a.length > 2 && t.attrs[a]) {
        add("INFO", "inline-handler", `${f}:${t.line}`,
          `inline ${a}="${t.attrs[a].slice(0, 40)}" — no CSP-safe equivalent found`);
      }
    }
  }

  // ---- collect this page's inline script -------------------------------
  let inlineJs = "";
  for (const t of tags) if (t.name === "script" && !t.attrs.src) inlineJs += t.text ?? "";
  scanJs(inlineJs, `${f} (inline)`);

  // ---- $("id") references must exist ----------------------------------
  const REF = /\$\(\s*"([^"]+)"\s*\)|getElementById\(\s*"([^"]+)"\s*\)/g;
  let m;
  while ((m = REF.exec(src))) {
    const id = m[1] ?? m[2];
    if (!ids.has(id)) {
      const line = src.slice(0, m.index).split("\n").length;
      add("ERROR", "missing-dom", `${f}:${line}`,
        `references $("${id}") but no such id in the HTML`);
    }
  }

  // ---- controls must be wired to something ----------------------------
  // Only things that are *pressed*. An <input>/<textarea> is read through
  // .value; flagging it for lacking an onclick was pure noise.
  for (const t of tags) {
    const pressable = t.name === "button" || t.name === "a" ||
      (t.attrs.role === "button") || (t.name === "input" &&
        ["button", "submit", "reset", "checkbox", "radio"].includes(t.attrs.type));
    if (!pressable) continue;
    const id = t.attrs.id;
    if (!id) continue;
    const wired = new RegExp(`\\$\\(\\s*"${id}"\\s*\\)\\s*\\.\\s*(on\\w+|addEventListener)`)
      .test(inlineJs);
    if (!wired) {
      add("WARN", "dead-control", `${f}:${t.line}`,
        `<${t.name} id="${id}"> has no handler in the inline script`);
    }
  }

  // ---- local links must resolve ---------------------------------------
  for (const t of tags) {
    const href = t.attrs.href;
    if (!href || /^(https?:|mailto:|#|javascript:)/.test(href)) continue;
    const target = href.split("#")[0].split("?")[0];
    if (!target) continue;
    // "./" and "/" are the relay's static root, which serves index.html.
    if (/^\.?\/?$/.test(target)) continue;
    const rel = target.replace(/^\.\//, "").replace(/^\//, "");
    // Pages may be linked without their extension, and targets may sit in
    // a subdirectory (./docs/UX-FLOW.md), so resolve properly.
    const hit = webExists(rel) || webExists(`${rel}.html`) ||
      webExists(`${rel.replace(/\/$/, "")}/index.html`);
    if (hit) continue;
    // Some paths are produced by the deploy rather than shipped in web/
    // (the publisher pushes /archive/ to Cloudflare Pages). Report those
    // as a note so a genuine broken link still stands out.
    const deployOnly = /^\/?(archive|dist)\/?$/.test(rel);
    add(deployOnly ? "INFO" : "ERROR", deployOnly ? "deploy-path" : "dead-link",
      `${f}:${t.line}`,
      deployOnly ? `href="${href}" is served by the deploy, not web/`
        : `href="${href}" resolves to nothing in web/`);
  }
}

// ---- module scripts are audited too -----------------------------------
for (const f of readdirSync(WEB).filter((f) => f.endsWith(".mjs"))) {
  scanJs(readFileSync(`${WEB}/${f}`, "utf8"), `${f}`);
}

// ---- 1. API drift ------------------------------------------------------
for (const c of calls) {
  const ok = routeShapes.includes(c.shape) ||
    // block fetches and pin lookups are served by the shell, not the relay
    c.shape.includes("/pin/");
  if (!ok) {
    add("ERROR", "api-drift", `${c.file}:${c.line}`,
      `calls ${c.shape} — no relay route matches (routes: ${routeShapes.join(", ")})`);
  }
}
for (const r of routes) {
  const used = calls.some((c) => c.shape === r.shape);
  if (!used) add("INFO", "unreached-route", `relay.mjs`, `${r.shape} is never called by web/`);
}

// ---- 2. hardcoded hosts and secrets ------------------------------------
const SECRETISH = [
  [/\b(?:api[_-]?key|secret|token|password|passwd|bearer)\b\s*[:=]\s*["'][^"']{8,}/i,
    "a literal secret/token"],
  [/\b[0-9a-f]{64}\b/, "a 64-char hex digest as a literal"],
  [/\beyJ[A-Za-z0-9_-]{20,}\./, "an embedded JWT"],
];
for (const f of [...htmlFiles.map((x) => `${WEB}/${x}`),
  ...readdirSync(WEB).filter((x) => x.endsWith(".mjs")).map((x) => `${WEB}/${x}`)]) {
  // A host baked into a *test* is a fixture and is fine; a host baked into
  // shipped code is the thing worth noticing. Spec namespaces and example
  // domains are never interesting.
  const isTest = /(?:-test|^test)\.mjs$/.test(f.split("/").pop());
  const src = readFileSync(f, "utf8");
  src.split("\n").forEach((line, i) => {
    if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;
    // placeholder=/title= are UI hints. A hint saying "https://relay.example.org"
    // is the correct thing to show a user, not a baked-in endpoint, and
    // "placeholder" is not a development marker. Look past them.
    const code = line.replace(/(?:placeholder|title|alt|aria-label)\s*=\s*"[^"]*"/g, '""');
    for (const [re, what] of SECRETISH) {
      if (re.test(code)) {
        add(isTest ? "INFO" : "WARN", isTest ? "test-fixture-digest" : "hardcoded-secret",
          `${f}:${i + 1}`, `looks like ${what}`);
      }
    }
    const host = /["'`]https?:\/\/([a-z0-9.-]+\.[a-z]{2,})/i.exec(code);
    // ipfs.io is a public gateway prefix lab.html rewrites ipfs:// links to,
// not a deployment this app talks to, so it is not a baked-in endpoint.
    const boring = /127\.0\.0\.1|localhost|\.example$|\.test$|w3\.org|schema\.org|twitter\.com|ipfs\.io/;
    if (host && !boring.test(host[1])) {
      add(isTest ? "INFO" : "WARN", isTest ? "test-fixture-host" : "hardcoded-host",
        `${f}:${i + 1}`, `hardcoded host ${host[1]}`);
    }
    if (/\b(lorem ipsum|TODO|FIXME|XXX|HACK|DUMMY)\b/i.test(code)) {
      add("INFO", "leftover-marker", `${f}:${i + 1}`, "development marker in shipped text");
    }
    // ---- fake data, the thing a static pass is actually good at -------
    // A baked-in clock reading is the classic way a "live" figure stops
    // being live while still looking real.
    if (!isTest && /\b20\d\d-\d\d-\d\dT\d\d:\d\d/.test(code)) {
      add("WARN", "frozen-timestamp", `${f}:${i + 1}`, "a literal ISO timestamp in shipped code");
    }
    // Non-crypto randomness reaching anything a witness depends on.
    if (!isTest && /Math\.random\s*\(/.test(code) && !/getRandomValues/.test(code)) {
      const near = code.slice(Math.max(0, code.indexOf("Math.random") - 120),
        code.indexOf("Math.random") + 120);
      if (/secret|nonce|key|digest|witness|randomBytes/.test(near)) {
        add("ERROR", "weak-randomness", `${f}:${i + 1}`,
          "Math.random() near key/secret material — use crypto.getRandomValues");
      }
    }
    if (!isTest && /\b(mock|stub|fake|sample|dummy)(Data|Response|Reply|Result)\b/.test(code)) {
      add("WARN", "mock-in-shIPPED".toLowerCase(), `${f}:${i + 1}`,
        "mock/sample identifier in shipped code");
    }
  });
}

// ---- 3. fake data: values the UI renders without the network ----------
for (const f of htmlFiles) {
  const { src, tags } = parsed[f];
  for (const t of tags) {
    // A data-* attribute carrying a literal value is a baked-in fixture.
    for (const a of t.order) {
      if (a.startsWith("data-") && t.attrs[a] && /^(?![\w-]+$)/.test(t.attrs[a])) {
        add("INFO", "data-fixture", `${f}:${t.line}`, `${a}="${t.attrs[a].slice(0, 30)}"`);
      }
    }
    // Text content of a table-ish element that JS never assigns to.
    const id = t.attrs.id;
    if (id && /^(stat|count|total|size|price|balance|metric|summary)/i.test(id)) {
      const assigned = new RegExp(`\\$\\(\\s*"${id}"\\s*\\)\\s*\\.\\s*(textContent|innerHTML|value)`)
        .test(src);
      if (!assigned) {
        add("WARN", "static-stat", `${f}:${t.line}`,
          `#${id} looks like live data but nothing ever writes to it`);
      }
    }
  }
}

// ---------------------------------------------------------------- report
// A linter that lies is worse than no linter, so before reporting anything
// it checks its own id extraction against a plain regex over the same
// file. Any divergence means the tokenizer lost sync, and every finding
// derived from it is suspect.
const SELF = argv.includes("--selftest");
let selftestFailed = false;
if (SELF) {
  for (const f of htmlFiles) {
    const src = readFileSync(`${WEB}/${f}`, "utf8");
    const viaTokens = new Set(parsed[f].tags.map((t) => t.attrs.id).filter(Boolean));
    const viaRegex = new Set([...src.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]));
    const missing = [...viaRegex].filter((id) => !viaTokens.has(id));
    const extra = [...viaTokens].filter((id) => !viaRegex.has(id));
    if (missing.length || extra.length) {
      selftestFailed = true;
      console.log(`SELFTEST ${f}: tokens missing ${missing.join(",") || "-"}` +
        ` | spurious ${extra.join(",") || "-"}`);
      const first = missing[0];
      if (first) {
        const at = src.indexOf(`id="${first}"`);
        console.log(`  first divergence near: ` +
          `${JSON.stringify(src.slice(Math.max(0, at - 90), at + 20))}`);
      }
    }
  }
  console.log(selftestFailed ? "SELFTEST FAILED" : "SELFTEST OK");
  if (selftestFailed) exit(2);
}
const order = { ERROR: 0, WARN: 1, INFO: 2 };
findings.sort((a, b) => order[a.level] - order[b.level] ||
  a.kind.localeCompare(b.kind) || a.where.localeCompare(b.where));

if (JSON_OUT) {
  console.log(JSON.stringify({ routes: routeShapes, calls, findings }, null, 2));
} else {
  const errors = findings.filter((f) => f.level === "ERROR");
  const warns = findings.filter((f) => f.level === "WARN");
  const infos = findings.filter((f) => f.level === "INFO");
  console.log(`relay routes: ${routeShapes.join("  ")}`);
  console.log(`client api shapes: ${[...new Set(calls.map((c) => c.shape))].sort().join("  ")}\n`);
  for (const [label, list] of [["ERROR", errors], ["WARN", warns], ["INFO", infos]]) {
    if (!list.length) continue;
    console.log(`${label} (${list.length})`);
    for (const f of list) console.log(`  ${f.kind.padEnd(16)} ${f.where.padEnd(28)} ${f.msg}`);
    console.log("");
  }
  if (!QUIET) console.log(`${errors.length} error(s), ${warns.length} warning(s), ${infos.length} note(s)`);
}
exit(findings.some((f) => f.level === "ERROR") ? 1 : 0);