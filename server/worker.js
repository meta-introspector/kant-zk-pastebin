// worker.js — the same kant-zk rendezvous relay, on Cloudflare.
//
// One Durable Object per room holds the append-only log; the Worker in
// front of it is pure routing.  The protocol is identical to the Node
// relay in `server/relay.mjs`, so a client cannot tell them apart:
//
//   GET  /health                          -> { ok, name, version }
//   POST /room/{room}   body: lines       -> { ok, cursor, accepted }
//   GET  /room/{room}?cursor=N[&wait=S]   -> { ok, cursor, lines, truncated }
//   WS   /ws/{room}?cursor=N              -> pushes { ok, cursor, lines }
//
// The relay never parses a line and never learns a room secret: a room
// name is the digest of that secret, computed in the browser.  Clients
// re-check every line against its own witness (`Kant.Relay.parseMsg`), so
// a hostile or compromised relay can drop lines but cannot forge them.
//
// Deploy:  cd server && npx wrangler deploy

const VERSION = "1.0.0";
const MAX_LINE = 262144;
const MAX_LINES = 4096;
const MAX_BODY = 1048576;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400",
};

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });

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
      return json({ ok: true, name: "kant-zk-relay", version: VERSION, platform: "cloudflare" });
    }

    const m = url.pathname.match(/^\/(room|ws)\/([^/]+)$/);
    if (!m) {
      console.log("404", request.url, "method=", request.method);
      return json({ ok: false, error: "not found" }, 404);
    }

    const [, kind, roomRaw] = m;
    const room = decodeURIComponent(roomRaw);
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

/** One room: an append-only log, some pollers, some sockets. */
export class Room {
  constructor(state) {
    this.state = state;
    this.base = 0;
    this.lines = [];
    this.sockets = new Set(); // { ws, cursor }
    this.waiters = new Set();
    this.loaded = this.state.blockConcurrencyWhile(async () => {
      const kept = await this.state.storage.get("log");
      if (kept) { this.base = kept.base; this.lines = kept.lines; }
    });
    console.log("ROOM_INIT", "loaded=", this.lines.length, "base=", this.base);
  }

  async persist() {
    await this.state.storage.put("log", { base: this.base, lines: this.lines });
    console.log("ROOM_PERSIST", "lines=", this.lines.length, "base=", this.base);
  }

  fetchFrom(cursor) {
    const end = this.base + this.lines.length;
    const from = Math.max(cursor, this.base);
    const out = { cursor: end, lines: this.lines.slice(from - this.base), truncated: cursor < this.base };
    console.log("ROOM_FETCH", "cursor=", cursor, "->", out.cursor, "lines=", out.lines.length, "truncated=", out.truncated);
    return out;
  }

  append(lines) {
    for (const l of lines) this.lines.push(l);
    if (this.lines.length > MAX_LINES) {
      const drop = this.lines.length - MAX_LINES;
      this.lines.splice(0, drop);
      this.base += drop;
    }
    console.log("ROOM_APPEND", "accepted=", lines.length, "total=", this.lines.length, "base=", this.base);
    for (const w of [...this.waiters]) { this.waiters.delete(w); w(); }
    for (const s of [...this.sockets]) {
      const out = this.fetchFrom(s.cursor);
      s.cursor = out.cursor;
      if (out.lines.length) {
        try { s.ws.send(JSON.stringify({ ok: true, ...out })); } catch { this.sockets.delete(s); }
      }
    }
    return this.base + this.lines.length;
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
    const started = Date.now();

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
      const cursor = this.append(lines);
      await this.persist();
      const ms = Date.now() - started;
      console.log("ROOM_POST", "cursor=", cursor, "accepted=", lines.length, "ms=", ms);
      return json({ ok: true, cursor, accepted: lines.length });
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
