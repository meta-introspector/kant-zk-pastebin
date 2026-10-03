// disk-blocks.mjs — the durable twin of the relay's in-memory `Blocks`
// store (relay.mjs).  Same API, same gas rules, but the bytes survive a
// restart: every block is a file, every room a directory, and the store
// replays itself on boot.
//
//   <archive-dir>/blocks/<roomRef>/<cid>.bin   — the pinned bytes
//   <archive-dir>/blocks/<roomRef>/index.json  — pins + gas ledger
//
// The room name never touches the disk — only its eight-character one-way
// handle (`roomRef`), exactly like the ndjson archive.  A CID is the
// witness digest of its bytes, re-verified on every read, so a corrupted
// or tampered file is refused, never served.
//
// Gas is the same honesty ledger as the in-memory store: bytes written
// and bytes served are charged per room per window, and the ledger
// persists with the index so a restart does not reset a room's budget.

import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync } from "node:fs";
import { join as pathJoin } from "node:path";
import { witness } from "../web/kantzk.mjs";
import { roomRef } from "./relay.mjs";

/** The disk-backed block store.  `cfg` is the relay CONFIG (the same
 *  maxBlock / gas budgets); `root` is the archive directory. */
export class DiskBlocks {
  constructor(cfg, root) {
    this.cfg = cfg;
    this.root = root;
    this.map = new Map(); // roomRef -> { room, blocks: Map(cid -> bytes), gas, dirty }
    this.replay();
  }

  /** Load every room directory back into memory.  Bytes are read
 *  lazily from disk on `get` (and re-verified); the index restores the
 *  gas ledger and the room name. */
  replay() {
    if (!existsSync(this.root)) return;
    for (const ref of readdirSync(this.root)) {
      const dir = pathJoin(this.root, ref);
      const idxPath = pathJoin(dir, "index.json");
      if (!existsSync(idxPath)) continue;
      try {
        const idx = JSON.parse(readFileSync(idxPath, "utf8"));
        const r = {
          room: idx.room ?? null,
          blocks: new Map(), // cid -> null (on disk, read on demand)
          gas: idx.gas ?? { stored: 0, served: 0, window: Date.now() },
          dirty: false,
        };
        for (const cid of idx.blocks ?? []) r.blocks.set(cid, null);
        this.map.set(ref, r);
      } catch { /* a broken index is a broken room: skip it */ }
    }
  }

  roomDir(name) {
    const ref = roomRef(name);
    return { ref, dir: pathJoin(this.root, ref) };
  }

  room(name) {
    const { ref, dir } = this.roomDir(name);
    let r = this.map.get(ref);
    if (!r) {
      r = { room: name, blocks: new Map(), gas: { stored: 0, served: 0, window: Date.now() }, dirty: false };
      this.map.set(ref, r);
    } else if (r.room == null) {
      r.room = name; // replay only knew the handle; first use restores the name
    }
    mkdirSync(dir, { recursive: true });
    return r;
  }

  /** The ledger, rolled over if the window has passed. */
  gas(name) {
    const r = this.room(name);
    if (Date.now() - r.gas.window > this.cfg.gasWindowMs) {
      r.gas.stored = 0; r.gas.served = 0; r.gas.window = Date.now();
      r.dirty = true;
    }
    return r.gas;
  }

  /** Pin bytes under their name.  Returns null on success, or
 *  { status, error } describing the refusal.  Same rules as the
 *  in-memory store; on success the bytes are fsynced to disk. */
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
    const buf = Buffer.from(bytes);
    const { ref, dir } = this.roomDir(name);
    mkdirSync(dir, { recursive: true });
    writeFileSync(pathJoin(dir, `${cid}.bin`), buf);
    r.blocks.set(cid, buf);
    r.dirty = true;
    this.save(r);
    return null;
  }

  /** Serve a block, charging the room for the bytes.  The bytes are
 *  read from disk if the room has not touched them this boot, and
 *  re-verified against their CID — a corrupted file is a 404, never
 *  garbage. */
  get(name, cid) {
    const { ref, dir } = this.roomDir(name);
    const r = this.map.get(ref);
    if (!r || !r.blocks.has(cid)) return { status: 404, error: "no such block" };
    const g = this.gas(name);
    if (g.served + 0 > this.cfg.gasServeBudget) {
      return { status: 429, error: "the room is out of serving gas until the window turns" };
    }
    let bytes = r.blocks.get(cid);
    if (bytes === null) {
      try {
        bytes = readFileSync(pathJoin(dir, `${cid}.bin`));
      } catch {
        return { status: 404, error: "no such block" };
      }
      if (witness(Array.from(bytes)) !== cid) {
        return { status: 404, error: "no such block" }; // corrupted on disk
      }
      r.blocks.set(cid, bytes); // hot for the rest of this boot
    }
    if (g.served + bytes.length > this.cfg.gasServeBudget) {
      return { status: 429, error: "the room is out of serving gas until the window turns" };
    }
    g.served += bytes.length;
    r.dirty = true;
    this.save(r);
    return bytes;
  }

  /** Persist a room's index (pins + gas).  Best-effort, like the ndjson
 *  archive: a failed save is logged by the caller, never fatal. */
  save(r) {
    if (!r.dirty || !r.room) return;
    const { ref, dir } = this.roomDir(r.room);
    try {
      mkdirSync(dir, { recursive: true });
      writeFileSync(pathJoin(dir, "index.json"),
        JSON.stringify({ room: r.room, blocks: [...r.blocks.keys()], gas: r.gas }, null, 2) + "\n");
      r.dirty = false;
    } catch { /* best-effort: the next put/get retries */ }
  }

  /** Every pinned CID across every room, for the pairer and the page
  *  emitter.  With a room name: that room's CIDs.  Without: every
  *  room's, as [{ ref, cid }] — the handle only, never a name. */
  list(name) {
    if (name != null) {
      const { ref } = this.roomDir(name);
      const r = this.map.get(ref);
      return r ? [...r.blocks.keys()] : [];
    }
    const out = [];
    for (const [ref, r] of this.map) {
      for (const cid of r.blocks.keys()) out.push({ ref, cid });
    }
    return out;
  }

  /** Forget a room (tests). */
  wipe(name) {
    const { ref, dir } = this.roomDir(name);
    this.map.delete(ref);
    rmSync(dir, { recursive: true, force: true });
  }
}
