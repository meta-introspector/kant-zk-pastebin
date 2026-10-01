// Relay-side kzpass ledger.
//
// Two backends, one interface:
//   * NodeRelay:  node:sqlite (Node 24 native, zero-dependency — the
//     twitterstorm/tracker pattern), file-backed, survives restarts.
//   * The CF worker keeps its own tiny copy in Durable Object storage
//     (worker.js) — the store here is the node twin's.
//
// The ledger counts POSTs per pass id and enforces the pass's limit.
// It also rate-limits passless posts per sender (the kzchat sender id
// is inside the line, and every client re-verifies witnesses, so a
// spoofed sender only burns someone else's quota — it cannot forge
// lines).

import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";

/** Default passless rate limit: N posts per sender per window. */
export const DEFAULT_PEER_LIMIT = 10;
export const DEFAULT_PEER_WINDOW_MS = 10 * 60 * 1000;

export class PassStore {
  constructor(file, {
    peerLimit = DEFAULT_PEER_LIMIT,
    peerWindowMs = DEFAULT_PEER_WINDOW_MS,
  } = {}) {
    this.peerLimit = peerLimit;
    this.peerWindowMs = peerWindowMs;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    this.db = new DatabaseSync(file);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS pass_spends (
        id TEXT PRIMARY KEY,
        room TEXT NOT NULL,
        limit_max INTEGER NOT NULL,
        spent INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS peer_posts (
        room TEXT NOT NULL,
        sender TEXT NOT NULL,
        at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS peer_posts_idx ON peer_posts (room, sender, at);
    `);
    this.pruneStmt = this.db.prepare(
      "DELETE FROM peer_posts WHERE at < ?");
    this.spendGet = this.db.prepare(
      "SELECT spent, limit_max FROM pass_spends WHERE id = ? AND room = ?");
    this.spendIns = this.db.prepare(
      `INSERT OR IGNORE INTO pass_spends (id, room, limit_max, spent, created_at, updated_at)
       VALUES (?, ?, ?, 0, ?, ?)`);
    this.spendInc = this.db.prepare(
      `UPDATE pass_spends SET spent = spent + 1, updated_at = ?
       WHERE id = ? RETURNING spent, limit_max`);
    this.peerCount = this.db.prepare(
      "SELECT COUNT(*) AS n FROM peer_posts WHERE room = ? AND sender = ? AND at >= ?");
    this.peerIns = this.db.prepare(
      "INSERT INTO peer_posts (room, sender, at) VALUES (?, ?, ?)");
  }

  /** Prune rate-limit rows older than the window. */
  prune(now = Date.now()) {
    this.pruneStmt.run(now - this.peerWindowMs);
  }

  /**
   * Admit one POST.  `pass` is the parsed kzpass (or null), `sender`
   * the kzchat sender id (or a fallback string), `lines` the number of
   * lines the POST carries.
   * Returns { ok: true } or { ok: false, status, error }.
   */
  admit({ pass = null, sender, room, lines = 1, now = Date.now() }) {
    this.prune(now);
    if (pass && pass.limit > 0) {
      const idHex = Buffer.from(pass.id).toString("hex");
      this.spendIns.run(idHex, room, pass.limit, now, now);
      const cur = this.spendGet.get(idHex, room);
      if (!cur || cur.spent >= cur.limit_max) {
        return { ok: false, status: 429,
          error: `pass spent (${cur ? cur.limit_max : "?"} post(s) allowed)` };
      }
      const row = this.spendInc.get(now, idHex);
      if (!row || row.spent > row.limit_max) {
        return { ok: false, status: 429,
          error: `pass spent (${row ? row.limit_max : "?"} post(s) allowed)` };
      }
      return { ok: true, remaining: row.limit_max - row.spent };
    }
    // No pass (or an unlimited owner invite): per-sender rate limit.
    const { n } = this.peerCount.get(room, sender, now - this.peerWindowMs);
    if (n + lines > this.peerLimit) {
      return { ok: false, status: 429,
        error: `rate limit: ${this.peerLimit} posts per ${Math.round(this.peerWindowMs / 60000)} min` };
    }
    for (let i = 0; i < lines; i++) this.peerIns.run(room, sender, now);
    return { ok: true, remaining: this.peerLimit - n - lines };
  }
}
