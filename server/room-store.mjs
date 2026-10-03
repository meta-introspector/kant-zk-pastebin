// room-store.mjs — the peer-side replica of a Kant room.
//
// The relay is a mailbox. It holds a room while the room is happening,
// forgets it on the TTL, and keeps no archive — `server/relay.mjs` is a
// `Map`, and the Cloudflare twin is a Durable Object with an in-memory
// RoomState and nothing written back. That is the contract, and this module
// is the other half of it: the copy that survives the room.
//
// This is the pattern `skills/kant-cli/SKILL.md` describes for fleet builds
// — "any sink can record builds into sqlite and mesh-sync them" — applied to
// the room log itself. A peer polls the relay for new lines, records them
// here, and hands this store to other peers so nobody depends on the relay
// still being up.
//
// In memory by default. A peer that wants its replica to outlive the process
// passes a file path to DatabaseSync, and the same code works; nothing here
// assumes which.
//
// Zero dependencies beyond `node:sqlite` and `node:crypto`, so a test can
// exercise it with a fake relay and two stores and no network.

import { DatabaseSync } from "node:sqlite";
import { createHash } from "node:crypto";

/** A room's cursor, its lines, and where each line was heard.
 *
 *  Dedup is on the printed line's digest, and that is sound rather than
 *  merely convenient: a Kant line is the encoding of its own witness, and
 *  the witness is computed over the message core, so one message has exactly
 *  one printed form. Two peers that both hold the same line agree on its
 *  digest, and a line that has been altered does not — it fails its witness
 *  at `accept` time upstream and is dropped long before it reaches here.
 *  Keying on the raw text is therefore identical to keying on identity,
 *  and it works uniformly across every tag (kzchat, kzat, kzpeer, kzfile,
 *  kzsig) without this file having to understand any of them.
 */
export class RoomStore {
  /** `file` is a path, or ":memory:" (the default). */
  constructor({ file = ":memory:" } = {}) {
    this.db = new DatabaseSync(file);
    this.file = file;
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS rooms (
        room      TEXT PRIMARY KEY,
        cursor    INTEGER NOT NULL DEFAULT 0,
        truncated INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS lines (
        room    TEXT NOT NULL,
        digest  TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        text    TEXT NOT NULL,
        seen_at INTEGER NOT NULL,
        PRIMARY KEY (room, digest)
      );

      CREATE INDEX IF NOT EXISTS lines_by_room ON lines (room, ordinal);

      -- Which relay a line was heard on, so two relays serving the same room
      -- are distinguishable and a mesh peer can tell where its data came from.
      CREATE TABLE IF NOT EXISTS sources (
        room   TEXT NOT NULL,
        digest TEXT NOT NULL,
        relay  TEXT NOT NULL,
        at     INTEGER NOT NULL,
        PRIMARY KEY (room, digest, relay)
      );

      CREATE TABLE IF NOT EXISTS meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    `);
    this.#insRoom = this.db.prepare(
      `INSERT INTO rooms (room, cursor, truncated, synced_at) VALUES (?, 0, 0, 0)
       ON CONFLICT(room) DO NOTHING`);
    this.#insLine = this.db.prepare(
      `INSERT INTO lines (room, digest, ordinal, text, seen_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(room, digest) DO NOTHING`);
    this.#insSource = this.db.prepare(
      `INSERT INTO sources (room, digest, relay, at) VALUES (?, ?, ?, ?)
       ON CONFLICT(room, digest, relay) DO NOTHING`);
    this.#setCursor = this.db.prepare(
      `UPDATE rooms SET cursor = MAX(cursor, ?), truncated = MAX(truncated, ?), synced_at = ?
       WHERE room = ?`);
    this.#getRoom = this.db.prepare(
      `SELECT room, cursor, truncated, synced_at FROM rooms WHERE room = ?`);
    this.#listRooms = this.db.prepare(
      `SELECT room, cursor, truncated, synced_at,
              (SELECT COUNT(*) FROM lines WHERE lines.room = rooms.room) AS count
         FROM rooms ORDER BY room`);
    this.#listLines = this.db.prepare(
      `SELECT room, digest, ordinal, text, seen_at FROM lines
        WHERE room = ? AND ordinal >= ? ORDER BY ordinal LIMIT ?`);
    this.#nextOrdinal = this.db.prepare(
      `SELECT COALESCE(MAX(ordinal), 0) AS n FROM lines WHERE room = ?`);
    this.#relaysFor = this.db.prepare(
      `SELECT DISTINCT relay FROM sources WHERE room = ? ORDER BY relay`);
    // `known` builds this per chunk size. A statement with a fixed number of
    // placeholders cannot be reused for a shorter argument list, and
    // node:sqlite refuses the mismatch — so the count is part of the cache key.
    this.#digestCache = new Map();
  }

  // node:sqlite has no prepared-statement cache, so hold the statements as
  // private fields rather than re-preparing on every insert.
  #insRoom; #insLine; #insSource; #setCursor; #getRoom; #listRooms; #listLines;
  #nextOrdinal; #relaysFor; #digestCache;

  #knownDigestStmt(n) {
    let stmt = this.#digestCache.get(n);
    if (!stmt) {
      stmt = this.db.prepare(
        `SELECT digest FROM lines WHERE room = ? AND digest IN (${new Array(n).fill("?").join(",")})`);
      this.#digestCache.set(n, stmt);
    }
    return stmt;
  }

  static digest(line) {
    return createHash("sha256").update(String(line), "utf8").digest("hex");
  }

  #touch(room) {
    this.#insRoom.run(room);
  }

  /** How far this replica has read a room, or 0 if it has never seen it. */
  cursor(room) {
    return Number(this.#getRoom.get(room)?.cursor ?? 0);
  }

  has(room) {
    return Boolean(this.#getRoom.get(room));
  }

  /** Take one poll's worth of lines from a relay.
   *
   *  `out` is what a relay returns: `{lines, cursor, truncated}`. Lines that
   *  are already held are counted, not re-inserted, so a peer that polls the
   *  same room from two relays — or re-polls after a rewind — converges
   *  instead of growing.
   *
   *  The cursor only ever moves forward (MAX in the SQL). A relay that
   *  reports a *lower* cursor than we hold has been trimmed or restarted,
   *  which is not a reason to rewind a replica that already has those lines.
   *  `truncated` is latched for the same reason: once a relay has told us it
   *  dropped history from under us, that fact does not un-happen.
   */
  record(room, out, { relay = "", at = Date.now(), adoptCursor = true } = {}) {
    const lines = Array.isArray(out?.lines) ? out.lines : [];
    const truncated = out?.truncated ? 1 : 0;
    this.#touch(room);

    let inserted = 0, duplicate = 0;
    let ordinal = Number(this.#nextOrdinal.get(room).n);

    this.db.exec("BEGIN");
    try {
      for (const text of lines) {
        const digest = RoomStore.digest(text);
        // The ordinal is only consumed when the row is actually new. Bumping
        // it first and then discovering a conflict left gaps in the sequence,
        // which quietly breaks `lines({from})` pagination: a reader that
        // resumes at the last ordinal it saw would skip the lines in between.
        const candidate = ordinal + 1;
        const res = this.#insLine.run(room, digest, candidate, String(text), at);
        if (res.changes === 0) { duplicate += 1; }
        else { inserted += 1; ordinal = candidate; }
        // The source is recorded whether or not the line was new. A line two
        // relays both carry is one line held twice; skipping the attribution
        // on the second relay loses exactly the provenance that makes it worth
        // holding the line once.
        if (relay) this.#insSource.run(room, digest, relay, at);
      }
      if (adoptCursor) this.#setCursor.run(Number(out?.cursor ?? 0) || 0, truncated, at, room);
      this.db.exec("COMMIT");
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
    return { inserted, duplicate, cursor: this.cursor(room) };
  }

  /** The lines held for a room, in arrival order. */
  lines(room, { from = 0, limit = -1 } = {}) {
    if (!this.has(room)) return [];
    const rows = this.#listLines.all(room, from, limit < 0 ? -1 : limit);
    return rows.map((r) => ({ ordinal: Number(r.ordinal), digest: r.digest, text: r.text, seenAt: Number(r.seen_at) }));
  }

  /** Every relay this replica has heard a line for that room on. */
  relays(room) {
    return this.#relaysFor.all(room).map((r) => r.relay);
  }

  /** How many of `texts` this replica already holds. */
  known(room, texts) {
    if (!texts.length || !this.has(room)) return 0;
    const digests = texts.map((t) => RoomStore.digest(t));
    // Chunked because node:sqlite caps bound parameters (SQLITE_MAX_VARIABLE_
    // NUMBER); 256 is a conservative floor for older SQLite builds.
    let n = 0;
    for (let i = 0; i < digests.length; i += 256) {
      const chunk = digests.slice(i, i + 256);
      n += this.#knownDigestStmt(chunk.length).all(room, ...chunk).length;
    }
    return n;
  }

  /** Take the lines from another peer's replica of the same room.
   *
   *  This is the peer-to-peer half. `other` is any RoomStore; it is read, not
   *  locked, and nothing about `other` is modified. Ordinals are rebased onto
   *  our own sequence rather than copied, so merging a peer that joined late
   *  does not renumber our history, and dedup means a line both of us hold is
   *  kept once.
   *
   *  The lines arrive with their own relay recorded, so provenance survives
   *  the hop — a reader can still tell that peer A heard it on relay X.
   */
  merge(room, other, { relay = "" } = {}) {
    if (!other?.has?.(room)) return { inserted: 0, duplicate: 0, cursor: 0 };
    const theirs = other.lines(room);
    // Their cursor is deliberately NOT adopted — `adoptCursor: false`. Cursors
    // are per-relay positions into per-relay logs; peer B's cursor 40 says
    // nothing about what peer A has read from relay X, and adopting it would
    // silently mark lines as read that this replica has never seen. For the
    // same reason a merge must not stamp `synced_at`: nothing was synced.
    const res = this.record(
      room,
      { lines: theirs.map((l) => l.text), cursor: 0, truncated: 0 },
      { relay: relay || `peer:${theirRelayHint(other, room)}`, adoptCursor: false },
    );
    return { inserted: res.inserted, duplicate: res.duplicate, cursor: this.cursor(room) };
  }

  /** What this store holds, for a health line or a test. */
  stats() {
    const rooms = this.#listRooms.all();
    return {
      rooms: rooms.length,
      lines: rooms.reduce((n, r) => n + Number(r.count), 0),
      detail: rooms.map((r) => ({
        room: r.room,
        cursor: Number(r.cursor),
        truncated: Boolean(r.truncated),
        lines: Number(r.count),
        syncedAt: Number(r.synced_at),
      })),
    };
  }

  /** Poll a relay for one room and record what comes back.
   *
   *  `poll` is injected rather than imported so this module stays free of
   *  `web/kant-net.mjs` (which drags the whole diagnostics stack in) and so a
   *  test can drive it with no network at all. Callers pass
   *  `new RelayClient(base).poll.bind(client)`.
   */
  async sync(room, poll, { relay = "", wait = 0, at = Date.now() } = {}) {
    if (typeof poll !== "function") {
      throw new TypeError("RoomStore.sync needs a poll(room, {from}) function");
    }
    const out = await poll(room, { from: this.cursor(room), wait });
    return { ...this.record(room, out, { relay, at }), truncated: Boolean(out?.truncated) };
  }

  close() { this.db.close(); }
}

const theirRelayHint = (store, room) => {
  const r = store.relays?.(room) ?? [];
  return r.length ? r.join(",") : "unknown";
};

/** Poll a relay with a RelayClient and record it. One call, for scripts.
 *
 *  `base` is a relay root, e.g. https://kant-zk-relay.workers.dev. */
export async function syncRoom(room, base, { store = new RoomStore(), wait = 0 } = {}) {
  const { RelayClient } = await import("../web/kant-net.mjs");
  const client = new RelayClient(base);
  // RelayClient keeps its own cursor per room; set it to ours so the two do
  // not disagree about where "new" starts.
  if (store.has(room)) client.cursors.set(room, store.cursor(room));
  return store.sync(
    room,
    async (r, { from, wait: w }) => {
      client.cursors.set(r, from);
      return client.poll(r, { wait: w });
    },
    { relay: base, wait },
  );
}