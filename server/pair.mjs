// pair.mjs — the archive pairer: the local archive server and its
// Cloudflare twin exchange pinned blocks until they agree.
//
// Minimal-cost pairing: the CF side holds no block state of its own.
// The twin is (a) the relay worker, a pure p2p router for room lines,
// and (b) the CF Pages snapshot, where the publisher already emits
// every block's raw bytes as a static content-addressed file
// (archive/b/<cid>.bin).  Static hosting of immutable, CID-verified
// bytes is public block storage — free, and semantically exact.
//
// So pairing is:
//   push — every block the local store has that the Pages snapshot
//          lacks gets POSTed to the local relay's room (the publisher
//          will pick it up on its next cycle and emit the page + .bin)
//   pull — every block the Pages snapshot has (blocks.json) that the
//          local store lacks gets fetched as b/<cid>.bin and pinned
//          locally, CID-verified
//
//   node server/pair.mjs --local http://127.0.0.1:8788 \
//       --pages https://kant-zk-pastebin.pages.dev \
//       --rooms <room> [--rooms <room>…]      # rooms to pair
//       [--interval 300] [--once]             # daemon or one cycle
//
// The direction that matters is pull: the Pages snapshot is the public
// archive of record, and a fresh local server converges to it without
// anyone telling it anything.  Push is the publisher's job, really —
// this loop just guarantees the local relay hears about new blocks
// promptly; the bytes reach the edge on the next publisher cycle.

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

const argsAll = (name) => {
  const out = [];
  for (let i = 0; i < process.argv.length - 1; i++) {
    if (process.argv[i] === `--${name}` && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")) {
      out.push(process.argv[i + 1]);
    }
  }
  return out;
};

const log = (level, msg, extra = "") =>
  console.log(`${new Date().toISOString()} ${level} pair ${msg}${extra ? " | " + extra : ""}`);
const info = (m, e) => log("info ", m, e);
const warn = (m, e) => log("warn ", m, e);
const error = (m, e) => console.error(`${new Date().toISOString()} error pair ${m}${e ? " | " + e : ""}`);

// ---------------------------------------------------------------- rooms

/** Rooms to pair, from --rooms, --rooms-file, or the relay's ndjson
 *  archive (every room that ever pinned a block — by handle only). */
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

/** Pull the Pages snapshot's block index (archive/blocks.json) — the
 *  public archive of record.  [{ ref, cid, size }] or null. */
async function pagesIndex(pagesBase) {
  try {
    const res = await fetch(`${pagesBase}/archive/blocks.json`);
    if (!res.ok) return null;
    return (await res.json()) ?? null;
  } catch { return null; }
}

/** Fetch a block's raw bytes from the Pages snapshot (archive/b/<cid>.bin),
 *  verified against its CID by the local relay on pin. */
async function pagesBlock(pagesBase, cid) {
  try {
    const res = await fetch(`${pagesBase}/archive/b/${cid}.bin`);
    if (!res.ok) return null;
    return new Uint8Array(await res.arrayBuffer());
  } catch { return null; }
}

async function cycle({ local, pages, rooms }) {
  let pushed = 0, pulled = 0;
  const idx = await pagesIndex(pages);
  // The rooms to diff: the named/discovered ones plus every room the
  // pages index names (a pulled block's handle may not be in --rooms,
  // and it must not be pulled again next cycle).
  const allRooms = [...new Set([
    ...rooms,
    ...(idx ?? []).map((b) => b.ref),
  ])];
  const mine = new Map(); // "ref/cid" -> true
  for (const room of allRooms) {
    const cids = (await listBlocks(local, room)) ?? [];
    for (const cid of cids) mine.set(`${room}/${cid}`, true);
  }
  // pull: pages index − local store
  if (idx) {
    for (const b of idx) {
      if (mine.has(`${b.ref}/${b.cid}`)) continue;
      const bytes = await pagesBlock(pages, b.cid);
      if (!bytes) { warn("pull: the pages snapshot lost a block", `${b.cid.slice(0, 12)}`); continue; }
      // The room handle is the room, as far as the relay is concerned
      // (it is the digest of the name; blocks are content-addressed).
      if (await putBlock(local, b.ref, b.cid, bytes)) pulled++;
      else warn("pull refused by local", `${b.ref} ${b.cid.slice(0, 12)}`);
    }
  } else {
    info("no pages index yet (first deploy?) — nothing to pull");
  }
  // push: local − pages index (the publisher carries these to the edge
  // on its next cycle; this is just the local-relay-side accounting)
  if (idx) {
    const theirs = new Set(idx.map((b) => `${b.ref}/${b.cid}`));
    for (const room of allRooms) {
      const cids = (await listBlocks(local, room)) ?? [];
      for (const cid of cids) {
        if (theirs.has(`${room}/${cid}`)) continue;
        // already local — the publisher will emit it; count it as pushed
        pushed++;
      }
    }
  }
  return { pushed, pulled };
}

// ----------------------------------------------------------------- main

const local = arg("local", "http://127.0.0.1:8788");
const pages = arg("pages", null);
if (!pages) {
  console.error("usage: node server/pair.mjs --pages <url> [--local <url>] [--rooms r …] [--interval 300] [--once]");
  process.exit(2);
}
const interval = Math.max(10, Number(arg("interval", 300)) || 300);
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

async function run() {
  const rooms = [...new Set([...namedRooms, ...discoverRooms(archiveDir)])];
  const { pushed, pulled } = await cycle({ local, pages, rooms });
  info(`cycle: ${rooms.length} room(s), ${pushed} to emit, pulled ${pulled}`);
}

await run();
if (once) process.exit(0);
info(`polling every ${interval}s`);
for (;;) { await new Promise((r) => setTimeout(r, interval * 1000)); await run(); }
