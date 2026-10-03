#!/usr/bin/env node
// relay.mjs — the kant-zk rendezvous relay for a Linux box.
//
// Zero dependencies: Node's own `http` module, plus a small RFC 6455
// server so the browser can hold a WebSocket open instead of polling.
//
// What it is: one append-only log per room, exactly the `Server` of
// `RequestProject/Kant/Relay.lean` (`post`, `lines`, `fetch`).  It never
// parses what it carries and never learns a room secret — a room name is
// the digest of that secret, computed in the browser.  Clients re-check
// every line against its own witness, so a hostile relay can withhold
// lines but cannot forge them.
//
// Two documented deviations from the proved model, both about running out
// of memory rather than about semantics:
//   * a line longer than --max-line bytes is rejected with 413;
//   * a room keeps at most --max-lines lines, and is forgotten after
//     --room-ttl of silence.  Cursors stay absolute; a poll from a cursor
//     that has been trimmed away gets `truncated: true` plus everything
//     still held.
//
// Usage:  node server/relay.mjs [--port 8787] [--static web] [--origin '*']
//                                [--log relay.log] [--quiet]
//
// Every request is written to the log: the time, the method, the path with
// the room reduced to an eight-character handle, the status, the number of
// lines and how long it took.  Rooms are never printed in full, so a relay
// log can be shared the way `web/diag.html` shares a client run.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";
import { PassStore } from "./pass-store.mjs";
import { DiskBlocks } from "./disk-blocks.mjs";
import { pastePass, passOk, passRoom } from "../web/kant-pass.mjs";
import { parseMsg } from "../web/kant-net.mjs";
import { witness } from "../web/kantzk.mjs";

const args = new Map();
for (let i = 2; i < process.argv.length; i += 1) {
  const tok = process.argv[i];
  if (!tok.startsWith("--")) continue;
  const next = process.argv[i + 1];
  // `--flag` on its own is a flag; `--key value` is a setting.
  if (next === undefined || next.startsWith("--")) args.set(tok.slice(2), "1");
  else { args.set(tok.slice(2), next); i += 1; }
}

/** Are we the program being run, or a library inside somebody else's?
 *  A library keeps quiet unless it is given a log file. */
const isMain = process.argv[1] && import.meta.url === `file://${path.resolve(process.argv[1])}`;

export const CONFIG = {
  port: Number(args.get("port") ?? process.env.PORT ?? 8787),
  host: args.get("host") ?? process.env.HOST ?? "0.0.0.0",
  staticDir: args.get("static") ?? process.env.KANT_STATIC ?? "",
  origin: args.get("origin") ?? process.env.KANT_ORIGIN ?? "*",
  maxLine: Number(args.get("max-line") ?? 262144),
  maxLines: Number(args.get("max-lines") ?? 4096),
  maxBody: Number(args.get("max-body") ?? 1048576),
  roomTtlMs: Number(args.get("room-ttl") ?? 6 * 60 * 60 * 1000),
  logFile: args.get("log") ?? process.env.KANT_LOG ?? "",
  quiet: args.get("quiet") === "1" || process.env.KANT_QUIET === "1" || !isMain,
  passDb: args.get("pass-db") ?? process.env.KANT_PASS_DB ?? "/var/lib/kant-zk/passes.sqlite",
  peerLimit: Number(args.get("peer-limit") ?? 10),
  peerWindowMs: Number(args.get("peer-window") ?? 10 * 60 * 1000),
  maxBlock: Number(args.get("max-block") ?? 1048576),
  gasStoreBudget: Number(args.get("gas-store") ?? 64 * 1024 * 1024),
  gasServeBudget: Number(args.get("gas-serve") ?? 256 * 1024 * 1024),
  gasWindowMs: Number(args.get("gas-window") ?? 60 * 60 * 1000),
  archiveDir: args.get("archive-dir") ?? process.env.KANT_ARCHIVE ?? "",
  blocksDir: args.get("blocks-dir") ?? process.env.KANT_BLOCKS ?? "",
  version: "1.0.0",
};

// ------------------------------------------------------------- the log

/** An eight-character one-way handle, as `Kant.Diagnostics.ref`. */
export const roomRef = (room) =>
  crypto.createHash("sha256").update(String(room)).digest("hex").slice(0, 8);

/**
 * Read the pass (or owner invite) out of a POST's headers.  Returns
 * the parsed pass (limit 0 for the owner's unlimited invite), `null`
 * when no header was sent, or `false` when a header was sent but is
 * bad (wrong room, bad signature, unparseable).
 */
function readPassHeader(req, room, log) {
  const raw = req.headers["x-kant-pass"] ?? req.headers["x-kant-invite"];
  if (raw == null) return null;
  const pass = pastePass(String(raw));
  if (!pass) return false;
  if (passRoom(pass) !== room) return false;
  if (pass.limit > 0 && !passOk(pass, pass.secret)) return false;
  return pass;
}

/** The kzchat sender id inside a line, if the line is a chat message. */
function senderOf(lines) {
  for (const l of lines) {
    const m = parseMsg(l);
    if (m && m.sender) return m.sender;
  }
  return null;
}

/** One line per request: `time level area text | detail`.  Writes to the
 *  file named by `--log` (appending) and, unless `--quiet`, to stdout. */
export function makeLogger(cfg = CONFIG) {
  const stream = cfg.logFile ? fs.createWriteStream(cfg.logFile, { flags: "a" }) : null;
  const write = (level, area, text, detail = "") => {
    const line = `${new Date().toISOString()} ${level.padEnd(5)} ${area.padEnd(6)} ${text}` +
      `${detail ? `  |  ${detail}` : ""}`;
    if (stream) stream.write(`${line}\n`);
    if (!cfg.quiet) console.log(line);
    return line;
  };
  return {
    info: (a, t, d) => write("info", a, t, d),
    warn: (a, t, d) => write("warn", a, t, d),
    error: (a, t, d) => write("error", a, t, d),
    close: () => stream?.end(),
  };
}

// ------------------------------------------------------------- the rooms

// ------------------------------------------------------- blocks and gas

/** Room-scoped, content-addressed block store with a gas ledger.
 *
 *  A block's name is the digest of its bytes (verified on write — a
 *  writer can pin garbage under a name of its own, but never under the
 *  name of honest bytes).  Blocks live under a room name: knowing the
 *  room is the trust credential, exactly as it is for reading the room's
 *  lines.
 *
 *  Gas is what keeps a room's pinning honest: every byte written and
 *  every byte served is charged to the room's ledger, and the budget
 *  refills every window.  A room that burns through its budget gets a
 *  429 until the window turns over — the relay relays for its peers,
 *  not for the whole internet. */
export class Blocks {
  constructor(cfg = CONFIG) {
    this.cfg = cfg;
    this.map = new Map(); // room -> { blocks: Map(cid -> bytes), gas: {stored, served, window} }
  }

  room(name) {
    let r = this.map.get(name);
    if (!r) {
      r = { blocks: new Map(), gas: { stored: 0, served: 0, window: Date.now() } };
      this.map.set(name, r);
    }
    return r;
  }

  /** The ledger, rolled over if the window has passed. */
  gas(name) {
    const r = this.room(name);
    if (Date.now() - r.gas.window > this.cfg.gasWindowMs) {
      r.gas.stored = 0; r.gas.served = 0; r.gas.window = Date.now();
    }
    return r.gas;
  }

  /** Pin bytes under their name.  Returns null on success, or
   *  { status, error } describing the refusal. */
  put(name, cid, bytes) {
    if (witness(Array.from(bytes)) !== cid) {
      return { status: 400, error: "cid is not the digest of the bytes" };
    }
    if (bytes.length > this.cfg.maxBlock) return { status: 413, error: "block too large" };
    const g = this.gas(name);
    if (g.stored + bytes.length > this.cfg.gasStoreBudget) {
      return { status: 429, error: "the room is out of pinning gas until the window turns" };
    }
    const r = this.room(name);
    if (!r.blocks.has(cid)) g.stored += bytes.length;
    r.blocks.set(cid, Buffer.from(bytes));
    return null;
  }

  /** Serve a block, charging the room for the bytes. */
  get(name, cid) {
    const r = this.map.get(name);
    const bytes = r?.blocks.get(cid);
    if (!bytes) return { status: 404, error: "no such block" };
    const g = this.gas(name);
    if (g.served + bytes.length > this.cfg.gasServeBudget) {
      return { status: 429, error: "the room is out of serving gas until the window turns" };
    }
    g.served += bytes.length;
    return bytes;
  }

  /** The room's pin list (see DiskBlocks.list). */
  list(name) {
    const r = this.map.get(name);
    return r ? [...r.blocks.keys()] : [];
  }
}

/** One append-only log per room (`Kant.Relay.Server`). */
export class Rooms {
  constructor(cfg = CONFIG) {
    this.cfg = cfg;
    this.map = new Map(); // room -> { base, lines, waiters, sockets, touched }
  }

  room(name) {
    let r = this.map.get(name);
    if (!r) {
      r = { base: 0, lines: [], waiters: new Set(), sockets: new Set(), touched: Date.now() };
      this.map.set(name, r);
    }
    r.touched = Date.now();
    return r;
  }

  /** Absolute length of the log: the cursor the next line will get. */
  end(name) { const r = this.room(name); return r.base + r.lines.length; }

  post(name, lines) {
    const r = this.room(name);
    for (const l of lines) r.lines.push(l);
    if (r.lines.length > this.cfg.maxLines) {
      const drop = r.lines.length - this.cfg.maxLines;
      r.lines.splice(0, drop);
      r.base += drop;
    }
    const cursor = r.base + r.lines.length;
    for (const w of [...r.waiters]) { r.waiters.delete(w); w(); }
    for (const s of [...r.sockets]) s.push(this.fetch(name, s.cursor));
    return cursor;
  }

  /** Everything from `cursor` onwards, plus the new cursor. */
  fetch(name, cursor) {
    const r = this.room(name);
    const end = r.base + r.lines.length;
    const from = Math.max(cursor, r.base);
    return {
      cursor: end,
      lines: r.lines.slice(from - r.base),
      truncated: cursor < r.base,
    };
  }

  /** Resolve when something is posted, or after `ms`. */
  wait(name, ms) {
    const r = this.room(name);
    return new Promise((resolve) => {
      const done = () => { clearTimeout(timer); r.waiters.delete(done); resolve(); };
      const timer = setTimeout(done, ms);
      r.waiters.add(done);
    });
  }

  sweep() {
    const now = Date.now();
    for (const [name, r] of this.map) {
      if (r.sockets.size === 0 && r.waiters.size === 0 &&
          now - r.touched > this.cfg.roomTtlMs) this.map.delete(name);
    }
  }

  stats() {
    return {
      rooms: this.map.size,
      lines: [...this.map.values()].reduce((n, r) => n + r.lines.length, 0),
      sockets: [...this.map.values()].reduce((n, r) => n + r.sockets.size, 0),
    };
  }
}

// -------------------------------------------------------------- HTTP part

const MIME = {
  ".html": "text/html; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
  ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".json": "application/json", ".wasm": "application/wasm",
  ".png": "image/png", ".svg": "image/svg+xml", ".gif": "image/gif",
  ".ico": "image/x-icon", ".txt": "text/plain; charset=utf-8",
};

const cors = (cfg) => ({
  "access-control-allow-origin": cfg.origin,
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, x-kant-pass, x-kant-invite",
  "access-control-max-age": "86400",
});

const sendJson = (res, cfg, code, obj) => {
  res.writeHead(code, { "content-type": "application/json", ...cors(cfg) });
  res.end(JSON.stringify(obj));
};

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > limit) { reject(new Error("too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

/** The same reader, but the bytes stay bytes — a block's ciphertext is
 *  binary and must not pass through utf-8 on its way to the store. */
function readBodyRaw(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > limit) { reject(new Error("too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

// Serving `web/` as the document root leaves the Lean-extracted kernel, which
// lives in the sibling `dist/`, outside the tree: `/dist/kant_kernel.wasm` used
// to 404, and the page reported that as a kernel validation failure. Requests
// under /dist/ therefore also look in the directory next to the static root.
function staticCandidates(cfg, rel) {
  const root = path.resolve(cfg.staticDir);
  const safe = path.normalize(rel).replace(/^(\.\.[/\\])+/, "");
  const inRoot = path.join(root, safe);
  const files = inRoot.startsWith(root) ? [inRoot] : [];
  const distRoot = path.resolve(root, "..", "dist");
  const under = /^[/\\]dist[/\\](.+)$/.exec(safe);
  if (under) {
    const sibling = path.join(distRoot, under[1]);
    if (sibling.startsWith(distRoot)) files.push(sibling);
  }
  return files;
}

function serveStatic(cfg, res, urlPath) {
  const rel = urlPath === "/" ? "/index.html" : urlPath;
  const files = staticCandidates(cfg, rel);
  const attempt = (i) => {
    if (i >= files.length) {
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
      return;
    }
    fs.readFile(files[i], (err, data) => {
      if (err) { attempt(i + 1); return; }
      res.writeHead(200, {
        "content-type": MIME[path.extname(files[i])] ?? "application/octet-stream",
        "cache-control": "no-cache",
      });
      res.end(data);
    });
  };
  attempt(0);
}

/** The pass store: at the configured path when that is usable, else a
 *  writable os.tmpdir() fallback (CI, sandboxes, unprivileged runs).
 *  An explicit --pass-db or KANT_PASS_DB is never downgraded silently --
 *  if the operator named a path, failing loudly is the honest answer. */
function makePassStore(cfg) {
  const opts = { peerLimit: cfg.peerLimit, peerWindowMs: cfg.peerWindowMs };
  try {
    return new PassStore(cfg.passDb, opts);
  } catch (err) {
    if (process.env.KANT_PASS_DB || String(args.get("pass-db") ?? "")) throw err;
    const fallback = path.join(os.tmpdir(), "kant-zk-passes.sqlite");
    console.error(`pass-db ${cfg.passDb} unusable (${err.code ?? err}), using ${fallback}`);
    return new PassStore(fallback, opts);
  }
}

export function createServer(cfg = CONFIG, rooms = new Rooms(cfg), log = makeLogger(cfg),
  passes = makePassStore(cfg)) {
  // With --blocks-dir the block store is the durable DiskBlocks twin:
  // same API and gas rules, but the pins survive a restart and replay
  // on boot.  Without it, the in-memory store (a room's pins live only
  // as long as the relay does).
  const blocks = cfg.blocksDir
    ? new DiskBlocks(cfg, cfg.blocksDir)
    : new Blocks(cfg);
  // The archive: every room line and every block pin, appended to one
  // ndjson file per room handle, so a reader can replay a room that the
  // relay itself has long since forgotten.  The room name is only ever
  // recorded as its eight-character handle.
  const archive = (room, kind, payload) => {
    if (!cfg.archiveDir) return;
    try {
      fs.mkdirSync(cfg.archiveDir, { recursive: true });
      fs.appendFileSync(
        path.join(cfg.archiveDir, `${roomRef(room)}.ndjson`),
        JSON.stringify({ t: new Date().toISOString(), kind, ...payload }) + "\n");
    } catch (e) { log.warn("archive", "an entry was not written", e.message); }
  };
  const server = http.createServer(async (req, res) => {
    const started = Date.now();
    const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
    const shown = url.pathname.replace(/^\/(room|ws)\/([^/]+)/,
      (_, kind, room) => `/${kind}/${roomRef(decodeURIComponent(room))}`);
    res.on("finish", () => log.info("relay",
      `${req.method} ${shown} ${res.statusCode}`,
      `${Date.now() - started}ms from ${req.socket.remoteAddress ?? "?"}`));
    req.on("error", (e) => log.error("relay", `${req.method} ${shown} failed`, e.message));

    if (req.method === "OPTIONS") { res.writeHead(204, cors(cfg)); res.end(); return; }

    if (url.pathname === "/health") {
      sendJson(res, cfg, 200, {
        ok: true, name: "kant-zk-relay", version: cfg.version, ...rooms.stats(),
      });
      return;
    }

    const m = url.pathname.match(/^\/room\/([^/]+)$/);
    if (m) {
      const room = decodeURIComponent(m[1]);
      log.info("relay", `route room ${roomRef(room)}`, `${req.method} ${shown}`);
      if (req.method === "POST") {
        let body;
        try { body = await readBody(req, cfg.maxBody); }
        catch (e) {
          log.warn("relay", "a body was refused", `${roomRef(room)}: ${e.message}`);
          sendJson(res, cfg, 413, { ok: false, error: "body too large" });
          return;
        }
        const lines = body.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
        if (lines.some((l) => l.length > cfg.maxLine)) {
          log.warn("relay", "a line was too long", roomRef(room));
          sendJson(res, cfg, 413, { ok: false, error: "line too long" });
          return;
        }
        // Pass + rate limiting.  A POST may carry a kzpass in
        // `x-kant-pass` (limited invite) or a kzinvite in
        // `x-kant-invite` (owner's unlimited invite).  Without either,
        // the per-sender rate limit applies.
        const pass = readPassHeader(req, room, log);
        if (pass === false) {
          sendJson(res, cfg, 401, { ok: false, error: "bad pass" });
          return;
        }
        const sender = senderOf(lines) ?? `ip:${req.socket.remoteAddress ?? "?"}`;
        const verdict = passes.admit({ pass, sender, room, lines: lines.length });
        if (!verdict.ok) {
          log.warn("relay", "a post was refused", `${roomRef(room)}: ${verdict.error}`);
          sendJson(res, cfg, verdict.status, { ok: false, error: verdict.error });
          return;
        }
        const cursor = rooms.post(room, lines);
        log.info("relay", `posted ${lines.length} lines`, `${roomRef(room)} cursor=${cursor} pass=${pass ? pass.limit : "peer"}`);
        for (const l of lines) archive(room, "line", { cursor, line: l });
        sendJson(res, cfg, 200, { ok: true, cursor, accepted: lines.length,
          passRemaining: verdict.remaining });
        return;
      }
      if (req.method === "GET") {
        const cursor = Number(url.searchParams.get("cursor") ?? 0) || 0;
        const wait = Math.min(Number(url.searchParams.get("wait") ?? 0) || 0, 60);
        log.info("relay", `fetch room`, `${roomRef(room)} cursor=${cursor} wait=${wait}`);
        let out = rooms.fetch(room, cursor);
        if (wait > 0 && out.lines.length === 0) {
          log.info("relay", `waiting for room`, `${roomRef(room)} cursor=${cursor} wait=${wait}s`);
          await rooms.wait(room, wait * 1000);
          out = rooms.fetch(room, cursor);
        }
        log.info("relay", `fetched room`, `${roomRef(room)} cursor=${cursor} -> ${out.cursor} lines=${out.lines.length} truncated=${out.truncated}`);
        sendJson(res, cfg, 200, { ok: true, ...out });
        return;
      }
      log.warn("relay", "method not allowed", `${roomRef(room)} ${req.method}`);
      sendJson(res, cfg, 405, { ok: false, error: "method not allowed" });
      return;
    }

    // The room's pin list: /room/<addr>/blocks — what the pairer and the
    // page emitter diff against the twin.  Listing is free (no bytes
    // move, no gas charged); only the room's handle is shown.
    const bl = url.pathname.match(/^\/room\/([^/]+)\/blocks$/);
    if (bl && req.method === "GET") {
      const room = decodeURIComponent(bl[1]);
      sendJson(res, cfg, 200, { ok: true, roomRef: roomRef(room), blocks: blocks.list(room) });
      return;
    }

    // Content-addressed blocks, room-scoped: /room/<addr>/block/<cid>.
    // Knowing the room is the trust credential, exactly as it is for the
    // room's lines; every byte in and out is charged to the room's gas.
    const b = url.pathname.match(/^\/room\/([^/]+)\/block\/([0-9a-f]{64})$/);
    if (b) {
      const room = decodeURIComponent(b[1]);
      const cid = b[2];
      if (req.method === "POST" || req.method === "PUT") {
        let body;
        try { body = await readBodyRaw(req, cfg.maxBlock + 1024); }
        catch (e) {
          log.warn("block", "a body was refused", `${roomRef(room)}: ${e.message}`);
          sendJson(res, cfg, 413, { ok: false, error: "block too large" });
          return;
        }
        const refused = blocks.put(room, cid, body);
        if (refused) {
          log.warn("block", "a pin was refused", `${roomRef(room)} ${cid.slice(0, 12)}: ${refused.error}`);
          sendJson(res, cfg, refused.status, { ok: false, error: refused.error });
          return;
        }
        const g = blocks.gas(room);
        log.info("block", "a block was pinned", `${roomRef(room)} ${cid.slice(0, 12)} ${body.length}B`);
        archive(room, "block", { cid, bytes: body.length });
        sendJson(res, cfg, 200, { ok: true, cid, bytes: body.length,
          gasStored: g.stored, gasStoredLeft: cfg.gasStoreBudget - g.stored });
        return;
      }
      if (req.method === "GET") {
        const out = blocks.get(room, cid);
        if (out.status) {
          log.warn("block", "a fetch was refused", `${roomRef(room)} ${cid.slice(0, 12)}: ${out.error}`);
          sendJson(res, cfg, out.status, { ok: false, error: out.error });
          return;
        }
        log.info("block", "a block was served", `${roomRef(room)} ${cid.slice(0, 12)} ${out.length}B`);
        res.writeHead(200, { ...cors(cfg), "content-type": "application/octet-stream",
          "content-length": out.length });
        res.end(out);
        return;
      }
      sendJson(res, cfg, 405, { ok: false, error: "method not allowed" });
      return;
    }

    if (cfg.staticDir) {
      log.info("relay", "static", shown);
      serveStatic(cfg, res, url.pathname);
      return;
    }
    log.warn("relay", "not found", shown);
    sendJson(res, cfg, 404, { ok: false, error: "not found" });
  });

  server.on("upgrade", (req, socket) => handleUpgrade(cfg, rooms, req, socket, log));
  server.on("clientError", (e, socket) => {
    log.error("relay", "a connection failed before any request", e.message);
    socket.destroy();
  });
  const sweeper = setInterval(() => rooms.sweep(), 60_000);
  sweeper.unref?.();
  server.rooms = rooms;
  server.log = log;
  return server;
}

// --------------------------------------------------------- WebSocket part
// A minimal RFC 6455 server: text frames, ping and close, which is all the
// protocol needs.  Client frames are masked; server frames are not.

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const wsAccept = (key) => crypto.createHash("sha1").update(key + WS_GUID).digest("base64");

function wsFrame(text) {
  const payload = Buffer.from(text, "utf8");
  const n = payload.length;
  let header;
  if (n < 126) {
    header = Buffer.alloc(2);
    header[1] = n;
  } else if (n < 65536) {
    header = Buffer.alloc(4);
    header[1] = 126;
    header.writeUInt16BE(n, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(n), 2);
  }
  header[0] = 0x81; // FIN + text
  return Buffer.concat([header, payload]);
}

/** Pull whole frames out of a buffer; returns how many bytes were used. */
function wsFrames(buf) {
  const out = [];
  let off = 0;
  while (off + 2 <= buf.length) {
    const b0 = buf[off], b1 = buf[off + 1];
    const opcode = b0 & 0x0f;
    const masked = (b1 & 0x80) !== 0;
    let len = b1 & 0x7f;
    let p = off + 2;
    if (len === 126) { if (p + 2 > buf.length) break; len = buf.readUInt16BE(p); p += 2; }
    else if (len === 127) {
      if (p + 8 > buf.length) break;
      len = Number(buf.readBigUInt64BE(p)); p += 8;
    }
    let mask = null;
    if (masked) { if (p + 4 > buf.length) break; mask = buf.subarray(p, p + 4); p += 4; }
    if (p + len > buf.length) break;
    const data = Buffer.from(buf.subarray(p, p + len));
    if (mask) for (let i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
    off = p + len;
    out.push({ opcode, data });
  }
  return { frames: out, used: off };
}

function handleUpgrade(cfg, rooms, req, socket, log = { info() {}, warn() {}, error() {} }) {
  const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
  const m = url.pathname.match(/^\/ws\/([^/]+)$/);
  const key = req.headers["sec-websocket-key"];
  if (!m || !key) {
    log.warn("relay", "websocket upgrade rejected", "missing room or key");
    socket.destroy();
    return;
  }
  const room = decodeURIComponent(m[1]);
  log.info("relay", "websocket upgrade", `${roomRef(room)} cursor=${url.searchParams.get("cursor") ?? 0}`);

  socket.write(
    "HTTP/1.1 101 Switching Protocols\r\n" +
    "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
    `Sec-WebSocket-Accept: ${wsAccept(key)}\r\n\r\n`,
  );

  const state = {
    cursor: Number(url.searchParams.get("cursor") ?? 0) || 0,
    push(out) {
      if (out.lines.length === 0) { state.cursor = out.cursor; return; }
      state.cursor = out.cursor;
      socket.write(wsFrame(JSON.stringify({ ok: true, ...out })));
    },
  };

  const r = rooms.room(room);
  r.sockets.add(state);
  state.push(rooms.fetch(room, state.cursor));

  let pending = Buffer.alloc(0);
  socket.on("data", (chunk) => {
    pending = Buffer.concat([pending, chunk]);
    const { frames, used } = wsFrames(pending);
    pending = pending.subarray(used);
    for (const { opcode, data } of frames) {
      if (opcode === 0x8) { socket.end(); return; }
      if (opcode === 0x9) socket.write(Buffer.concat([Buffer.from([0x8a, data.length]), data]));
      if (opcode === 0x1) {
        const lines = data.toString("utf8").split("\n")
          .map((l) => l.trim()).filter((l) => l.length > 0 && l.length <= cfg.maxLine);
        if (lines.length) rooms.post(room, lines);
      }
    }
  });

  const drop = () => { r.sockets.delete(state); };
  socket.on("close", () => { log.info("socket", `a stream closed`, roomRef(room)); drop(); });
  socket.on("error", (e) => { log.error("socket", "a stream failed", e.message); drop(); });
  log.info("socket", "a stream opened", roomRef(room));
}

// ------------------------------------------------------------------- main

if (isMain) {
  const server = createServer(CONFIG);
  server.listen(CONFIG.port, CONFIG.host, () => {
    console.log(`kant-zk relay ${CONFIG.version} listening on http://${CONFIG.host}:${CONFIG.port}`);
    console.log("  POST /room/{room}                    append lines");
    console.log("  GET  /room/{room}?cursor=N[&wait=S]  poll (long poll with wait)");
    console.log("  WS   /ws/{room}?cursor=N             stream");
    if (CONFIG.staticDir) console.log(`  serving ${path.resolve(CONFIG.staticDir)} at /`);
    if (CONFIG.logFile) console.log(`  writing the log to ${path.resolve(CONFIG.logFile)}`);
    if (CONFIG.blocksDir) console.log(`  blocks pinned durably under ${path.resolve(CONFIG.blocksDir)}`);
  });
}
