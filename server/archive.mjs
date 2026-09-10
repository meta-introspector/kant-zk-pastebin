// archive.mjs — the kant-zk archiver: a client that joins a room and
// archives the discussion as a thread in the old Kant pastebin.
//
// The archiver is just another peer.  It joins with the same invite any
// agent uses (the room secret is in the link, the relay never learns
// it), listens on the room (long poll or WebSocket), and every time the
// transcript grows it posts the whole thread to the pastebin as a paste
// with reply_to chaining, so the discussion appears as a thread:
//
//   room 6152b57d… -> paste "kant room 6152b57d… — transcript" (root)
//                   -> paste "kant room 6152b57d… — +N lines"   (reply)
//
// The pastebin content-dedupes, so re-posting an unchanged transcript
// returns the same paste.  The archiver keeps the root paste id in its
// state file and replies to it, so /threads shows one thread per room.
//
// Usage (a daemon; every option is also an env var, dashes/underscores
// interchangeable):
//
//   node server/archive.mjs --invite '<link>' \
//       --relay https://solana.solfunmeme.com/relay \
//       --backend https://solana.solfunmeme.com/pastebin \
//       --state /var/lib/kant-archive/<room>.json \
//       [--ws] [--interval 15] [--name kant-archive]
//
//   node server/archive.mjs --rooms /var/lib/kant-archive/rooms.d \
//       …  # every *.json in the dir that has an invite: archive them all
//
// Protocol notes: the archiver never posts the invite or any secret;
// the transcript it posts is the same text every peer displays
// (`transcript()`), and the room name in the paste title is the public
// digest, which the relay and every peer already know.

import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { join as pathJoin } from "node:path";
import * as Net from "../web/kant-net.mjs";
import { pasteApi } from "../web/kant-pastebin.mjs";

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
  console.log(`${new Date().toISOString()} ${level} archive ${msg}${extra ? " | " + extra : ""}`);
const info = (m, e) => log("info ", m, e);
const warn = (m, e) => log("warn ", m, e);
const error = (m, e) => console.error(`${new Date().toISOString()} error archive ${m}${e ? " | " + e : ""}`);

// -------------------------------------------------------------- the room

/** One archived room: a KantNode joined on the invite, a poller, and the
 *  pastebin thread it maintains.  */
class ArchivedRoom {
  constructor({ invite, relay, backend, statePath, name = "kant-archive",
                interval = 15, ws = false }) {
    this.statePath = statePath;
    this.backend = backend;
    this.interval = Math.max(1, Number(interval) || 15);
    this.ws = ws;
    this.paste = pasteApi(backend);
    this.state = existsSync(statePath)
      ? JSON.parse(readFileSync(statePath, "utf8"))
      : { root: null, lastCursor: 0, archivedLines: 0 };

    // A client with no browser around it: fetch for the relay, no bus,
    // no mesh — the archiver only listens, it never speaks first.
    this.node = new Net.KantNode({ peer: name, relay: relay || null, log: null });
    const joined = this.node.joinInvite(invite);
    if (!joined) throw new Error(`the invite did not parse: ${String(invite).slice(0, 60)}…`);
    this.room = this.node.room;
    this.client = this.node.client;
    if (!this.client) throw new Error("the invite names no relay and none was given");
    info(`joined room ${this.room.slice(0, 8)}…`, `relay=${this.node.relayBase}`);
  }

  /** The transcript as displayed: "sender: text", one line per message. */
  display() {
    return this.node.view().map((m) => `${m.sender}: ${Net.msgText(m)}`);
  }

  /** Poll once (or read the socket) and archive if the transcript grew. */
  async tick() {
    const out = await this.client.poll(this.room, { wait: 0 });
    for (const line of out.lines ?? []) this.node.ingest(line);
    const view = this.display();
    const n = view.length;
    if (n === this.state.archivedLines) return false;
    const grew = n - this.state.archivedLines;
    await this.archive(view, grew);
    this.state.archivedLines = n;
    this.state.lastCursor = out.cursor ?? this.state.lastCursor;
    this.save();
    return true;
  }

  /** Post the transcript to the pastebin, chaining replies to the root. */
  async archive(view, grew) {
    const room8 = this.room.slice(0, 8);
    const title = `kant room ${room8}… — ${view.length} lines`;
    const body = [
      `# kant-zk room ${this.room}`,
      ``,
      `Archived discussion from the kant-zk relay ${this.node.relayBase}`,
      `(${view.length} lines, ${new Date().toISOString()}).`,
      ``,
      ...view,
      ``,
    ].join("\n");
    const res = await this.paste.put(body, {
      title,
      description: `transcript of kant-zk room ${room8}`,
      keywords: ["kant-zk", "archive", "transcript", room8],
      replyTo: this.state.root ?? undefined,
    });
    if (!this.state.root) {
      this.state.root = res.id;
      info(`archived ${view.length} lines as thread root`, `${res.url}`);
    } else {
      info(`archived +${grew} lines as a reply`, `${res.url}`);
    }
    this.state.lastUrl = res.url;
    this.state.lastAt = new Date().toISOString();
  }

  save() {
    mkdirSync(pathJoin(this.statePath, ".."), { recursive: true });
    writeFileSync(this.statePath, JSON.stringify(this.state, null, 2) + "\n");
  }

  /** The loop: long-poll or WebSocket, forever. */
  async run() {
    if (this.ws) {
      // WebSocket mode: the relay pushes; each push re-archives.
      await new Promise(() => {
        const sock = new Net.RelaySocket(this.node.relayBase, this.room, {
          cursor: this.state.lastCursor,
          onLines: async (out) => {
            for (const l of out.lines ?? []) this.node.ingest(l);
            const view = this.display();
            if (view.length !== this.state.archivedLines) {
              const grew = view.length - this.state.archivedLines;
              try {
                await this.archive(view, grew);
                this.state.archivedLines = view.length;
                this.state.lastCursor = out.cursor ?? this.state.lastCursor;
                this.save();
              } catch (e) { error("archive failed", e.message ?? e); }
            }
          },
          onOpen: () => info(`websocket open`, this.room.slice(0, 8)),
          onClose: () => warn(`websocket closed; falling back to polling`),
        });
        sock.open();
        // If the socket closes (proxy timeout), poll as a fallback.
        const fallback = setInterval(() => this.tick().catch((e) =>
          error("poll failed", e.message ?? e)), this.interval * 1000);
        if (fallback.unref) fallback.unref();
      });
      return;
    }
    // Long-poll mode: hold the request open for `wait` seconds, then
    // archive whatever arrived and ask again.
    info(`polling every ${this.interval}s (wait=10 long poll)`);
    for (;;) {
      try {
        const out = await this.client.poll(this.room, { wait: 10 });
        for (const line of out.lines ?? []) this.node.ingest(line);
        const view = this.display();
        if (view.length !== this.state.archivedLines) {
          const grew = view.length - this.state.archivedLines;
          await this.archive(view, grew);
          this.state.archivedLines = view.length;
          this.state.lastCursor = out.cursor ?? this.state.lastCursor;
          this.save();
          info(`archived +${grew} line(s)`, `total ${view.length}`);
        }
      } catch (e) {
        error("poll cycle failed", e.message ?? e);
        await new Promise((r) => setTimeout(r, this.interval * 1000));
      }
    }
  }
}

// ---------------------------------------------------------------- main

const invite = arg("invite", null);
const roomsDir = arg("rooms", null);

const configs = [];
if (roomsDir && existsSync(roomsDir)) {
  for (const f of readdirSync(roomsDir).filter((f) => f.endsWith(".json")).sort()) {
    const p = pathJoin(roomsDir, f);
    const j = JSON.parse(readFileSync(p, "utf8"));
    if (j.invite) configs.push({ ...j, statePath: p });
  }
  info(`loaded ${configs.length} room(s) from ${roomsDir}`);
} else if (invite) {
  const statePath = arg("state", `kant-archive-${Date.now()}.json`);
  configs.push({ invite, statePath });
} else {
  console.error(`usage: node server/archive.mjs --invite '<link>' [--state f.json]
       node server/archive.mjs --rooms <dir>   # every *.json with an invite`);
  process.exit(2);
}

const rooms = [];
for (const c of configs) {
  try {
    rooms.push(new ArchivedRoom({
      invite: c.invite,
      relay: c.relay ?? arg("relay", null),
      backend: c.backend ?? arg("backend", "https://solana.solfunmeme.com/pastebin"),
      statePath: c.statePath,
      name: c.name ?? arg("name", "kant-archive"),
      interval: c.interval ?? arg("interval", 15),
      ws: c.ws ?? arg("ws", false),
    }));
  } catch (e) {
    error(`room skipped: ${e.message}`);
  }
}
if (!rooms.length) { error("no rooms to archive"); process.exit(1); }

// Every room runs its own loop; the process stays up as long as any does.
for (const r of rooms) r.run().catch((e) => { error("room loop died", e.message ?? e); process.exit(1); });
setInterval(() => {}, 1 << 30); // keep the event loop alive
