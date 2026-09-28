// publisher.mjs — the kant-zk archive server: collects the pastebin's
// archived threads, folds each room's replies into one transcript page,
// writes a static snapshot (HTML + JSON + manifest), and pushes it to
// the Cloudflare twin so the archive is readable from the public edge
// even when solana.solfunmeme.com is down.
//
// The fold is the same one the pastebin's /threads view does, done
// offline: every paste with the same `reply_to` root is one thread, and
// a kant-zk room's thread is the room's whole history — each archive
// reply adds the lines that arrived since the previous one, so the
// LATEST reply of a thread is always the full transcript.  The snapshot
// keeps every reply (provenance) but the folded view is what renders.
//
// What it writes into the snapshot dir:
//
//   index.html          — the archive front page: every room thread,
//                         newest first, folded line counts, CIDs, links
//   thread/<room8>.html — one page per kant-zk room: the folded
//                         transcript (latest reply's body) + the chain
//                         of replies with their witnesses and CIDs
//   archive.json        — the whole fold as one JSON document
//   manifest.json       — what this snapshot contains + when + sizes
//
// Usage (a daemon; every option is also an env var):
//
//   node server/publisher.mjs \
//       --spool /var/spool/uucp/pastebin \
//       --out /var/lib/kant-zk/snapshot \
//       [--interval 300] [--once] \
//       [--pages-deploy]   # also `wrangler pages deploy` the snapshot
//
// With --pages-deploy the whole site is staged (web/ as the root, the
// snapshot under archive/) and pushed to the CF Pages project
// `kant-zk-pastebin`, using the same token deploy.sh uses
// (~/.cloudflare).  Without it the snapshot is only written to disk;
// any static file server can serve it.

import { readFileSync, writeFileSync, existsSync, mkdirSync, cpSync, rmSync } from "node:fs";
import { join as pathJoin } from "node:path";
import { pasteSpool } from "../web/kant-pastebin.mjs";

// ------------------------------------------------------------- arguments

const arg = (name, dflt) => {
  const k = name.replace(/-/g, "_").toUpperCase();
  if (process.env[k] != null && process.env[k] !== "") return process.env[k];
  const i = process.argv.indexOf(`--${name}`);
  if (i !== -1 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")) {
    return process.argv[i + 1];
  }
  if (process.argv.includes(`--${name}`)) return true; // flag without value
  return dflt;
};

const log = (level, msg, extra = "") =>
  console.log(`${new Date().toISOString()} ${level} publisher ${msg}${extra ? " | " + extra : ""}`);
const info = (m, e) => log("info ", m, e);
const warn = (m, e) => log("warn ", m, e);
const error = (m, e) => console.error(`${new Date().toISOString()} error publisher ${m}${e ? " | " + e : ""}`);

// ----------------------------------------------------------------- fold

/** Group pastes into threads by their reply_to root.
 *  Returns [{ root, replies: [paste…] newest-last }], newest root first. */
function foldThreads(pastes) {
  const byId = new Map(pastes.map((p) => [p.id, p]));
  // Resolve the true root: walk reply_to chains to the top.  Old archive
  // runs chained replies to whatever paste was latest at the time, so
  // the same room can appear under several shallow roots; walking to
  // the top folds them back into one thread.
  const rootOf = (p) => {
    const seen = new Set();
    let cur = p;
    while (cur?.reply_to && byId.has(cur.reply_to) && !seen.has(cur.id)) {
      seen.add(cur.id);
      cur = byId.get(cur.reply_to);
    }
    return cur?.id ?? p.id;
  };
  const roots = new Map(); // rootId -> [paste…]
  for (const p of pastes) {
    const root = rootOf(p);
    if (!roots.has(root)) roots.set(root, []);
    roots.get(root).push(p);
  }
  const threads = [];
  for (const [root, replies] of roots) {
    replies.sort((a, b) => (a.timestamp ?? "").localeCompare(b.timestamp ?? ""));
    threads.push({ root, rootPaste: byId.get(root) ?? replies[0], replies });
  }
  // newest activity first
  threads.sort((a, b) =>
    (b.replies.at(-1)?.timestamp ?? "").localeCompare(a.replies.at(-1)?.timestamp ?? ""));
  return threads;
}

/** The kant-zk room a paste belongs to, from its title; null if none. */
const room8OfPaste = (p) => (p?.title ?? "").match(/kant room ([0-9a-f]{8})…/)?.[1] ?? null;

/** The folded transcript of a thread: the LATEST reply's body — each
 *  archive reply contains the whole transcript as of its timestamp, so
 *  the last one is the complete history. */
function foldedBody(spool, thread) {
  const last = thread.replies.at(-1);
  try { return spool.read(last.id); } catch { return null; }
}

/** Fold threads into rooms: every thread whose pastes name the same
 *  kant-zk room is one room archive, whatever reply chain it rode in
 *  on.  The room's transcript is the latest reply across all its
 *  threads; the reply chain is every paste, oldest first. */
function foldRooms(threads) {
  const rooms = new Map(); // room8 -> { room8, replies: [paste…] }
  for (const t of threads) {
    for (const p of t.replies) {
      const room8 = room8OfPaste(p);
      if (!room8) continue;
      if (!rooms.has(room8)) rooms.set(room8, { room8, replies: [] });
      rooms.get(room8).replies.push(p);
    }
  }
  for (const r of rooms.values()) {
    r.replies.sort((a, b) => (a.timestamp ?? "").localeCompare(b.timestamp ?? ""));
  }
  return [...rooms.values()];
}

// --------------------------------------------------------------- render

const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function renderIndex(threads, manifest) {
  const rows = threads.map((t) => {
    const room8 = t.room8;
    const last = t.replies.at(-1);
    const href = room8 ? `thread/${room8}.html` : null;
    const title = esc(t.rootPaste?.title ?? t.replies[0]?.title ?? t.root);
    return `    <tr><td>${esc(last?.timestamp ?? "")}</td>` +
      `<td>${href ? `<a href="${href}">${title}</a>` : title}</td>` +
      `<td>${t.replies.length}</td>` +
      `<td><code>${esc(last?.cid ?? "")}</code></td></tr>`;
  }).join("\n");
  return `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>kant-zk archive</title>
<style>
body{font-family:monospace;max-width:900px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}
a{color:#0ff;text-decoration:none} code{color:#ff0}
table{border-collapse:collapse;width:100%} td,th{border:1px solid #030;padding:4px 8px;text-align:left}
th{color:#0f0;background:#111}
</style></head><body>
<h1>kant-zk archive</h1>
<p>Folded from the Kant pastebin spool — every room thread, newest activity first.
Snapshot ${esc(manifest.generatedAt)} · ${threads.length} thread(s) ·
<a href="archive.json">archive.json</a> · <a href="manifest.json">manifest.json</a></p>
<table><tr><th>last activity</th><th>thread</th><th>replies</th><th>latest CID</th></tr>
${rows}
</table></body></html>
`;
}

function renderThread(thread, body) {
  const room8 = thread.room8 ?? thread.root.slice(0, 8);
  const chain = thread.replies.map((r) =>
    `    <li>${esc(r.timestamp)} · <code>${esc(r.cid)}</code> · witness <code>${esc((r.witness ?? "").slice(0, 16))}…</code>` +
    ` · <a href="https://solana.solfunmeme.com/pastebin/paste/${encodeURIComponent(r.id)}">paste</a></li>`);
  return `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>kant room ${esc(room8)} — archive</title>
<style>
body{font-family:monospace;max-width:900px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}
a{color:#0ff;text-decoration:none} code{color:#ff0} pre{white-space:pre-wrap;background:#111;padding:10px;border:1px solid #030}
</style></head><body>
<h1>kant room ${esc(room8)}…</h1>
<p><a href="../index.html">← archive</a> · folded transcript (latest reply) + reply chain below.</p>
<h2>transcript</h2>
<pre>${esc(body ?? "(unreadable)")}</pre>
<h2>reply chain (${thread.replies.length})</h2>
<ul>
${chain.join("\n")}
</ul></body></html>
`;
}

// -------------------------------------------------------------- snapshot

function writeSnapshot({ spool, out, roomsOnly }) {
  const pastes = spool.list({});
  let threads = foldThreads(pastes);
  const rooms = foldRooms(threads);
  const archive = rooms.map((t) => ({
    root: t.replies[0]?.reply_to ?? t.replies[0]?.id,
    room8: t.room8,
    replies: t.replies.map((r) => ({
      id: r.id, timestamp: r.timestamp, cid: r.cid, witness: r.witness,
      ipfs_cid: r.ipfs_cid, title: r.title, size: r.size,
    })),
  }));
  const manifest = {
    generatedAt: new Date().toISOString(),
    source: "kant-pastebin spool",
    threads: rooms.length,
    pastes: pastes.length,
    roomsOnly: Boolean(roomsOnly),
  };
  mkdirSync(pathJoin(out, "thread"), { recursive: true });
  writeFileSync(pathJoin(out, "archive.json"), JSON.stringify(archive, null, 2) + "\n");
  writeFileSync(pathJoin(out, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  writeFileSync(pathJoin(out, "index.html"), renderIndex(rooms, manifest));
  for (const t of rooms) {
    writeFileSync(pathJoin(out, "thread", `${t.room8}.html`), renderThread(t, foldedBody(spool, t)));
  }
  return { threads: rooms.length, pastes: pastes.length };
}

// ---------------------------------------------------------------- push

async function pagesDeploy(out) {
  const { execFileSync } = await import("node:child_process");
  const token = existsSync(`${process.env.HOME}/.cloudflare`)
    ? readFileSync(`${process.env.HOME}/.cloudflare`, "utf8").trim() : "";
  const env = { ...process.env, CLOUDFLARE_API_TOKEN: token };
  // Stage the whole site: web/ root + the snapshot under archive/.
  const webDir = pathJoin(import.meta.dirname, "..", "web");
  const stage = pathJoin(out, "..", "kant-pages-stage");
  rmSync(stage, { recursive: true, force: true });
  cpSync(webDir, stage, { recursive: true });
  cpSync(out, pathJoin(stage, "archive"), { recursive: true });
  execFileSync("npx", ["wrangler", "pages", "deploy", stage,
    "--project-name", "kant-zk-pastebin", "--branch", "main", "--commit-dirty=true"],
    { env, stdio: "inherit", cwd: process.cwd() });
}

// ----------------------------------------------------------------- main

const spoolDir = arg("spool", "/var/spool/uucp/pastebin");
const out = arg("out", "/var/lib/kant-zk/snapshot");
const interval = Math.max(10, Number(arg("interval", 300)) || 300);
const once = arg("once", false);
const deployPages = arg("pages-deploy", false);
const roomsOnly = arg("rooms-only", true); // default: only kant-zk room threads

const spool = pasteSpool(spoolDir);
info(`spool=${spoolDir} out=${out} interval=${interval}s pages-deploy=${deployPages} rooms-only=${roomsOnly}`);

async function cycle() {
  try {
    const t0 = Date.now();
    const stats = writeSnapshot({ spool, out, roomsOnly });
    info(`snapshot: ${stats.threads} thread(s) from ${stats.pastes} paste(s)`, `${Date.now() - t0}ms`);
    if (deployPages) {
      await pagesDeploy(out);
      info("pushed snapshot to Cloudflare Pages");
    }
  } catch (e) {
    error("snapshot cycle failed", e.message ?? e);
  }
}

await cycle();
if (once) process.exit(0);
info(`polling every ${interval}s`);
for (;;) { await new Promise((r) => setTimeout(r, interval * 1000)); await cycle(); }
