// worker.js — the same kant-zk rendezvous relay, on Cloudflare.
//
// One Durable Object per room holds the append-only log; the Worker in
// front of it is pure routing.  The protocol is identical to the Node
// relay in `server/relay.mjs`, so a client cannot tell them apart:
//
//   GET  /health                          -> { ok, name, version }
//   POST /room/{room}   body: lines       -> { ok, cursor, accepted }
//   POST may carry `x-kant-pass` (a kzpass: a limited invite) or
//   `x-kant-invite` (the owner's unlimited kzinvite).  The pass is
//   verified and its spend counted here — the same rules as the Node
//   relay's PassStore, so the twins agree on what a pass buys.
//   GET  /room/{room}?cursor=N[&wait=S]   -> { ok, cursor, lines, truncated }
//   WS   /ws/{room}?cursor=N              -> pushes { ok, cursor, lines }
//
// The relay never parses a line and never learns a room secret: a room
// name is the digest of that secret, computed in the browser.  Clients
// re-check every line against its own witness (`Kant.Relay.parseMsg`), so
// a hostile or compromised relay can drop lines but cannot forge them.
//
// Deploy:  cd server && npx wrangler deploy

import { makeStore } from "./store.js";

const VERSION = "1.0.0";
// Which build is this? The systemd twin reads its checkout, but a Worker
// has no filesystem, so the commit is injected at build time
// (`wrangler deploy --var` / deploy-cloudflare-worker.sh). Without it a
// stale twin is indistinguishable from a current one — both used to answer
// version "1.0.0" while serving different wasm.
const COMMIT = "__KANT_COMMIT__";
const MAX_LINE = 262144;
const MAX_BODY = 1048576;

// Storage limits and commit cadence. The cadence is what keeps a burst of
// posts from turning into a burst of Durable Object writes: the old code
// persisted the whole log on every POST and every socket message, so the cost
// of one append scaled with the size of the room rather than the size of the
// change. Overridable per deployment, so the tradeoff can be tuned against the
// `/stats` numbers without a code change -- see `configFrom`.
const DEFAULT_LIMITS = { maxLines: 4096, maxBytes: 8 * 1024 * 1024 };
const DEFAULT_COMMIT = { every: 8, intervalMs: 2000 };

/**
 * Resolve storage config from the environment.
 *
 * Read per request rather than at module scope: a Worker has no `process`, and
 * `env` is the only place deployment config actually arrives. Parsed with a
 * fallback rather than `Number(...)` alone, because `Number(undefined)` is NaN
 * and a NaN cadence would compare false forever -- silently disabling every
 * commit, which is the failure this whole change exists to prevent.
 */
function configFrom(env) {
  const num = (v, d) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : d;
  };
  return {
    mode: env?.RELAY_MODE || undefined,
    limits: {
      maxLines: num(env?.RELAY_MAX_LINES, DEFAULT_LIMITS.maxLines),
      maxBytes: num(env?.RELAY_MAX_BYTES, DEFAULT_LIMITS.maxBytes),
    },
    commit: {
      every: num(env?.RELAY_COMMIT_EVERY, DEFAULT_COMMIT.every),
      intervalMs: num(env?.RELAY_COMMIT_INTERVAL_MS, DEFAULT_COMMIT.intervalMs),
    },
  };
}

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, x-kant-pass, x-kant-invite",
  "access-control-max-age": "86400",
};

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });

// ------------------------------------------------------------ kzpass
//
// A minimal, self-contained verifier for the pass codes of
// `web/kant-pass.mjs` (the worker is a single file, so the codec is
// inlined rather than imported).  Only what the relay needs to check
// is here: parse the envelope, recompute the signature, count spends.

const FNV_OFFSET = 14695981039346656037n;
const FNV_PRIME = 1099511628211n;
const MASK64 = (1n << 64n) - 1n;

function fnv1a(bytes) {
  let h = FNV_OFFSET;
  for (const b of bytes) h = ((h ^ BigInt(b & 0xff)) * FNV_PRIME) & MASK64;
  return h;
}

/** The 32-byte digest `witness()` hex-encodes (kantzk.mjs `digest`). */
function digestBytes(bytes) {
  const out = [];
  for (let i = 0; i < 4; i++) {
    let h = fnv1a([i, ...bytes]);
    for (let j = 7; j >= 0; j--) out.push(Number((h >> BigInt(8 * j)) & 0xffn));
  }
  return out;
}

const hexDec = (s) => {
  if (s.length % 2 || !/^[0-9a-f]*$/.test(s)) return null;
  const out = [];
  for (let i = 0; i < s.length; i += 2) out.push(parseInt(s.slice(i, i + 2), 16));
  return out;
};

const bytesEq = (a, b) => Array.isArray(a) && Array.isArray(b) &&
  a.length === b.length && a.every((x, i) => x === b[i]);

const ascii = (b) => Array.from(b, (x) => String.fromCharCode(x)).join("");

/**
 * Parse a kzpass (limited) or kzinvite (unlimited, limit 0) code.
 * Returns { secret, limit, id, sig } or null.  Room-membership fields
 * (relay, peer, addrs) are not needed for enforcement.
 */
function parsePassCode(s) {
  const parts = String(s).split(":");
  if (parts.length < 4) return null;
  const tag = ascii(hexDec(parts[0]) ?? []);
  const relay = hexDec(parts[1]);
  const secret = hexDec(parts[2]);
  if (!relay || !secret) return null;
  if (tag === "kzinvite") return { secret, limit: 0 };
  if (tag !== "kzpass" || parts.length < 7) return null;
  // fields: relay, secret, peer, [addrs…] — the last three are limit, id, sig.
  const limitF = hexDec(parts[parts.length - 3]);
  const id = hexDec(parts[parts.length - 2]);
  const sig = hexDec(parts[parts.length - 1]);
  if (!limitF || !id || !sig) return null;
  const limit = limitF.reduce((a, x) => a * 256 + x, 0);
  if (limit < 1 || id.length !== 16 || sig.length !== 32) return null;
  return { secret, limit, id, sig };
}

/** The room a pass opens: witness(secret), hex. */
function passRoom(pass) {
  return digestBytes(pass.secret).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Does the pass prove it was minted from its own secret? */
function passOk(pass) {
  const sep = [0];
  const expect = digestBytes([...pass.secret, ...sep, ...pass.id, ...sep,
    ...natBytes(pass.limit)]);
  return bytesEq(pass.sig, expect);
}

const natBytes = (n) => {
  const out = [];
  let x = n;
  do { out.unshift(x % 256); x = Math.floor(x / 256); } while (x > 0);
  return out;
};

/** The kzchat sender inside a line, if any (for the passless rate limit). */
function senderOfLine(line) {
  const parts = line.split(":");
  if (ascii(hexDec(parts[0]) ?? []) !== "kzchat" || parts.length < 4) return null;
  const sender = hexDec(parts[2]);
  return sender ? ascii(sender) : null;
}

const PEER_LIMIT = 10;
const PEER_WINDOW_MS = 10 * 60 * 1000;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const start = Date.now();

    if (request.method === "OPTIONS") {
      console.log("OPTIONS", request.url);
      return new Response(null, { status: 204, headers: CORS });
    }

    if (url.pathname === "/health") {
      console.log("HEALTH", request.url);
      const cfg = configFrom(env);
      return json({
        ok: true, name: "kant-zk-relay", version: VERSION, commit: COMMIT,
        platform: "cloudflare",
        // Announced, not inferred. A peer cannot tell the two modes apart from
        // the wire, so `durable` here is what tells it whether a cursor is a
        // promise or a hint.
        durable: Boolean(env?.ROOMS) && cfg.mode !== "rendezvous",
        mode: cfg.mode ?? (env?.ROOMS ? "mailbox" : "rendezvous"),
        commit: cfg.commit,
      });
    }

    const m = url.pathname.match(/^\/(room|ws|stats)\/([^/]+)$/);
    if (!m) {
      console.log("404", request.url, "method=", request.method);
      return json({ ok: false, error: "not found" }, 404);
    }

    const [, kind, roomRaw] = m;
    const room = decodeURIComponent(roomRaw);
    if (!env.ROOMS) {
      // No Durable Object bound: routing has nowhere to send a room, and
      // saying so plainly beats a 500 from `idFromName` on undefined.
      return json({ ok: false, error: "no ROOMS binding: this deployment has no relay storage" }, 503);
    }
    const id = env.ROOMS.idFromName(room);
    console.log("ROUTE", kind, room, "url=", request.url, "method=", request.method);

    try {
      const resp = await env.ROOMS.get(id).fetch(request);
      const ms = Date.now() - start;
      console.log("RESPONSE", kind, room, "status=", resp.status, "ms=", ms);
      return resp;
    } catch (e) {
      console.log("ERROR", kind, room, "url=", request.url, "err=", e?.message ?? e);
      return json({ ok: false, error: String(e?.message ?? e) }, 500);
    }
  },
};

/**
 * One room: storage, some pollers, some sockets.
 *
 * The log lives in `this.store`, not in fields here. `worker.js` decides what
 * a room means; `store.js` decides where those lines live and when they are
 * written. That split is what lets the same room code run with a Durable
 * Object behind it and without one.
 */
export class Room {
  constructor(state, env) {
    this.state = state;
    this.sockets = new Set(); // { ws, cursor }
    this.waiters = new Set();
    const cfg = configFrom(env ?? state?.env);
    this.store = makeStore({
      mode: cfg.mode,
      env,
      // `state` is what makes the store durable; without it, mailbox mode
      // would have nothing to write to and `makeStore` refuses rather than
      // quietly downgrading to a store that loses everything.
      state,
      limits: cfg.limits,
      commit: cfg.commit,
    });
    this.loaded = this.state.blockConcurrencyWhile(() => this.store.ready());
    console.log("ROOM_INIT", "mode=", this.store.report().mode,
      "cursor=", this.store.report().cursor);
  }

  /**
   * Commit if the cadence says so.
   *
   * The cadence is what this replaced: `await this.persist()` ran on every
   * POST and every socket message, writing the entire log each time.
   */
  async persist() {
    if (!this.store.dueForCommit()) return false;
    return this.store.commit();
  }

  /**
   * Admit one POST under the pass rules.  Pass spends live in DO
   * storage (`pass:<id>` -> { spent, limit }), the passless rate
   * limit in `peerPosts` (sender -> timestamps).  Same rules as the
   * Node relay's PassStore: the twins agree on what a pass buys.
   */
  async admitPass(pass, lines, roomName) {
    const now = Date.now();
    if (pass && pass.limit > 0) {
      const key = "pass:" + pass.id.map((b) => b.toString(16).padStart(2, "0")).join("");
      const cur = (await this.state.storage.get(key)) ?? { spent: 0, limit: pass.limit };
      if (cur.spent >= cur.limit) {
        return { ok: false, status: 429, error: `pass spent (${cur.limit} post(s) allowed)` };
      }
      cur.spent += 1;
      await this.state.storage.put(key, cur);
      return { ok: true, remaining: cur.limit - cur.spent };
    }
    // No pass (or the owner's unlimited invite): per-sender rate limit.
    const sender = lines.map(senderOfLine).find((s) => s != null) ?? "anonymous";
    this.peerPosts ??= new Map();
    const win = this.peerPosts.get(sender) ?? [];
    const kept = win.filter((t) => t >= now - PEER_WINDOW_MS);
    if (kept.length + lines.length > PEER_LIMIT) {
      return { ok: false, status: 429,
        error: `rate limit: ${PEER_LIMIT} posts per 10 min` };
    }
    for (let i = 0; i < lines.length; i++) kept.push(now);
    this.peerPosts.set(sender, kept);
    return { ok: true, remaining: PEER_LIMIT - kept.length };
  }

  fetchFrom(cursor) {
    const out = this.store.fetchFrom(cursor);
    console.log("ROOM_FETCH", "cursor=", cursor, "->", out.cursor, "lines=", out.lines.length, "truncated=", out.truncated);
    return out;
  }

  append(lines) {
    const { cursor, dropped } = this.store.append(lines);
    console.log("ROOM_APPEND", "accepted=", lines.length, "cursor=", cursor, "dropped=", dropped);
    for (const w of [...this.waiters]) { this.waiters.delete(w); w(); }
    for (const s of [...this.sockets]) {
      const out = this.fetchFrom(s.cursor);
      s.cursor = out.cursor;
      if (out.lines.length) {
        try { s.ws.send(JSON.stringify({ ok: true, ...out })); } catch { this.sockets.delete(s); }
      }
    }
    return cursor;
  }

  wait(ms) {
    return new Promise((resolve) => {
      const done = () => { this.waiters.delete(done); resolve(); };
      this.waiters.add(done);
      setTimeout(done, ms);
    });
  }

  async fetch(request) {
    await this.loaded;
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/(?:room|ws|stats)\/([^/]+)$/);
    const roomName = m ? decodeURIComponent(m[1]) : "";
    const started = Date.now();

    if (url.pathname.startsWith("/stats/")) {
      // What the storage split exists to make visible: how much is committed,
      // how much is exposed, how many writes the cadence has saved, and --
      // crucially -- whether loss is measurable at all in this mode.
      const report = this.store.report();
      console.log("ROOM_STATS", JSON.stringify(report));
      return json({ ok: true, room: roomName, ...report });
    }

    if (url.pathname.startsWith("/ws/")) {
      console.log("ROOM_UPGRADE", url.pathname);
      return this.upgrade(request, url);
    }

    if (request.method === "POST") {
      const body = await request.text();
      if (body.length > MAX_BODY) {
        console.log("ROOM_POST", "413 body too large", body.length);
        return json({ ok: false, error: "body too large" }, 413);
      }
      const lines = body.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
      if (lines.some((l) => l.length > MAX_LINE)) {
        console.log("ROOM_POST", "413 line too long");
        return json({ ok: false, error: "line too long" }, 413);
      }
      // Pass + rate limiting (mirrors the Node relay's PassStore).
      const rawPass = request.headers.get("x-kant-pass") ?? request.headers.get("x-kant-invite");
      let pass = null;
      if (rawPass != null) {
        pass = parsePassCode(rawPass);
        if (!pass || passRoom(pass) !== roomName || (pass.limit > 0 && !passOk(pass))) {
          console.log("ROOM_POST", "401 bad pass");
          return json({ ok: false, error: "bad pass" }, 401);
        }
      }
      const verdict = await this.admitPass(pass, lines, roomName);
      if (!verdict.ok) {
        console.log("ROOM_POST", verdict.status, verdict.error);
        return json({ ok: false, error: verdict.error }, verdict.status);
      }
      const cursor = this.append(lines);
      // Cadence, not per-request. A caller that needs the post durable can
      // force it; the default trades a bounded window of exposure for a large
      // drop in Durable Object writes, and `/stats` reports what that window
      // currently costs.
      await this.persist();
      const ms = Date.now() - started;
      console.log("ROOM_POST", "cursor=", cursor, "accepted=", lines.length, "ms=", ms);
      return json({ ok: true, cursor, accepted: lines.length, passRemaining: verdict.remaining });
    }

    if (request.method === "GET") {
      const cursor = Number(url.searchParams.get("cursor") ?? 0) || 0;
      const wait = Math.min(Number(url.searchParams.get("wait") ?? 0) || 0, 30);
      let out = this.fetchFrom(cursor);
      if (wait > 0 && out.lines.length === 0) {
        console.log("ROOM_GET", "wait=", wait, "cursor=", cursor);
        await this.wait(wait * 1000);
        out = this.fetchFrom(cursor);
      }
      const ms = Date.now() - started;
      console.log("ROOM_GET", "cursor=", cursor, "->", out.cursor, "lines=", out.lines.length, "ms=", ms);
      return json({ ok: true, ...out });
    }

    console.log("ROOM_METHOD_NOT_ALLOWED", request.method, url.pathname);
    return json({ ok: false, error: "method not allowed" }, 405);
  }

  upgrade(request, url) {
    if (request.headers.get("upgrade") !== "websocket") {
      return json({ ok: false, error: "expected websocket" }, 426);
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();

    const entry = { ws: server, cursor: Number(url.searchParams.get("cursor") ?? 0) || 0 };
    this.sockets.add(entry);

    const first = this.fetchFrom(entry.cursor);
    entry.cursor = first.cursor;
    if (first.lines.length) server.send(JSON.stringify({ ok: true, ...first }));

    server.addEventListener("message", async (ev) => {
      const text = typeof ev.data === "string" ? ev.data : "";
      const lines = text.split("\n").map((l) => l.trim())
        .filter((l) => l.length > 0 && l.length <= MAX_LINE);
      if (lines.length) { this.append(lines); await this.persist(); }
    });
    const drop = () => this.sockets.delete(entry);
    server.addEventListener("close", drop);
    server.addEventListener("error", drop);

    return new Response(null, { status: 101, webSocket: client });
  }
}
