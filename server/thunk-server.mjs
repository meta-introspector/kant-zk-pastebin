#!/usr/bin/env node
// server/thunk-server.mjs — HTTP thunk server that meshes with the chat relay.
//
// This server:
// 1. Exposes HTTP endpoints for thunk operations (store, run, share, list)
// 2. Publishes its presence to a discovery room in the relay
// 3. Listsens for thunk traffic and responds
// 4. Multiple instances can coexist, discovered via relay pub/sub
//
// Mesh protocol with relay.mjs:
//   - Connects to /ws/{room} for streaming updates
//   - Publishes presence to /room/{discovery-room} via POST
//   - Receives commands via WebSocket stream

import http from "node:http";
import { URL } from "node:url";
import { ThunkStore } from "./thunk-store.mjs";
import { Schedule } from "./schedule.mjs";
import { Thunk } from "./thunk.mjs";

const DEFAULT_PORT = process.env.THUNK_SERVER_PORT ? Number(process.env.THUNK_SERVER_PORT) : 9787;
const RELAY_URL = process.env.RELAY_URL || "http://localhost:8787";
const DISCOVERY_ROOM = process.env.DISCOVERY_ROOM || "thunk-servers";
const SERVER_ID = process.env.SERVER_ID || `thunk-${Math.random().toString(36).slice(2, 10)}`;

class ThunkServer {
  constructor({ thunkStore, schedule, port, relayUrl, discoveryRoom, serverId }) {
    this.thunkStore = thunkStore;
    this.schedule = schedule;
    this.port = port;
    this.relayUrl = relayUrl;
    this.discoveryRoom = discoveryRoom;
    this.serverId = serverId;
    this.httpServer = null;
    this.ws = null;
    this.peers = new Map();
    this.running = false;
  }

  async start() {
    this.running = true;

    // Start HTTP server for thunk operations
    this.httpServer = http.createServer(async (req, res) => {
      await this.handleRequest(req, res);
    });

    await new Promise((resolve) => {
      this.httpServer.listen(this.port, () => {
        console.log(`[thunk-server] HTTP server listening on :${this.port}`);
        resolve();
      });
    });

    // Publish presence to relay
    await this.publishPresence();

    // Connect to relay WebSocket for mesh
    await this.connectToRelay();

    console.log(`[thunk-server] ${this.serverId} is ready — serving thunks on :${this.port}`);
  }

  async stop() {
    this.running = false;
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    if (this.httpServer) {
      await new Promise((resolve) => {
        this.httpServer.close(() => resolve());
      });
      this.httpServer = null;
    }
    console.log(`[thunk-server] ${this.serverId} stopped`);
  }

  async publishPresence() {
    const presence = JSON.stringify({
      type: "thunk-server-ping",
      serverId: this.serverId,
      endpoint: `http://localhost:${this.port}`,
      timestamp: Date.now(),
    });

    try {
      const url = new URL(`${this.relayUrl}/room/${this.discoveryRoom}`);
      url.searchParams.set("cursor", "0");
      await fetch(url.toString(), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: presence,
      });
      console.log(`[thunk-server] published presence to discovery room`);
    } catch (e) {
      console.error(`[thunk-server] failed to publish presence: ${e.message}`);
    }
  }

  async connectToRelay() {
    try {
      const url = new URL(`${this.relayUrl}/ws/${this.discoveryRoom}`);
      const protocol = url.protocol === "https:" ? "wss:" : "ws:";
      const wsUrl = url.origin + url.pathname + url.search;

      console.log(`[thunk-server] connecting to relay WebSocket: ${wsUrl}`);

      const WebSocket = (await import("ws")).default;
      this.ws = new WebSocket(wsUrl);
      // Keep the import path explicit so it resolves from the installed package

      this.ws.on("open", () => {
        console.log(`[thunk-server] WebSocket connected to relay`);
        this.pingInterval = setInterval(() => {
          if (this.ws?.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({ type: "ping", serverId: this.serverId }));
          }
        }, 30000);
      });

      this.ws.on("message", (data) => {
        this.handleRelayMessage(data.toString());
      });

      this.ws.on("close", () => {
        console.log(`[thunk-server] WebSocket disconnected`);
        if (this.pingInterval) clearInterval(this.pingInterval);
      });

      this.ws.on("error", (e) => {
        console.error(`[thunk-server] WebSocket error: ${e.message}`);
      });
    } catch (e) {
      console.error(`[thunk-server] failed to connect to relay: ${e.message}`);
    }
  }

  handleRelayMessage(msg) {
    try {
      const parsed = JSON.parse(msg);

      // Handle thunks-from-peers
      if (parsed.type === "thunk-request" && parsed.thunkId) {
        this.handleThunkRequest(parsed);
      }

      // Track other servers
      if (parsed.type === "thunk-server-ping") {
        this.peers.set(parsed.serverId, {
          endpoint: parsed.endpoint,
          timestamp: parsed.timestamp,
        });
      }
    } catch (e) {
      console.error(`[thunk-server] failed to parse relay message: ${e.message}`);
    }
  }

  async handleThunkRequest(req) {
    const { thunkId, action, input } = req;

    try {
      if (action === "run") {
        const result = await this.runThunk(thunkId, input);
        return result;
      } else if (action === "share") {
        const bundle = await this.shareThunk(thunkId);
        return bundle;
      }
    } catch (e) {
      console.error(`[thunk-server] thunk request failed: ${e.message}`);
    }
  }

  async handleRequest(req, res) {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const method = req.method;

    try {
      if (url.pathname === "/health") {
        this.sendJson(res, 200, {
          ok: true,
          name: "thunk-server",
          serverId: this.serverId,
          peers: this.peers.size,
          thunks: this.thunkStore.list().length,
          version: "0.0.1",
        });
        return;
      }

      if (url.pathname === "/thunk/store" && method === "POST") {
        const body = await this.readBody(req);
        const { source, name, version, schema, refs } = JSON.parse(body);
        const thunk = await Thunk.load(source, name, version, schema, refs);
        const id = this.thunkStore.store(thunk);
        this.sendJson(res, 200, { ok: true, id });
        return;
      }

      if (url.pathname === "/thunk/run" && method === "POST") {
        const body = await this.readBody(req);
        const { thunkId, input } = JSON.parse(body);
        const result = await this.runThunk(thunkId, input);
        this.sendJson(res, 200, result);
        return;
      }

      if (url.pathname === "/thunk/share" && method === "GET") {
        const thunkId = url.searchParams.get("id");
        const bundle = await this.shareThunk(thunkId);
        this.sendJson(res, 200, bundle);
        return;
      }

      if (url.pathname === "/thunk/list" && method === "GET") {
        const thunks = this.thunkStore.list();
        this.sendJson(res, 200, { ok: true, thunks });
        return;
      }

      if (url.pathname === "/thunk/demo" && method === "POST") {
        const { source } = await import("./example-compactor.mjs");
        const thunk = await Thunk.load(source, "room-compactor", "1.0.0");
        const id = this.thunkStore.store(thunk);
        const result = await this.runThunk(id, { type: "compact", room: "test-room", logLines: 42, logBase: 0, when: Date.now() });
        this.sendJson(res, 200, { ok: true, id, result });
        return;
      }

      if (url.pathname === "/thunk/publish" && method === "POST") {
        const body = await this.readBody(req);
        const { thunkId, id: thunkId2, targets } = JSON.parse(body);
        const tid = thunkId ?? thunkId2;
        const thunk = await this.thunkStore.get(tid);
        if (!thunk) {
          this.sendJson(res, 404, { ok: false, error: `thunk not found: ${tid}` });
          return;
        }
        const { publishBundle, publishToNix, publishToNora, publishToForge } = await import("./thunk-publish.mjs");
        const bundle = publishBundle(thunk);
        const results = [];
        if (!targets || targets.includes("nix")) results.push(await publishToNix(bundle));
        if (!targets || targets.includes("nora")) results.push(await publishToNora(bundle));
        if (!targets || targets.includes("forge")) results.push(await publishToForge(bundle));
        this.sendJson(res, 200, { ok: true, thunkId, results });
        return;
      }

      if (url.pathname === "/thunk/publish/demo" && method === "POST") {
        const { source } = await import("./example-compactor.mjs");
        const thunk = await Thunk.load(source, "room-compactor", "1.0.0");
        const id = this.thunkStore.store(thunk);
        const { publishBundle, publishToNix, publishToNora, publishToForge } = await import("./thunk-publish.mjs");
        const bundle = publishBundle(thunk);
        const results = [];
        results.push(await publishToNix(bundle));
        results.push(await publishToNora(bundle));
        results.push(await publishToForge(bundle));
        this.sendJson(res, 200, { ok: true, id, results });
        return;
      }

      if (url.pathname === "/peers" && method === "GET") {
        this.sendJson(res, 200, { ok: true, peers: [...this.peers.entries()] });
        return;
      }

      this.sendJson(res, 404, { ok: false, error: "not found" });
    } catch (e) {
      console.error(`[thunk-server] request error: ${e.message}`);
      this.sendJson(res, 500, { ok: false, error: e.message });
    }
  }

  async runThunk(id, input) {
    const result = await this.thunkStore.get(id);
    if (!result) throw new Error(`thunk not found: ${id}`);
    const out = result.apply(input);
    return { ok: true, id, state: out.state, effects: out.effects };
  }

  async shareThunk(id) {
    const thunk = await this.thunkStore.get(id);
    if (!thunk) throw new Error(`thunk not found: ${id}`);
    return thunk.share();
  }

  async readBody(req) {
    return new Promise((resolve, reject) => {
      const chunks = [];
      let size = 0;
      const limit = 1048576;
      req.on("data", (chunk) => {
        size += chunk.length;
        if (size > limit) {
          req.destroy();
          reject(new Error("body too large"));
          return;
        }
        chunks.push(chunk);
      });
      req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
      req.on("error", reject);
    });
  }

  sendJson(res, status, obj) {
    res.writeHead(status, {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET, POST, OPTIONS",
      "access-control-allow-headers": "content-type",
    });
    res.end(JSON.stringify(obj));
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const storeDir = args["--store"] ?? "/tmp/thunks";
  const port = Number(args["--port"] ?? DEFAULT_PORT);

  console.log(`[thunk-server] starting: store=${storeDir} port=${port}`);

  const thunkStore = new ThunkStore(storeDir);
  const schedule = new Schedule();
  const server = new ThunkServer({
    thunkStore,
    schedule,
    port,
    relayUrl: RELAY_URL,
    discoveryRoom: DISCOVERY_ROOM,
    serverId: SERVER_ID,
  });

  await server.start();

  process.on("SIGINT", async () => {
    console.log("[thunk-server] received SIGINT");
    await server.stop();
    process.exit(0);
  });

  process.on("SIGTERM", async () => {
    console.log("[thunk-server] received SIGTERM");
    await server.stop();
    process.exit(0);
  });

  console.log("[thunk-server] running");
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a;
      const val = argv[i + 1]?.startsWith("--") ? true : argv[++i];
      out[key] = val ?? true;
    }
  }
  return out;
}

main().catch((e) => {
  console.error("[thunk-server] fatal", e);
  process.exit(1);
});