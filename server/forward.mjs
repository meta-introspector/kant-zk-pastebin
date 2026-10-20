// forward.mjs — the kant-zk bridge: forwards a room's lines from one
// relay to another, so a discussion on the local relay is mirrored on
// the remote relay (the Cloudflare worker, or any other deployment of
// the same protocol).
//
// The bridge is just another client.  It joins the room with the same
// invite any agent uses, reads every line off the source relay, and
// re-posts the raw lines to the same room name on the destination
// relay.  Lines carry their own witness, so the destination's clients
// accept them without ever seeing the bridge: it is a mailbox that
// happens to have two keys.
//
//   local relay  ──poll──▶  forward.mjs  ──post──▶  cloudflare relay
//   (solana.solfunmeme.com/relay)              (kant-zk-relay.…workers.dev)
//
// One direction only.  Bidirectional bridging needs line-level dedup
// (each bridge would see the other's carried lines as new and bounce
// them back forever); the relay log would grow without bound.  Run two
// bridges with disjoint sender sets, or dedup by (sender, seq) first.
//
// Usage:
//
//   node server/forward.mjs --invite '<link>' \
//       --from https://solana.solfunmeme.com/relay \
//       --to   https://kant-zk-relay.jmikedupont2.workers.dev \
//       [--interval 10] [--state <dir>] [--once]
//
// --state names the directory holding this room's carry ledger and cursor
// state: one `<room>-<dir>.json` plus one `<room>-<dir>.sent.sqlite` per
// bridge. It defaults to /tmp, which is fine for a one-off carry and wrong
// for anything long-lived.
//
// The invite's room (a digest of the secret, which neither relay ever
// learns) names the same room on both relays: that is the interlink.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { RelayClient } from "../web/kant-net.mjs";
import { RoomStore } from "./room-store.mjs";

// ------------------------------------------------------------- arguments

const arg = (name, dflt) => {
  const k = name.replace(/-/g, "_").toUpperCase();
  if (process.env[k] != null && process.env[k] !== "") return process.env[k];
  const i = process.argv.indexOf(`--${name}`);
  if (i !== -1 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")) {
    return process.argv[i + 1];
  }
  if (process.argv.includes(`--${name}`)) return true;
  return dflt;
};

const log = (level, msg, extra = "") =>
  console.log(`${new Date().toISOString()} ${level} forward ${msg}${extra ? " | " + extra : ""}`);
const info = (m, e) => log("info ", m, e);
const error = (m, e) => console.error(`${new Date().toISOString()} error forward ${m}${e ? " | " + e : ""}`);

// --------------------------------------------------------------- the room

// The room name comes from the invite's #fragment: the invite is
// `origin#kzinvite:<relay-hex>:<secret-hex>:<peer>`, and the room is
// the witness of the secret.  The bridge only needs the public room
// name to ROUTE — it never needs the secret, because it re-posts raw
// lines that already carry their own witness.
//
// It does still need to PRESENT the invite when it writes.  A POST with
// no `x-kant-invite` is charged to an anonymous sender and held to the
// per-sender rate limit (10 posts / 10 min on the default relay), which
// a first carry of a real backlog trips at once — a 143-line room came
// back 429 on the first attempt.  Presenting it makes the relay admit
// the bridge as the room's owner instead.  (Resolved in main, after the
// dynamic import of kantzk.mjs below.)

// --------------------------------------------------------------- bridge

export class Bridge {
  constructor({ from, to, room, statePath, interval = 10, invite = null }) {
    this.src = new RelayClient(from);
    this.dst = new RelayClient(to);
    this.from = from;
    this.to = to;
    this.room = room;
    this.interval = Math.max(1, Number(interval) || 10);
    this.statePath = statePath;
    // Written on every post so the destination relay admits this bridge as
    // the room's owner rather than as an anonymous peer under the
    // per-sender rate limit. The fragment, not the whole link — see
    // fragOfInvite above.
    const frag = invite ? fragOfInvite(invite) : null;
    this.writeHeaders = frag ? { "x-kant-invite": frag } : null;
    this.state = existsSync(statePath)
      ? JSON.parse(readFileSync(statePath, "utf8"))
      : { carried: 0 };
    // What the bridge has already pushed to the destination.
    //
    // This used to be a bare Set of line strings in memory, which vanished
    // with the process: a restarted bridge re-sent everything it had carried.
    // It is now a sqlite replica — but a *file-backed* one, deliberately. An
    // in-memory RoomStore would have kept the code shape and lost the
    // property the change was for, because every carry in `pump`/`carry` is
    // its own process invocation. `scripts/forward-test.mjs` runs the bridge
    // in separate processes on purpose for exactly this reason.
    this.sent = new RoomStore({ file: statePath.replace(/\.json$/, ".sent.sqlite") });
  }

  save() { writeFileSync(this.statePath, JSON.stringify(this.state, null, 2) + "\n"); }

  /** Lines read off the source that this bridge has not already carried.
   *
   *  Dedup is on the printed line's digest, keyed per room, and it survives a
   *  restart because it lives in `sent` rather than in this process. */
  uncarried(lines) {
    if (!lines.length) return [];
    const digests = lines.map((l) => RoomStore.digest(l));
    const have = new Set();
    for (const row of this.sent.lines(this.room)) have.add(row.digest);
    return lines.filter((_, i) => !have.has(digests[i]));
  }

  /** Record lines as carried, so they are never sent twice. */
  markCarried(lines, { at = Date.now() } = {}) {
    if (lines.length) {
      this.sent.record(this.room, { lines, cursor: 0 }, { relay: this.to, at, adoptCursor: false });
    }
  }

  /** Carry every line the source has past our cursor to the destination.
   *  On the first carry (backlog) the destination is read first and any
   *  line it already has is skipped, so restarting the bridge is
   *  idempotent — the destination never grows duplicate history. */
  async carry() {
    const out = await this.src.poll(this.room, { wait: 0 });
    let lines = this.uncarried(out.lines ?? []);
    if (!lines.length) {
      if (out.lines?.length) {
        info(`backlog: everything the source has was already carried`,
          `${out.lines.length} line(s) held in ${this.sent.file}`);
      }
      return 0;
    }
    if (!this.state.synced) {
      const have = (await this.dst.poll(this.room, { wait: 0 })).lines ?? [];
      const fresh = lines.filter((l) => !have.includes(l));
      const skipped = lines.length - fresh.length;
      if (skipped) info(`backlog: skipped ${skipped} line(s) already on the destination`);
      lines = fresh;
      this.state.synced = true;
      if (!lines.length) { this.save(); return 0; }
    }
    await this.dst.post(this.room, lines, this.writeHeaders);
    // Only now is a line known to be on the destination: a post that throws
    // has carried nothing, so nothing is marked and the next attempt retries.
    this.markCarried(lines);
    this.state.carried += lines.length;
    this.save();
    return lines.length;
  }
}

// ----------------------------------------------------------------- invites
//
// Above the main guard on purpose: the Bridge constructor reads
// `fragOfInvite`, so these cannot live inside a block the module only
// enters when it is the process entry point.
const { witness, hexDecode } = await import("../web/kantzk.mjs");

// The invite fragment, from either shape an invite arrives in:
//
//   https://relay.example/#kzinvite:<relay-hex>:<secret-hex>:<peer>
//   kzinvite:<relay-hex>:<secret-hex>:<peer>
//
// The relay's `x-kant-invite` header wants that fragment verbatim —
// `envelopeDecode` reads colon-separated hex fields and nothing else, so
// passing the whole link (origin included) parses as garbage and the relay
// answers 401 rather than the 429 an anonymous post would get.
//
// An invite is not always a URL: `kant-cli join` takes a bare envelope out of
// a UUCP spool file, and the rooms directory in `--rooms` mode is full of
// them. Requiring a `#` meant such an invite produced a null fragment and the
// bridge died on it rather than carrying anything.
const fragOfInvite = (link) => {
  const s = String(link ?? "").trim();
  const m = s.match(/#(.+)$/);
  if (m) return m[1];
  return s.includes("#") ? null : s || null;
};

const roomOfInvite = (link) => {
  const frag = fragOfInvite(link);
  const fields = frag.slice(frag.indexOf(":") + 1).split(":");
  return witness(hexDecode(fields[1]));
};

// ----------------------------------------------------------------- main
//
// Guarded so the module can be imported for its classes without
// running the bridge: a test that constructs a Bridge should not
// start carrying anything.
if (import.meta.main) {


  const invite = arg("invite", null);
  const roomsDir = arg("rooms", null);
  const from = arg("from", null);
  const to = arg("to", null);
  const interval = Number(arg("interval", 10)) || 10;
  const once = arg("once", false);

  async function pump(fwd, label) {
    for (;;) {
      try {
        const out = await fwd.src.poll(fwd.room, { wait: 10 });
        // Loop guard: never re-post a line this bridge already carried, and
        // never carry back one the opposite bridge brought in.
        const lines = fwd.other
          ? fwd.uncarried(out.lines ?? []).filter((l) => !fwd.other.sent.known(fwd.room, [l]))
          : fwd.uncarried(out.lines ?? []);
        if (lines.length) {
          await fwd.dst.post(fwd.room, lines, fwd.writeHeaders);
          fwd.markCarried(lines);
          // The destination's own record of what it now holds, so a later poll
          // of it does not read as new lines to carry back.
          fwd.other?.markCarried(lines);
          fwd.state.carried += lines.length;
          fwd.save();
          info(`${label}: carried ${lines.length} line(s)`, `total ${fwd.state.carried}`);
        }
      } catch (e) {
        error(`${label} poll cycle failed`, e.message ?? e);
        await new Promise((r) => setTimeout(r, fwd.interval * 1000));
      }
    }
  }

  async function runBridge(room, fromRelay, toRelay, stateDir, { both = false } = {}) {
    const r8 = room.slice(0, 8);
    const mk = (from2, to2, tag) => {
      const b = new Bridge({
        from: from2, to: to2, room,
        // The FULL room name, not r8. The carry ledger records lines by digest,
        // so two rooms whose names share a prefix must not land in one file:
        // room A's carried lines would then read as room B's and B would
        // silently never bridge anything. r8 is fine for a log line, where a
        // collision costs a moment of confusion; for a filename it costs
        // correctness.
        statePath: `${stateDir}/kant-forward-${room}-${tag}.json`,
        interval,
        invite,
      });
      return b;
    };
    // A backlog carry that throws has carried nothing. In `--once` mode the
    // caller is a script or a test that reads the exit code as "did this
    // work", so the error has to reach it rather than be logged and dropped.
    // Exiting 0 having carried nothing is the exact failure mode this
    // rewrite exists to remove.
    const mustCarry = async (b, label) => {
      try {
        return await b.carry();
      } catch (e) {
        error(`${label} failed`, e.message ?? e);
        throw e;
      }
    };
    const fwd = mk(fromRelay, toRelay, both ? "ab" : "fwd");
    info(`room ${r8}…`, both ? `${fromRelay} <-> ${toRelay}` : `${fromRelay} -> ${toRelay}`);
    if (both) {
      const back = mk(toRelay, fromRelay, "ba");
      fwd.other = back; back.other = fwd;
      // Seed both sides' carry records from the initial carry so backfill
      // doesn't bounce: after carry, anything on a side is "known".
      info(`carrying the backlog (both directions)`);
      await mustCarry(fwd, "backlog carry fwd");
      await mustCarry(back, "backlog carry back");
      // Snapshot each side's current contents into the other's carry record, so
      // polls don't re-bounce what is already there on both ends.
      for (const [b, other] of [[fwd, back], [back, fwd]]) {
        try {
          other.markCarried((await b.src.poll(b.room, { wait: 0 })).lines ?? []);
        } catch { /* best effort */ }
      }
      if (once) return;
      await Promise.all([pump(fwd, `fwd ${r8}…`), pump(back, `back ${r8}…`)]);
      return;
    }
    info(`carrying the backlog`);
    await mustCarry(fwd, "backlog carry");
    if (once) return;
    await pump(fwd, `fwd ${r8}…`);
  }

  if (roomsDir) {
    // Self-maintaining mode: scan the rooms dir, keep one bridge per room.
    // Each room config can add `"forward": [{ "from": "...", "to": "..." }, ...]`;
    // absent, the default is local relay -> CF twin.
    const { readdirSync, readFileSync, mkdirSync } = await import("node:fs");
    const defaultFrom = arg("default-from", "https://solana.solfunmeme.com/relay");
    const defaultTo = arg("default-to", "https://kant-zk-relay.jmikedupont2.workers.dev");
    const stateDir = arg("state-dir", "/var/lib/kant-zk/forward");
    mkdirSync(stateDir, { recursive: true });
    const running = new Map(); // room8 -> true
    const scan = () => {
      for (const f of readdirSync(roomsDir).filter((f) => f.endsWith(".json"))) {
        let cfg;
        try { cfg = JSON.parse(readFileSync(`${roomsDir}/${f}`, "utf8")); } catch { continue; }
        if (!cfg.invite) continue;
        const room = roomOfInvite(cfg.invite);
        const r8 = room.slice(0, 8);
        if (running.has(r8)) continue;
        running.set(r8, true);
        const pairs = cfg.forward?.length ? cfg.forward : [{ from: defaultFrom, to: defaultTo }];
        for (const p of pairs) {
          runBridge(room, p.from, p.to, stateDir, { both: Boolean(p.both ?? cfg.both ?? arg("both", false)) }).catch((e) => {
            error(`bridge ${r8}… died`, e.message ?? e);
            running.delete(r8); // allow rescan to restart it
          });
        }
        info(`watching room ${r8}… (${f})`, `${pairs.length} bridge(s)`);
      }
    };
    scan();
    if (!once) setInterval(scan, 15000);
    setInterval(() => {}, 1 << 30);
    if (once) process.exit(0);
  } else {
    if (!invite || !from || !to) {
      console.error(`usage: node server/forward.mjs --invite '<link>' --from <relay> --to <relay> [--both] [--once] [--state <dir>]
         node server/forward.mjs --rooms <dir> [--default-from <relay>] [--default-to <relay>] [--both]`);
      process.exit(2);
    }
    const room = roomOfInvite(invite);
    const both = Boolean(arg("both", false));
    // Single-room mode honours --state (or --state-dir) instead of assuming
    // /tmp. It used to hardcode "/tmp" and ignore whatever state path it was
    // given, which made the carry ledger global: a stale ledger left by an
    // earlier run made a fresh bridge read its whole backlog as already
    // carried, and two rooms' ledgers shared a directory. Callers that need an
    // isolated ledger — tests especially — now actually get one.
    const { mkdirSync } = await import("node:fs");
    const singleStateDir = arg("state", arg("state-dir", "/tmp"));
    mkdirSync(singleStateDir, { recursive: true });
    if (once) {
      await runBridge(room, from, to, singleStateDir, { both })
        .catch((e) => { error("once carry failed", e.message ?? e); process.exit(1); });
      process.exit(0);
    }
    runBridge(room, from, to, singleStateDir, { both })
      .catch((e) => { error("fwd loop died", e.message ?? e); process.exit(1); });
    setInterval(() => {}, 1 << 30);
  }

}
