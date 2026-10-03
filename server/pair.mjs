// pair.mjs — the archive pairer: the local archive server and its
// Cloudflare twin exchange pinned blocks until they agree.
//
// The twins are symmetric and content-addressed, so pairing is simple:
//   push — every block the local store has that the twin lacks gets POSTed
//   pull — every block the twin has that the local store lacks gets fetched
// A block is a block; the CID is verified on both ends, so a lying twin
// can only refuse service, never corrupt the store.
//
//   node server/pair.mjs --local http://127.0.0.1:8787 \
//       --twin https://kant-zk-relay.<account>.workers.dev \
//       --rooms <room> [--rooms <room>…]      # rooms to pair
//       [--interval 60] [--once]               # daemon or one cycle
//
// Room discovery: without --rooms the pairer reads the relay's ndjson
// archive (--archive-dir, the same one the relay writes) and pairs every
// room that ever pinned a block.  Room names are never read from disk —
// only their eight-character handles; the names come from --rooms or
// from a --rooms-file of `{"room": "…"}` entries (the archive.mjs
// rooms.d pattern).

import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join as pathJoin } from "node:path";

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
  console.log(`${new Date().toISOString()} ${level} pair ${msg}${extra ? " | " + extra : ""}`);
const info = (m, e) => log("info ", m, e);
const warn = (m, e) => log("warn ", m, e);
const error = (m, e) => console.error(`${new Date().toISOString()} error pair ${m}${e ? " | " + e : ""}`);

const argsAll = (name) => {
  const out = [];
  for (let i = 0; i < process.argv.length - 1; i++) {
    if (process.argv[i] === `--${name}` && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")) {
      out.push(process.argv[i + 1]);
    }
  }
  return out;
};

// ---------------------------------------------------------------- rooms

/** Rooms to pair, from --rooms, --rooms-file, or the relay's ndjson
 *  archive (every room that ever pinned a block). */
function discoverRooms(archiveDir) {
  const refs = new Set();
  if (existsSync(archiveDir)) {
    for (const f of readdirSync(archiveDir).filter((f) => f.endsWith(".ndjson"))) {
      try {
        for (const line of readFileSync(pathJoin(archiveDir, f), "utf8").split("\n")) {
          if (!line.trim()) continue;
          const j = JSON.parse(line);
          if (j.kind === "block") refs.add(f.replace(/\.ndjson$/, ""));
        }
      } catch { /* skip a torn line */ }
    }
  }
  return refs;
}

// --------------------------------------------------------------- fetch

async function listBlocks(base, room) {
  const res = await fetch(`${base}/room/${encodeURIComponent(room)}/blocks`);
  if (!res.ok) return null;
  const j = await res.json();
  return j.blocks ?? [];
}

async function getBlock(base, room, cid) {
  const res = await fetch(`${base}/room/${encodeURIComponent(room)}/block/${cid}`);
  if (!res.ok) return null;
  return new Uint8Array(await res.arrayBuffer());
}

async function putBlock(base, room, cid, bytes) {
  const res = await fetch(`${base}/room/${encodeURIComponent(room)}/block/${cid}`, {
    method: "POST", body: bytes,
  });
  return res.ok;
}

// ---------------------------------------------------------------- cycle

async function pairRoom({ local, twin, room }) {
  let pushed = 0, pulled = 0;
  const mine = (await listBlocks(local, room)) ?? [];
  const theirs = (await listBlocks(twin, room)) ?? [];
  const have = new Set(mine), want = new Set(theirs);

  // push: mine − theirs
  for (const cid of mine) {
    if (want.has(cid)) continue;
    const bytes = await getBlock(local, room, cid);
    if (!bytes) { warn("push: local lost a block mid-cycle", `${room.slice(0, 8)} ${cid.slice(0, 12)}`); continue; }
    if (await putBlock(twin, room, cid, bytes)) pushed++;
    else warn("push refused by twin", `${room.slice(0, 8)} ${cid.slice(0, 12)}`);
  }
  // pull: theirs − mine
  for (const cid of theirs) {
    if (have.has(cid)) continue;
    const bytes = await getBlock(twin, room, cid);
    if (!bytes) { warn("pull: twin lost a block mid-cycle", `${room.slice(0, 8)} ${cid.slice(0, 12)}`); continue; }
    if (await putBlock(local, room, cid, bytes)) pulled++;
    else warn("pull refused by local", `${room.slice(0, 8)} ${cid.slice(0, 12)}`);
  }
  return { pushed, pulled };
}

// ----------------------------------------------------------------- main

const local = arg("local", "http://127.0.0.1:8787");
const twin = arg("twin", null);
if (!twin) {
  console.error("usage: node server/pair.mjs --twin <url> [--local <url>] [--rooms r …] [--interval 60] [--once]");
  process.exit(2);
}
const interval = Math.max(5, Number(arg("interval", 60)) || 60);
const once = arg("once", false);
const archiveDir = arg("archive-dir", "");

const namedRooms = argsAll("rooms");
const roomsFile = arg("rooms-file", null);
if (roomsFile && existsSync(roomsFile)) {
  for (const f of readdirSync(roomsFile).filter((f) => f.endsWith(".json"))) {
    const j = JSON.parse(readFileSync(pathJoin(roomsFile, f), "utf8"));
    if (j.room) namedRooms.push(j.room);
  }
}

async function cycle() {
  // Rooms named explicitly pair by name; rooms discovered from the
  // archive only ever pair by their handle (the relay accepts the
  // handle as the room — it is the digest of the name, and blocks are
  // content-addressed, so the handle is as good as the name for
  // moving bytes).
  const rooms = [...new Set([...namedRooms, ...discoverRooms(archiveDir)])];
  let pushed = 0, pulled = 0;
  for (const room of rooms) {
    try {
      const r = await pairRoom({ local, twin, room });
      pushed += r.pushed; pulled += r.pulled;
    } catch (e) {
      error(`pairing ${room.slice(0, 8)} failed`, e.message ?? e);
    }
  }
  info(`cycle: ${rooms.length} room(s), pushed ${pushed}, pulled ${pulled}`);
}

await cycle();
if (once) process.exit(0);
info(`polling every ${interval}s`);
for (;;) { await new Promise((r) => setTimeout(r, interval * 1000)); await cycle(); }
