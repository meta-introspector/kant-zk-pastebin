#!/usr/bin/env node
// sneakernet.mjs — the static sneakernet server: a directory, not a service.
//
// There is no relay here and no protocol endpoint.  The tool keeps a
// local spool on disk, and renders it into a directory of *static files*
// that any host will serve: a bag you can paste, a link, a QR code, and
// a numbered thread for tweeting.  Copy the directory to a pages host, an
// object store, a pinned IPFS directory or a USB stick; whoever opens it
// pastes the bag and is caught up to the moment it was published.
//
// Everything the tool does mirrors `RequestProject/Kant/Uucp.lean`.
//
//   node scripts/sneakernet.mjs init      site --name alice [--room <hex>]
//   node scripts/sneakernet.mjs write     site "something to say"
//   node scripts/sneakernet.mjs paste     site <file|url|-|text>
//   node scripts/sneakernet.mjs publish   site [--base https://host/path/] [--config kant.config]
//   node scripts/sneakernet.mjs tweets    site [--carrier tweet]
//   node scripts/sneakernet.mjs status    site
//   node scripts/sneakernet.mjs serve     site [--port 8080]   (read-only files)

import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import { fileURLToPath } from "node:url";
import { utf8, witness, asciiBytes } from "../web/kantzk.mjs";
import { roomOf, printMsg, msgText } from "../web/kant-net.mjs";
import { qrEncode, qrSvg } from "../web/kant-qr.mjs";
import {
  SneakerNode, packBag, openBag, bagUrl, readBagUrl, thread, readThread,
  bagForCarrier, CARRIER_CAPACITY,
} from "../web/kant-uucp.mjs";
import * as SITE from "../web/kant-site.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STATE = "sneakernet.json";

const die = (msg) => { console.error(`sneakernet: ${msg}`); process.exit(1); };

function parseFlags(argv) {
  const flags = {}, rest = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) { flags[argv[i].slice(2)] = argv[i + 1]; i += 1; }
    else rest.push(argv[i]);
  }
  return { flags, rest };
}

const statePath = (dir) => path.join(dir, STATE);

/** The deployment configuration: `kant.config` unless another file is named. */
function siteConfig(file) {
  const candidates = file ? [file] : [path.join(HERE, "..", "web", "kant.config")];
  for (const c of candidates) {
    if (!fs.existsSync(c)) continue;
    const cfg = SITE.parseConfig(fs.readFileSync(c, "utf8"));
    if (cfg && SITE.configWf(cfg)) return { config: cfg, source: c };
    console.error(`sneakernet: ignoring ${c} (not a well-formed configuration)`);
  }
  return { config: { ...SITE.DEFAULT_CONFIG }, source: "built-in" };
}

function loadState(dir) {
  const p = statePath(dir);
  if (!fs.existsSync(p)) die(`no spool in ${dir}; run 'init' first`);
  const raw = JSON.parse(fs.readFileSync(p, "utf8"));
  const node = new SneakerNode(raw.name, openBag(raw.bag) ?? [], raw.clock ?? 0);
  return { node, room: raw.room, base: raw.base ?? "" };
}

function saveState(dir, { node, room, base }) {
  fs.writeFileSync(statePath(dir),
    JSON.stringify({ name: node.name, room, base, clock: node.clock, bag: node.bag() }, null, 2));
}

// ------------------------------------------------------------------ commands

function cmdInit(dir, flags) {
  const name = flags.name ?? "anon";
  const room = flags.room ?? roomOf(utf8(flags.secret ?? `sneakernet:${name}`));
  fs.mkdirSync(dir, { recursive: true });
  if (fs.existsSync(statePath(dir))) die(`${dir} already holds a spool`);
  saveState(dir, { node: SneakerNode.blank(name), room, base: flags.base ?? "" });
  console.log(`spool created in ${dir}\n  name ${name}\n  room ${room}`);
}

function cmdWrite(dir, text) {
  if (!text) die("nothing to write");
  const st = loadState(dir);
  const m = st.node.write(st.room, text);
  saveState(dir, st);
  console.log(`wrote line ${m.seq}; spool now holds ${st.node.spool.length}`);
}

function readInput(arg) {
  if (arg === "-") return fs.readFileSync(0, "utf8");
  if (arg && fs.existsSync(arg)) return fs.readFileSync(arg, "utf8");
  return arg ?? "";
}

function cmdPaste(dir, arg) {
  const st = loadState(dir);
  const text = readInput(arg).trim();
  if (!text) die("nothing to paste");
  // One bag, a link, or a whole thread of parts — all are accepted, and
  // anything that does not certify itself is refused as a whole.
  const asThread = text.includes("\n") ? readThread(text.split(/\n+/).map((l) => l.trim()).filter(Boolean)) : null;
  const candidates = [text, asThread].filter(Boolean);
  let added = 0, accepted = false;
  for (const c of candidates) {
    const r = st.node.paste(c);
    if (r.accepted) { accepted = true; added += r.added; break; }
  }
  if (!accepted) die("that code did not open: not a bag, or a line failed its witness");
  saveState(dir, st);
  console.log(`pasted; ${added} new line(s); spool now holds ${st.node.spool.length}`);
}

function cmdPublish(dir, flags) {
  const st = loadState(dir);
  const { config, source } = siteConfig(flags.config);
  // The origin comes from the configuration file unless --base overrides it,
  // so every code and link published here carries the whole URL.
  if (flags.base) st.base = flags.base;
  if (!st.base) st.base = config.origin;
  const bag = st.node.bag();
  const parts = bagForCarrier(bag, "tweet");
  const link = st.base ? bagUrl(st.base, st.node.spool) : "";

  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "bag.txt"), bag + "\n");
  fs.writeFileSync(path.join(dir, "thread.txt"), parts.join("\n") + "\n");
  if (link) fs.writeFileSync(path.join(dir, "link.txt"), link + "\n");

  // A QR code, when the bag is small enough for one; otherwise one per part.
  const qrDir = path.join(dir, "qr");
  fs.rmSync(qrDir, { recursive: true, force: true });
  fs.mkdirSync(qrDir, { recursive: true });
  const single = link && link.length <= CARRIER_CAPACITY.qr;
  const codes = single ? [link] : (bag.length <= CARRIER_CAPACITY.qr ? [bag] : parts);
  codes.forEach((code, i) => {
    try {
      fs.writeFileSync(path.join(qrDir, `bag-${String(i).padStart(3, "0")}.svg`),
        qrSvg(qrEncode(code), { scale: 4 }));
    } catch (e) { console.error(`  (no QR for part ${i}: ${e.message})`); }
  });

  // The share card: the same link, with the configured text and picture, in
  // one SVG that still carries the card itself (Kant.SiteCard.readCard_cardSvg).
  let card = null;
  if (link) {
    card = SITE.cardFor(config, link);
    try {
      fs.writeFileSync(path.join(dir, "card.svg"), SITE.renderCard(card, { scale: 6 }));
      fs.writeFileSync(path.join(dir, "card.txt"), SITE.chatText(card) + "\n");
      const logo = path.join(HERE, "..", "web", "kant-logo.svg");
      if (config.picture === "./kant-logo.svg" && fs.existsSync(logo)) {
        fs.copyFileSync(logo, path.join(dir, "kant-logo.svg"));
      }
    } catch (e) { console.error(`  (no share card: ${e.message})`); card = null; }
  }

  fs.writeFileSync(path.join(dir, "index.html"), page(st, bag, parts, link, card));
  saveState(dir, st);

  console.log(`published ${st.node.spool.length} line(s) to ${dir}`);
  console.log(`  bag.txt      ${bag.length} characters, digest ${witness(asciiBytes(bag)).slice(0, 16)}…`);
  console.log(`  thread.txt   ${parts.length} tweet-sized part(s)`);
  console.log(`  qr/          ${codes.length} code(s)`);
  if (link) console.log(`  link.txt     ${link.length} characters`);
  if (card) console.log(`  card.svg     the share card (text + picture), card.txt to paste in chat`);
  console.log(`  index.html   a page that reads itself back`);
  console.log(`  site         ${st.base} (from ${flags.base ? "--base" : source})`);
}

function cmdTweets(dir, flags) {
  const st = loadState(dir);
  const carrier = flags.carrier ?? "tweet";
  if (!(carrier in CARRIER_CAPACITY)) die(`unknown carrier ${carrier}`);
  const parts = bagForCarrier(st.node.bag(), carrier);
  parts.forEach((p, i) => console.log(`--- ${i + 1}/${parts.length} (${p.length} chars)\n${p}`));
}

function cmdStatus(dir) {
  const st = loadState(dir);
  const bag = st.node.bag();
  console.log(`name    ${st.node.name}`);
  console.log(`room    ${st.room}`);
  console.log(`lines   ${st.node.spool.length}`);
  console.log(`bag     ${bag.length} characters (${witness(asciiBytes(bag)).slice(0, 16)}…)`);
  console.log(`fits    dm:${bag.length <= CARRIER_CAPACITY.dm} qr:${bag.length <= CARRIER_CAPACITY.qr}` +
    ` tweet:${bag.length <= CARRIER_CAPACITY.tweet}`);
  for (const m of st.node.view()) console.log(`  ${m.seq} ${m.sender}: ${msgText(m)}`);
}

// A read-only file server, for looking at the directory locally.  It has
// no endpoints: every request is a file lookup, and nothing it receives
// can change what is on disk (`Kant.Uucp.Site.serve_static`).
function cmdServe(dir, flags) {
  const port = Number(flags.port ?? 8080);
  const root = path.resolve(dir);
  const types = { ".html": "text/html", ".txt": "text/plain", ".svg": "image/svg+xml",
    ".mjs": "text/javascript", ".json": "application/json" };
  const server = http.createServer((req, res) => {
    if (req.method !== "GET" && req.method !== "HEAD") { res.writeHead(405).end(); return; }
    const rel = decodeURIComponent(new URL(req.url, "http://x").pathname);
    const file = path.join(root, rel.endsWith("/") ? rel + "index.html" : rel);
    if (!file.startsWith(root)) { res.writeHead(403).end(); return; }
    fs.readFile(file, (err, body) => {
      if (err) { res.writeHead(404, { "content-type": "text/plain" }).end("not here\n"); return; }
      res.writeHead(200, { "content-type": types[path.extname(file)] ?? "application/octet-stream" });
      res.end(req.method === "HEAD" ? undefined : body);
    });
  });
  server.listen(port, () => console.log(`serving ${root} read-only on http://localhost:${port}/`));
}

// ------------------------------------------------------------------- the page

const escape = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

function page(st, bag, parts, link, card) {
  const lines = st.node.view()
    .map((m) => `<li><b>${escape(m.sender)}</b> <span class=seq>#${m.seq}</span> ${escape(msgText(m))}</li>`)
    .join("\n");
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>sneakernet snapshot — ${escape(st.node.name)}</title>
<style>
 body{font:16px/1.5 system-ui,sans-serif;margin:2rem auto;max-width:44rem;padding:0 1rem}
 code,pre{font-family:ui-monospace,monospace} pre{white-space:pre-wrap;word-break:break-all;
 background:#f4f4f5;padding:.75rem;border-radius:.4rem;font-size:.75rem}
 .seq{color:#71717a} li{margin:.25rem 0} .note{color:#52525b;font-size:.9rem}
</style></head><body>
<h1>sneakernet snapshot</h1>
<p class="note">Published by <b>${escape(st.node.name)}</b> in room <code>${escape(st.room.slice(0, 16))}…</code>.
This page is a static file. It is exactly as up to date as the moment it was written: nothing here
polls, connects or refreshes. To catch up, paste a fresher bag; to catch somebody else up, send them
the bag below by DM, tweet it as the thread, or show them the QR code.</p>
<h2>${st.node.spool.length} line(s)</h2>
<ul>${lines}</ul>
<h2>the bag</h2>
<pre id="bag">${escape(bag)}</pre>
${link ? `<p>as a link: <a href="${escape(link)}">${escape(link.slice(0, 80))}…</a></p>` : ""}
${card ? `<h2>the share card</h2>
<p><img src="card.svg" alt="${escape(card.alt)}" width="320"></p>
<p class="note">The card carries the whole URL, the text and the picture; it reads back as itself.
To send it in a chat, paste <a href="card.txt">card.txt</a>.</p>` : ""}
<h2>as ${parts.length} tweet(s)</h2>
<pre>${escape(parts.join("\n\n"))}</pre>
<p class="note">Codes: <a href="qr/">qr/</a> · raw bag: <a href="bag.txt">bag.txt</a> ·
thread: <a href="thread.txt">thread.txt</a></p>
</body></html>
`;
}

// ---------------------------------------------------------------------- main

const [, , cmd, dir, ...rest] = process.argv;
const { flags, rest: words } = parseFlags(rest);

switch (cmd) {
  case "init": cmdInit(dir ?? "site", flags); break;
  case "write": cmdWrite(dir, words.join(" ")); break;
  case "paste": cmdPaste(dir, words[0] ?? "-"); break;
  case "publish": cmdPublish(dir, flags); break;
  case "tweets": cmdTweets(dir, flags); break;
  case "status": cmdStatus(dir); break;
  case "serve": cmdServe(dir, flags); break;
  default:
    console.log(fs.readFileSync(path.join(HERE, "sneakernet.mjs"), "utf8")
      .split("\n").filter((l) => l.startsWith("//")).map((l) => l.slice(3)).join("\n"));
    process.exit(cmd ? 1 : 0);
}
