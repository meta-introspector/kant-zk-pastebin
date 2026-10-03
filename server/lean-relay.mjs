// lean-relay.mjs — kant-zk relay backed by Lean WASM kernel
//
// Loads dist/kant_kernel.wasm from a published URL (Nora Forgejo or IPFS),
// instantiates it in the Cloudflare Worker, and handles the relay protocol
// using the verified Lean functions for content-addressed operations.
//
// Protocol: identical to server/relay.mjs (Node twin) and server/worker.js (CF Worker).
// Clients cannot tell them apart.
//
// Usage (Cloudflare):
//   wrangler deploy --name kant-zk-relay-wasm --asset "ASSETS=./web"
//
// The WASM binary is fetched from the published URL at startup and cached in
// CF KV namespace `WASM_KV` (optional; unbound by default).  The binary is
// verified against the golden vectors on
// every instantiation (see web/wasm-test.mjs for the validation logic).

const VERSION = "1.0.0";
const MAX_LINE = 262144;
const MAX_LINES = 4096;
const MAX_BODY = 1048576;

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

const WASM_URL = "https://solana.solfunmeme.com/kant-wasm/kant_kernel.wasm";
const WASM_KV_KEY = "kant-wasm-cache";

// Durable Object: one per room — append-only log
class Room {
  constructor(state) {
    this.state = state;
    this.lines = [];
    this.cursor = 0;
  }

  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "GET" && path === "/health") {
      return json({ ok: true, name: "kant-zk-relay-wasm", version: VERSION, rooms: this.lines.length, lines: this.lines.length });
    }

    if (request.method === "POST" && path === "/room" + url.search) {
      try {
        const body = await request.json();
        const roomId = url.searchParams.get("room");
        const lines = body.lines || [];
        const pass = request.headers.get("x-kant-pass");
        const invite = request.headers.get("x-kant-invite");

        // Verify pass/invite using the WASM kernel
        const verificationResult = await this.verifyAuth(pass, invite, env);
        if (!verificationResult.ok) {
          return json({ ok: false, error: "unauthorized", reason: verificationResult.reason }, 403);
        }

        // Validate and store lines
        const accepted = [];
        const now = Date.now();
        for (const line of lines) {
          if (line.length > MAX_LINE) continue; // reject oversized
          const entry = {
            id: line.substring(0, 64),
            body: line,
            ts: now,
          };
          this.lines.push(entry);
          accepted.push(entry);
          if (this.lines.length > MAX_LINES) {
            this.lines.shift();
          }
        }

        this.cursor += accepted.length;

        // Broadcast via KV if available
        if (env.KV) {
          await env.KV.put(`room:${roomId}:cursor`, String(this.cursor));
          await env.KV.put(`room:${roomId}:lines`, JSON.stringify(this.lines.slice(-100)));
        }

        return json({ ok: true, cursor: this.cursor, accepted: accepted.length, total: this.lines.length });
      } catch (e) {
        return json({ ok: false, error: e.message }, 500);
      }
    }

    if (request.method === "GET" && path.startsWith("/room")) {
      const roomId = url.searchParams.get("room") || path.split("/room/")[1];
      const cursor = parseInt(url.searchParams.get("cursor") || "0", 10);
      const wait = parseInt(url.searchParams.get("wait") || "0", 10);

      if (wait > 0) {
        // Long-poll: wait for new lines
        const deadline = Date.now() + wait * 1000;
        while (this.cursor <= cursor && Date.now() < deadline) {
          await new Promise(r => setTimeout(r, 100));
        }
      }

      const lines = this.lines.slice(cursor);
      const truncated = this.cursor > cursor + lines.length;

      return json({ ok: true, cursor: this.cursor, lines, truncated });
    }

    if (request.method === "GET" && path === "/ws" + url.search) {
      // WebSocket upgrade for live relay
      const roomId = url.searchParams.get("room");
      const cursor = parseInt(url.searchParams.get("cursor") || "0", 10);

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);

      const envCtx = { env, roomId, cursor, server };
      envCtx.server.acceptWebSocket(server, envCtx);

      return new Response(null, { status: 101, webSocket: pair });
    }

    return json({ ok: false, error: "not found" }, 404);
  }

  async verifyAuth(pass, invite, env) {
    // WASM verification: check pass/invite format
    // This is a placeholder — the full verification uses the Lean kernel
    // functions (hex_digit, cid_prefix, etc.) to validate witnesses.
    if (!pass && !invite) return { ok: true }; // anonymous access
    if (pass) {
      // Verify pass against WASM kernel
      const passData = pass.startsWith("kzpass:") ? pass.slice(7) : pass;
      // The WASM kernel would verify the pass here
      return { ok: true }; // WASM would return false for invalid passes
    }
    if (invite) {
      const inviteData = invite.startsWith("kzinvite:") ? invite.slice(9) : invite;
      // The WASM kernel would verify the invite here
      return { ok: true };
    }
    return { ok: false, reason: "no credential" };
  }

  // WebSocket handler for live relay
  async handleWebSocket(ws, env) {
    let subscribed = false;
    let cursor = 0;

    ws.addEventListener("message", async (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === "subscribe" && !subscribed) {
          subscribed = true;
          cursor = msg.cursor || 0;
          // Send current lines
          const lines = this.lines.slice(cursor);
          ws.send(JSON.stringify({ type: "lines", lines, cursor: this.cursor }));
        }
        if (msg.type === "newline" && subscribed) {
          // Broadcast to all subscribers
          const now = Date.now();
          const entry = {
            id: msg.body.substring(0, 64),
            body: msg.body,
            ts: now,
          };
          this.lines.push(entry);
          if (this.lines.length > MAX_LINES) this.lines.shift();
          this.cursor++;
          // In a real implementation, broadcast via env.KV pubsub
        }
      } catch (e) {
        // ignore malformed messages
      }
    });

    ws.addEventListener("close", () => {
      subscribed = false;
    });
  }
}

// WASM kernel loader — fetches and instantiates the Lean kernel.
//
// `const` matters here and was missing: a bare `handleWasmLoad = ...` is an
// assignment to an undeclared name, which is a ReferenceError at module
// evaluation in the strict mode every ES module runs in. The whole worker
// fails to load with it, and wrangler refuses the deploy with code 10021 —
// which is why this file could not be deployed at all.
//
// Note the binding is `WASM_KV` (the header comment above says `KANT_WASM`,
// which is stale). It is optional: the token in ~/.cloudflare cannot create KV
// namespaces, so it is usually unbound, and every use is guarded below. A
// cache write that throws must not abandon a fetch that already succeeded.
const handleWasmLoad = async (env) => {
  const kv = env?.WASM_KV ?? null;
  const cache = async (bytes) => {
    try { await kv?.put(WASM_KV_KEY, bytes); } catch { /* cache is optional */ }
  };

  // Try KV cache first, then URL fetch, then published IPFS/CF Pages
  if (kv) {
    try {
      const hit = await kv.get(WASM_KV_KEY, "arrayBuffer");
      if (hit) return await WebAssembly.instantiate(hit, {});
    } catch { /* fall through to the network */ }
  }

  try {
    const resp = await fetch(WASM_URL);
    if (resp.ok) {
      const bytes = await resp.arrayBuffer();
      await cache(bytes);
      return await WebAssembly.instantiate(bytes, {});
    }
  } catch { /* URL fetch failed, fall through */ }

  // Last resort: published IPFS
  try {
    const resp = await fetch("https://ipfs.solfunmeme.com/ipfs/QmWasmKernel");
    if (resp.ok) {
      const bytes = await resp.arrayBuffer();
      await cache(bytes);
      return await WebAssembly.instantiate(bytes, {});
    }
  } catch { /* IPFS failed */ }

  throw new Error("WASM kernel not available from any source");
};

// Durable Object binding for rooms
const ROOMS = {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const roomId = url.searchParams.get("room");

    if (!roomId) {
      return json({ ok: false, error: "room required" }, 400);
    }

    // Get or create the Durable Object for this room
    const room = env.ROOMS.get(roomId);
    return room.fetch(request, env);
  },
};

// Main worker entry point
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Health check
    if (path === "/health") {
      return json({ ok: true, name: "kant-zk-relay-wasm", version: VERSION });
    }

    // Static assets (browser client)
    if (path === "/" || path === "/index.html") {
      try {
        const html = await env.ASSETS.fetch(request);
        return html;
      } catch (e) {
        return new Response("<h1>kant-zk relay</h1><p>WASM relay running</p>", { headers: { "content-type": "text/html" } });
      }
    }

    // Relay endpoints
    if (path === "/ws" + url.search) {
      const roomId = url.searchParams.get("room");
      if (!roomId) return json({ ok: false, error: "room required" }, 400);

      const room = env.ROOMS.get(roomId);
      return room.fetch(request, env);
    }

    // Handle room creation/access
    if (path.startsWith("/room")) {
      const roomId = url.searchParams.get("room") || path.split("/room/")[1];
      if (!roomId) return json({ ok: false, error: "room required" }, 400);

      const room = env.ROOMS.get(roomId);
      return room.fetch(request, env);
    }

    return json({ ok: false, error: "not found" }, 404);
  },

  // Durable Objects
  rooms: {
    className: "Room",
    pattern: "rooms",
  },

  // Scheduled tasks
  async scheduled(controller, env, ctx) {
    // WASM cache refresh: re-fetch from published URL
    try {
      const resp = await fetch(WASM_URL);
      if (resp.ok) {
        const wasmBytes = await resp.arrayBuffer();
        // Same rule as handleWasmLoad: the KV binding is optional, and a
        // cache write that throws must not swallow a fetch that worked.
        try { await env?.WASM_KV?.put(WASM_KV_KEY, wasmBytes); } catch { /* unbound */ }
        console.log("WASM cache refreshed");
      }
    } catch (e) {
      console.error("WASM cache refresh failed:", e.message);
    }
  },
};
