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
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { PassStore } from "./pass-store.mjs";
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
  version: "1.0.0",
  commit: process.env.KANT_COMMIT ?? "",
};

// Which build is this? The twins speak one protocol but are deployed
// independently, so a stale twin is otherwise invisible: both reported
// version "1.0.0" while serving different wasm. Stamp the commit at build
// time (KANT_COMMIT) or read it from the checkout, and let the operator
// override so a deployed artifact can be labelled without a rebuild.
function resolveCommit() {
  if (CONFIG.commit) return CONFIG.commit;
  try {
    // "." is the directory holding this file (server/); the checkout is its
    // parent. Note `new URL("..", import.meta.url)` would resolve above the
    // repo, which is why the path is joined explicitly.
    const here = fs.realpathSync(new URL(".", import.meta.url).pathname);
    const root = path.resolve(here, "..");
    let ref = fs.readFileSync(path.join(root, ".git", "HEAD"), "utf8").trim();
    if (ref.startsWith("ref: ")) {
      const name = ref.slice(5).trim();
      try {
        ref = fs.readFileSync(path.join(root, ".git", name), "utf8").trim();
      } catch {
        // unborn or packed ref
        const packed = fs.readFileSync(path.join(root, ".git", "packed-refs"), "utf8");
        ref = (packed.split("\n").find((l) => l.endsWith(" " + name)) ?? "").split(" ")[0] ?? "";
      }
    }
    return /^[0-9a-f]{7,40}$/.test(ref) ? ref.slice(0, 12) : "";
  } catch {
    return "";
  }
}

const COMMIT = resolveCommit();

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

/*
 * Experimental strict V2-only authorization.
 * Never trust issuer keys supplied by the bearer.
 */
function readV2Header(req) {
  const raw = req.headers["x-kant-v2"];

  if (
    typeof raw !== "string" ||
    raw.length === 0 ||
    raw.length > 4096 ||
    !/^[A-Za-z0-9_-]+$/.test(raw)
  ) return false;

  try {
    const bytes = Buffer.from(raw, "base64url");

    if (bytes.toString("base64url") !== raw) {
      return false;
    }

    const token = JSON.parse(
      bytes.toString("utf8")
    );

    if (
      !token ||
      typeof token !== "object" ||
      Array.isArray(token)
    ) return false;

    return token;
  } catch {
    return false;
  }
}

function hasLegacyCredential(req) {
  return (
    req.headers["x-kant-pass"] !== undefined ||
    req.headers["x-kant-invite"] !== undefined
  );
}

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
 *  writable os.tmpdir() fallback (CI, sandboxes, unprivileged runs). */
function makePassStore(cfg) {
  const opts = { peerLimit: cfg.peerLimit, peerWindowMs: cfg.peerWindowMs };
  try {
    return new PassStore(cfg.passDb ?? "/var/lib/kant-zk/passes.sqlite", opts);
  } catch (err) {
    if (process.env.KANT_PASS_DB || String(args.get("pass-db") ?? "")) throw err;
    const fallback = path.join(os.tmpdir(), "kant-zk-passes.sqlite");
    console.error(`pass-db ${cfg.passDb} unusable (${err.code ?? err}), using ${fallback}`);
    return new PassStore(fallback, opts);
  }
}

export function createServer(cfg = CONFIG, rooms = new Rooms(cfg), log = makeLogger(cfg),
  passes = makePassStore(cfg)) {
  if (
    cfg.v2Only === true &&
    (
      !cfg.v2Authority ||
      typeof cfg.v2Authority.validate !== "function" ||
      typeof cfg.v2Authority.admit !== "function"
    )
  ) {
    throw new Error("V2_AUTHORITY_REQUIRED");
  }

  if (cfg.v2Durable === true && (
    cfg.v2Only !== true ||
    !cfg.v2Authority ||
    typeof cfg.v2Authority.admitDurable !== "function" ||
    typeof cfg.v2Authority.readDurable !== "function"
  )) {
    throw new Error("DURABLE_V2_AUTHORITY_REQUIRED");
  }

  const blocks = new Blocks(cfg);
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
        ok: true, name: "kant-zk-relay", version: cfg.version,
        commit: COMMIT, platform: "systemd", ...rooms.stats(),
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
        const v2Token = cfg.v2Only === true
          ? readV2Header(req)
          : null;

        const pass = cfg.v2Only === true
          ? null
          : readPassHeader(req, room, log);

        if (
          pass === false ||
          (
            cfg.v2Only === true &&
            (
              v2Token === false ||
              hasLegacyCredential(req)
            )
          ) ||
          (
            cfg.v2Only !== true &&
            req.headers["x-kant-v2"] !== undefined
          )
        ) {
          sendJson(res, cfg, 401, {
            ok: false,
            error: "invalid credential"
          });
          return;
        }
        const sender = senderOf(lines) ?? `ip:${req.socket.remoteAddress ?? "?"}`;

        if (cfg.v2Durable === true) {
          const publicationId =
            req.headers["x-kant-publication-id"];

          if (
            typeof publicationId !== "string" ||
            !/^[0-9a-f]{32}$/.test(publicationId)
          ) {
            sendJson(res, cfg, 400, {
              ok: false,
              error: "invalid publication id"
            });
            return;
          }

          let durable;

          try {
            durable = cfg.v2Authority.admitDurable(
              v2Token, room, lines, publicationId
            );
          } catch (error) {
            log.error(
              "relay", "durable admission failed",
              error.message
            );
            sendJson(res, cfg, 503, {
              ok: false,
              error: "durable admission unavailable"
            });
            return;
          }

          if (!durable?.ok) {
            sendJson(res, cfg, durable?.status ?? 503, {
              ok: false,
              error: durable?.error ??
                "durable admission rejected"
            });
            return;
          }

          sendJson(res, cfg, 200, {
            ok: true,
            cursor: durable.sequence,
            accepted: lines.length,
            duplicate: durable.duplicate,
            passRemaining: durable.remaining ?? null
          });
          return;
        }

        let verdict;

        try {
          verdict = cfg.v2Only === true
            ? cfg.v2Authority.admit(
                v2Token, room, lines.length
              )
            : passes.admit({
                pass, sender, room, lines: lines.length
              });
        } catch (error) {
          // Never publish when the SQLite admission ledger fails.
          log.error(
            "relay",
            "HTTP admission failed",
            error.message
          );

          sendJson(res, cfg, 503, {
            ok: false,
            error: "admission temporarily unavailable"
          });
          return;
        }
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
        if (cfg.v2Durable === true) {
          const raw = url.searchParams.get("cursor") ?? "0";
          const cursor = Number(raw);

          if (
            !/^(0|[1-9][0-9]*)$/.test(raw) ||
            !Number.isSafeInteger(cursor)
          ) {
            sendJson(res, cfg, 400, {
              ok: false, error: "invalid cursor"
            });
            return;
          }

          let publications;

          try {
            publications = cfg.v2Authority.readDurable(
              room, cursor, 100
            );
          } catch (error) {
            log.error(
              "relay", "durable read failed",
              error.message
            );
            sendJson(res, cfg, 503, {
              ok: false,
              error: "durable read unavailable"
            });
            return;
          }

          sendJson(res, cfg, 200, {
            ok: true,
            cursor: publications.length
              ? publications[publications.length - 1].sequence
              : cursor,
            lines: publications.flatMap(x => x.lines),
            publications: publications.map(x => ({
              publicationId: x.publicationId,
              sequence: x.sequence,
              epoch: x.epoch
            })),
            truncated: false
          });
          return;
        }

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

    // Content-addressed blocks, room-scoped: /room/<addr>/block/<cid>.
    // Knowing the room is the trust credential, exactly as it is for the
    // room's lines; every byte in and out is charged to the room's gas.
    // A dropped file is only ever ciphertext here: the browser cuts it
    // into chunks, encrypts each with a key the room already shares, and
    // pins the ciphertext under the digest of the ciphertext itself.
    const blk = url.pathname.match(/^\/room\/([^/]+)\/block\/([0-9a-f]{64})$/);
    if (blk) {
      const room = decodeURIComponent(blk[1]);
      const cid = blk[2];
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
      log.warn("block", "method not allowed", `${roomRef(room)} ${req.method}`);
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

  server.on("upgrade", (req, socket, head) =>
    handleUpgrade(cfg, rooms, req, socket, log, passes, head));
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
const INT05_WS_MAX_DATA = 1048576;
const INT05_WS_MAX_PENDING = 1048590;
const INT05_WS_INCOMPLETE_TIMEOUT_MS = 5000;

const int05Utf8 = new TextDecoder("utf-8", {
  fatal: true,
  ignoreBOM: true
});

function int05CloseFrame(code) {
  const frame = Buffer.alloc(4);
  frame[0] = 0x88;
  frame[1] = 2;
  frame.writeUInt16BE(code, 2);
  return frame;
}

function int05ValidCloseCode(code) {
  if (code >= 3000 && code <= 4999) return true;

  return [
    1000, 1001, 1002, 1003,
    1007, 1008, 1009, 1010,
    1011, 1012, 1013, 1014
  ].includes(code);
}

/*
 * INT05-12D: fail-closed WebSocket frame parser.
 *
 * All complete frames in the supplied buffer are validated
 * before their contents are returned to the application.
 *
 * Fragmented messages are intentionally unsupported.
 */
function wsFrames(buf) {
  const frames = [];
  let off = 0;

  const reject = code => ({
    frames: [],
    used: 0,
    invalid: true,
    code
  });

  while (off + 2 <= buf.length) {
    const b0 = buf[off];
    const b1 = buf[off + 1];

    const fin = (b0 & 0x80) !== 0;
    const rsv = b0 & 0x70;
    const opcode = b0 & 0x0f;
    const masked = (b1 & 0x80) !== 0;

    if (!masked || rsv !== 0) {
      return reject(1002);
    }

    // Fragmented frames and continuation opcodes are unsupported.
    if (!fin || opcode === 0x0) {
      return reject(1002);
    }

    // Only text, close, ping and pong are supported.
    if (![0x1, 0x8, 0x9, 0xa].includes(opcode)) {
      return reject(1002);
    }

    const control = opcode >= 0x8;
    let len = b1 & 0x7f;
    let p = off + 2;

    // Control frames must use the short payload encoding.
    if (control && len > 125) {
      return reject(1002);
    }

    if (len === 126) {
      if (p + 2 > buf.length) break;

      len = buf.readUInt16BE(p);
      p += 2;

      if (len < 126) {
        return reject(1002);
      }
    } else if (len === 127) {
      if (p + 8 > buf.length) break;

      const big = buf.readBigUInt64BE(p);
      p += 8;

      // The high bit is forbidden; oversized frames must
      // be rejected before conversion to Number.
      if (big & (1n << 63n)) {
        return reject(1002);
      }

      if (big < 65536n) {
        return reject(1002);
      }

      if (big > BigInt(INT05_WS_MAX_DATA)) {
        return reject(1009);
      }

      len = Number(big);
    }

    if (control && len > 125) {
      return reject(1002);
    }

    if (!control && len > INT05_WS_MAX_DATA) {
      return reject(1009);
    }

    // Every client frame requires a four-byte masking key.
    if (p + 4 > buf.length) break;

    const mask = buf.subarray(p, p + 4);
    p += 4;

    if (p + len > buf.length) break;

    const data = Buffer.from(buf.subarray(p, p + len));

    for (let i = 0; i < data.length; i++) {
      data[i] ^= mask[i % 4];
    }

    let text = null;

    if (opcode === 0x1) {
      try {
        text = int05Utf8.decode(data);
      } catch {
        return reject(1007);
      }
    }

    if (opcode === 0x8) {
      if (len === 1) {
        return reject(1002);
      }

      if (len >= 2) {
        const code = data.readUInt16BE(0);

        if (!int05ValidCloseCode(code)) {
          return reject(1002);
        }

        try {
          int05Utf8.decode(data.subarray(2));
        } catch {
          return reject(1007);
        }
      }
    }

    off = p + len;

    frames.push({
      opcode,
      data,
      text
    });
  }

  return {
    frames,
    used: off,
    invalid: false,
    code: null
  };
}


/* INT05-D2B-R1: isolated durable WebSocket transport. */
function int05DurableWsUpgrade(cfg, req, socket, head, log) {
  function reject(status, reason) {
    socket.end(
      `HTTP/1.1 ${status} ${reason}\r\n` +
      "Connection: close\r\n" +
      "Content-Length: 0\r\n\r\n"
    );
  }

  let url;
  let room;

  try {
    url = new URL(
      req.url,
      `http://${req.headers.host ?? "localhost"}`
    );
    const match = url.pathname.match(/^\/ws\/([^/]+)$/);
    if (!match) {
      reject(404, "Not Found");
      return;
    }
    room = decodeURIComponent(match[1]);
  } catch {
    reject(400, "Bad Request");
    return;
  }

  const raw = url.searchParams.get("cursor") ?? "0";
  const cursor = Number(raw);

  if (
    !/^(0|[1-9][0-9]*)$/.test(raw) ||
    !Number.isSafeInteger(cursor)
  ) {
    reject(400, "Bad Request");
    return;
  }

  const key = req.headers["sec-websocket-key"];
  const connection = req.headers.connection;

  if (
    typeof key !== "string" ||
    !/^[A-Za-z0-9+/]{22}==$/.test(key) ||
    Buffer.from(key, "base64").length !== 16 ||
    req.headers["sec-websocket-version"] !== "13" ||
    String(req.headers.upgrade).toLowerCase() !== "websocket" ||
    typeof connection !== "string" ||
    !connection.toLowerCase().split(",")
      .some(x => x.trim() === "upgrade")
  ) {
    reject(400, "Bad Request");
    return;
  }

  const authority = cfg.v2Authority;

  if (
    cfg.v2Only !== true ||
    !authority ||
    typeof authority.validate !== "function" ||
    typeof authority.admitDurable !== "function" ||
    typeof authority.readDurable !== "function"
  ) {
    reject(503, "Service Unavailable");
    return;
  }

  const token = readV2Header(req);

  if (token === false || hasLegacyCredential(req)) {
    reject(401, "Unauthorized");
    return;
  }

  let authorized;
  let initial;

  try {
    authorized = authority.validate(token, room);
    if (authorized) {
      initial = authority.readDurable(room, cursor, 100);
    }
  } catch (error) {
    log.error("socket", "durable upgrade failed", error.message);
    reject(503, "Service Unavailable");
    return;
  }

  if (!authorized) {
    reject(401, "Unauthorized");
    return;
  }

  if (!Array.isArray(initial)) {
    reject(503, "Service Unavailable");
    return;
  }

  socket.write(
    "HTTP/1.1 101 Switching Protocols\r\n" +
    "Upgrade: websocket\r\n" +
    "Connection: Upgrade\r\n" +
    `Sec-WebSocket-Accept: ${wsAccept(key)}\r\n\r\n`
  );

  let currentCursor = cursor;
  let pending = Buffer.alloc(0);
  let timer = null;
  let poller = null;
  let closed = false;

  function cleanup() {
    if (closed) return;
    closed = true;
    if (timer !== null) clearTimeout(timer);
    if (poller !== null) clearInterval(poller);
    pending = Buffer.alloc(0);
  }

  function closeWith(code) {
    if (closed) return;
    cleanup();
    socket.end(int05CloseFrame(code));
  }

  function send(value) {
    if (closed || socket.destroyed) return false;
    const ok = socket.write(wsFrame(JSON.stringify(value)));
    if (!ok) {
      closeWith(1013);
      return false;
    }
    return true;
  }

  function sendRows(rows) {
    if (!Array.isArray(rows)) {
      closeWith(1011);
      return false;
    }

    if (rows.length === 0) return true;

    let previous = currentCursor;
    for (const row of rows) {
      if (
        !Number.isSafeInteger(row.sequence) ||
        row.sequence <= previous ||
        !Array.isArray(row.lines)
      ) {
        closeWith(1011);
        return false;
      }
      previous = row.sequence;
    }

    const out = {
      ok: true,
      type: "publications",
      cursor: previous,
      lines: rows.flatMap(x => x.lines),
      publications: rows.map(x => ({
        publicationId: x.publicationId,
        sequence: x.sequence,
        epoch: x.epoch
      })),
      truncated: false
    };

    if (!send(out)) return false;
    currentCursor = previous;
    return true;
  }

  function refresh() {
    if (closed) return;
    try {
      for (let i = 0; i < 4; i++) {
        const rows = authority.readDurable(
          room, currentCursor, 100
        );
        if (!sendRows(rows)) return;
        if (rows.length < 100) return;
      }
    } catch (error) {
      log.error("socket", "durable read failed", error.message);
      closeWith(1011);
    }
  }

  function updateTimer() {
    if (pending.length === 0) {
      if (timer !== null) clearTimeout(timer);
      timer = null;
      return;
    }
    if (timer !== null) return;
    timer = setTimeout(() => {
      timer = null;
      if (!closed && pending.length) closeWith(1002);
    }, INT05_WS_INCOMPLETE_TIMEOUT_MS);
    timer.unref?.();
  }

  function handleChunk(chunk) {
    if (closed) return;

    if (
      pending.length + chunk.length >
      INT05_WS_MAX_PENDING
    ) {
      closeWith(1009);
      return;
    }

    pending = Buffer.concat([pending, chunk]);
    const parsed = wsFrames(pending);

    if (parsed.invalid) {
      closeWith(parsed.code ?? 1002);
      return;
    }

    pending = pending.subarray(parsed.used);
    updateTimer();

    for (const frame of parsed.frames) {
      if (closed) return;
      const { opcode, data, text } = frame;

      if (opcode === 0x8) {
        cleanup();
        socket.end(Buffer.concat([
          Buffer.from([0x88, data.length]), data
        ]));
        return;
      }

      if (opcode === 0x9) {
        if (!socket.write(Buffer.concat([
          Buffer.from([0x8a, data.length]), data
        ]))) {
          closeWith(1013);
        }
        continue;
      }

      if (opcode === 0xa) continue;

      if (opcode !== 0x1) {
        closeWith(1002);
        return;
      }

      let message;
      try {
        message = JSON.parse(text);
      } catch {
        closeWith(1008);
        return;
      }

      if (
        !message ||
        typeof message !== "object" ||
        Array.isArray(message) ||
        typeof message.publicationId !== "string" ||
        !/^[0-9a-f]{32}$/.test(message.publicationId) ||
        !Array.isArray(message.lines) ||
        message.lines.length < 1 ||
        message.lines.length > 100 ||
        !message.lines.every(line =>
          typeof line === "string" &&
          line.length > 0 &&
          line.trim() === line &&
          !/[\r\n]/.test(line) &&
          line.length <= cfg.maxLine &&
          Buffer.byteLength(line, "utf8") <= 4096
        )
      ) {
        closeWith(1008);
        return;
      }

      let result;
      try {
        result = authority.admitDurable(
          token, room, message.lines,
          message.publicationId
        );
      } catch (error) {
        log.error("socket", "durable admission failed", error.message);
        closeWith(1011);
        return;
      }

      if (
        !result?.ok ||
        !Number.isSafeInteger(result.sequence)
      ) {
        closeWith(result?.ok ? 1011 : 1008);
        return;
      }

      if (!send({
        ok: true,
        type: "ack",
        publicationId: message.publicationId,
        cursor: result.sequence,
        accepted: message.lines.length,
        duplicate: result.duplicate,
        passRemaining: result.remaining ?? null
      })) return;

      refresh();
    }
  }

  socket.on("data", handleChunk);
  socket.on("close", cleanup);
  socket.on("error", cleanup);

  if (!sendRows(initial)) return;

  poller = setInterval(refresh, 250);
  poller.unref?.();

  if (head?.length) {
    queueMicrotask(() => {
      if (!closed) handleChunk(head);
    });
  }
}

function handleUpgrade(cfg, rooms, req, socket, log = { info() {}, warn() {}, error() {} }, passes, head) {
  if (cfg.v2Durable === true) {
    int05DurableWsUpgrade(cfg, req, socket, head, log);
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
  const m = url.pathname.match(/^\/ws\/([^/]+)$/);
  const key = req.headers["sec-websocket-key"];
  if (!m || !key) {
    log.warn("relay", "websocket upgrade rejected", "missing room or key");
    socket.destroy();
    return;
  }
  let room;
  try {
    room = decodeURIComponent(m[1]);
  } catch {
    // INT05-SEC-04: malformed room URI must not crash Node.
    socket.end(
      "HTTP/1.1 400 Bad Request\r\n" +
      "Connection: close\r\n" +
      "Content-Length: 0\r\n\r\n"
    );
    return;
  }

  // INT05: fail closed if admission enforcement is unavailable.
  if (!passes || typeof passes.admit !== "function") {
    socket.destroy();
    return;
  }

  // Validate authorization before accepting the upgrade.
  const v2Token = cfg.v2Only === true
    ? readV2Header(req)
    : null;

  const pass = cfg.v2Only === true
    ? null
    : readPassHeader(req, room, log);

  let authorized = (
    pass !== false &&
    (
      cfg.v2Only === true
        ? v2Token !== false &&
          !hasLegacyCredential(req)
        : req.headers["x-kant-v2"] === undefined
    )
  );

  if (authorized && cfg.v2Only === true) {
    try {
      authorized = cfg.v2Authority.validate(
        v2Token, room
      );
    } catch (error) {
      log.error(
        "socket",
        "v2 validation failed",
        error.message
      );

      socket.end(
        "HTTP/1.1 503 Service Unavailable\r\n" +
        "Connection: close\r\n" +
        "Content-Length: 0\r\n\r\n"
      );
      return;
    }
  }

  if (!authorized) {
    socket.end(
      "HTTP/1.1 401 Unauthorized\r\n" +
      "Connection: close\r\n" +
      "Content-Length: 0\r\n\r\n"
    );
    return;
  }

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
  let incompleteTimer = null;
  let closing = false;

  function clearIncompleteTimer() {
    if (incompleteTimer !== null) {
      clearTimeout(incompleteTimer);
      incompleteTimer = null;
    }
  }

  function closeWithCode(code) {
    if (closing) return;

    closing = true;
    clearIncompleteTimer();
    pending = Buffer.alloc(0);

    socket.end(int05CloseFrame(code));
  }

  function refreshIncompleteTimer() {
    if (pending.length === 0) {
      clearIncompleteTimer();
      return;
    }

    if (incompleteTimer !== null) return;

    incompleteTimer = setTimeout(() => {
      incompleteTimer = null;

      if (!closing && pending.length > 0) {
        closeWithCode(1002);
      }
    }, INT05_WS_INCOMPLETE_TIMEOUT_MS);

    incompleteTimer.unref?.();
  }

  socket.on("data", chunk => {
    if (closing) return;

    // Bound buffering before allocating the concatenated buffer.
    if (
      pending.length + chunk.length >
      INT05_WS_MAX_PENDING
    ) {
      closeWithCode(1009);
      return;
    }

    pending = Buffer.concat([pending, chunk]);

    const result = wsFrames(pending);

    if (result.invalid) {
      closeWithCode(result.code ?? 1002);
      return;
    }

    pending = pending.subarray(result.used);

    refreshIncompleteTimer();

    // Parser validation is complete for all available frames.
    // Only now may application-side effects occur.
    for (const { opcode, data, text } of result.frames) {
      if (closing) return;

      if (opcode === 0x8) {
        closing = true;
        clearIncompleteTimer();
        pending = Buffer.alloc(0);

        socket.end(
          Buffer.concat([
            Buffer.from([0x88, data.length]),
            data
          ])
        );
        return;
      }

      if (opcode === 0x9) {
        socket.write(
          Buffer.concat([
            Buffer.from([0x8a, data.length]),
            data
          ])
        );
        continue;
      }

      if (opcode === 0xa) {
        continue;
      }

      if (opcode === 0x1) {
        const lines = text.split("\n")
          .map(l => l.trim())
          .filter(l =>
            l.length > 0 &&
            l.length <= cfg.maxLine
          );

        if (!lines.length) continue;

        const sender = senderOf(lines) ??
          `ip:${req.socket.remoteAddress ?? "?"}`;

        let verdict;

        try {
          verdict = cfg.v2Only === true
            ? cfg.v2Authority.admit(
                v2Token, room, lines.length
              )
            : passes.admit({
                pass,
                sender,
                room,
                lines: lines.length
              });
        } catch (error) {
          log.error(
            "socket",
            "admission failed",
            error.message
          );

          closeWithCode(1011);
          return;
        }

        if (!verdict || !verdict.ok) {
          log.warn(
            "socket",
            "message admission rejected",
            roomRef(room)
          );

          closeWithCode(1008);
          return;
        }

        rooms.post(room, lines);
      }
    }
  });

  const drop = () => {
    clearIncompleteTimer();
    pending = Buffer.alloc(0);
    closing = true;
    r.sockets.delete(state);
  };

  socket.on("close", () => {
    log.info("socket", "a stream closed", roomRef(room));
    drop();
  });

  socket.on("error", error => {
    log.error(
      "socket",
      "a stream failed",
      error.message
    );
    drop();
  });

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
  });
}
