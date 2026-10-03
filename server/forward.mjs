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
//       [--interval 60] [--wait 10] [--max-interval 900] [--state f.json]
//
// The invite's room (a digest of the secret, which neither relay ever
// learns) names the same room on both relays: that is the interlink.
//
// Pacing: the default interval is deliberately NOT 10s.  The destination
// may be a Durable Object on Cloudflare's free tier, which bills storage
// *duration*, so a bridge that long-polls `wait` seconds every `interval`
// seconds holds the room open a `wait/interval` fraction of the time —
// at 10/10 that is four rooms held open permanently, in the normal
// healthy case, not under failure.  The long poll is therefore capped to
// a third of the period, and a failure backs off exponentially rather
// than retrying at the same cost.  See server/backoff.mjs.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { RelayClient } from "../web/kant-net.mjs";
import { Backoff, sleep, holdFor } from "./backoff.mjs";

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
// name — it never needs the secret, because it re-posts raw lines
// that already carry their own witness.  (Resolved in main, after the
// dynamic import of kantzk.mjs below.)

// --------------------------------------------------------------- bridge

class Bridge {
  // `interval`, `wait` and `maxInterval` arrive in SECONDS, from the
  // command line.  Backoff works in milliseconds, so convert here, once.
  constructor({ from, to, room, statePath, interval = 60, wait = 10,
                maxInterval = 900 }) {
    this.src = new RelayClient(from);
    this.dst = new RelayClient(to);
    this.from = from;
    this.to = to;
    this.room = room;
    this.interval = Math.max(1, Number(interval) || 60);
    // Never hold the relay open longer than our share of the period.
    this.wait = holdFor(this.interval, wait);
    // Each destination gets its own pacer, so one dead relay cannot
    // stretch the other bridge's cadence.
    this.pace = new Backoff({
      base: this.interval * 1000,
      cap: Math.max(1, Number(maxInterval) || 900) * 1000,
    });
    this.statePath = statePath;
    this.state = existsSync(statePath)
      ? JSON.parse(readFileSync(statePath, "utf8"))
      : { carried: 0 };
  }

  save() { writeFileSync(this.statePath, JSON.stringify(this.state, null, 2) + "\n"); }

  /** Carry every line the source has past our cursor to the destination.
   *  On the first carry (backlog) the destination is read first and any
   *  line it already has is skipped, so restarting the bridge is
   *  idempotent — the destination never grows duplicate history. */
  async carry() {
    const out = await this.src.poll(this.room, { wait: 0 });
    let lines = out.lines ?? [];
    if (!lines.length) return 0;
    if (!this.state.synced) {
      const have = new Set((await this.dst.poll(this.room, { wait: 0 })).lines ?? []);
      const fresh = lines.filter((l) => !have.has(l));
      const skipped = lines.length - fresh.length;
      if (skipped) info(`backlog: skipped ${skipped} line(s) already on the destination`);
      lines = fresh;
      this.state.synced = true;
      if (!lines.length) { this.save(); return 0; }
    }
    await this.dst.post(this.room, lines);
    this.state.carried += lines.length;
    this.save();
    return lines.length;
  }
}

// ----------------------------------------------------------------- main

const invite = arg("invite", null);
const roomsDir = arg("rooms", null);
const from = arg("from", null);
const to = arg("to", null);
// Default 60s, not 10s: see the header.  A 10s period with a 10s long
// poll holds a free-tier Durable Object open ~100% of the time.
const interval = Number(arg("interval", 60)) || 60;
const wait = Number(arg("wait", 10)) || 0;
const maxInterval = Number(arg("max-interval", 900)) || 900;
const once = arg("once", false);

const { witness, hexDecode } = await import("../web/kantzk.mjs");

// The room name from an invite link fragment:
const roomOfInvite = (link) => {
  const frag = String(link).match(/#(.+)$/)?.[1];
  const fields = frag.slice(frag.indexOf(":") + 1).split(":");
  return witness(hexDecode(fields[1]));
};

async function pump(fwd, label) {
  for (;;) {
    try {
      const out = await fwd.src.poll(fwd.room, { wait: fwd.wait });
      let lines = out.lines ?? [];
      // Loop guard: never re-post a line this bridge put on the source.
      if (fwd.pushed?.size) lines = lines.filter((l) => !fwd.pushed.has(l));
      if (lines.length) {
        await fwd.dst.post(fwd.room, lines);
        fwd.state.carried += lines.length;
        for (const l of lines) fwd.other?.pushed?.add(l);
        fwd.save();
        info(`${label}: carried ${lines.length} line(s)`, `total ${fwd.state.carried}`);
      }
      fwd.pace.ok();
    } catch (e) {
      const { delay, kind, status, failures } = fwd.pace.fail(e);
      // A quota-exhausted destination is not going to recover by being
      // asked again, so name the wait in the log: a line every 10s
      // saying "500" reads as an outage rather than as a bridge
      // correctly sitting out its budget window.
      if (kind === "quota") {
        error(`${label}: destination is out of its Durable Objects duration budget`
          + `${status ? ` (${status})` : ""} — not retrying for ${Math.round(delay / 1000)}s`,
          e.message ?? e);
      } else if (failures === 1 || failures % 8 === 0) {
        error(`${label} poll cycle failed`, `${e.message ?? e} — retrying in ${Math.round(delay / 1000)}s`);
      }
      await sleep(delay);
      continue;
    }
    // A successful cycle: the poll already blocked for up to `wait`
    // seconds, so only the remainder of the period is left to wait.
    const spent = fwd.wait * 1000;
    if (fwd.interval * 1000 > spent) await sleep(fwd.interval * 1000 - spent);
  }
}

async function runBridge(room, fromRelay, toRelay, stateDir, { both = false } = {}) {
  const r8 = room.slice(0, 8);
  const mk = (from2, to2, tag) => {
    const b = new Bridge({
      from: from2, to: to2, room,
      statePath: `${stateDir}/kant-forward-${r8}-${tag}.json`,
      interval, wait, maxInterval,
    });
    b.pushed = new Set(); // lines this side has posted to its destination
    return b;
  };
  const fwd = mk(fromRelay, toRelay, both ? "ab" : "fwd");
  info(`room ${r8}…`, both ? `${fromRelay} <-> ${toRelay}` : `${fromRelay} -> ${toRelay}`);
  info(`  polling every ${interval}s, holding at most ${holdFor(interval, wait)}s`
    + `, backing off to ${maxInterval}s`);
  if (both) {
    const back = mk(toRelay, fromRelay, "ba");
    fwd.other = back; back.other = fwd;
    // Seed both sides' push-sets from the initial carry so backfill
    // doesn't bounce: after carry, anything on a side is "known".
    info(`carrying the backlog (both directions)`);
    await fwd.carry().catch((e) => error("backlog carry fwd failed", e.message ?? e));
    await back.carry().catch((e) => error("backlog carry back failed", e.message ?? e));
    // Snapshot current contents into pushed sets so polls don't re-bounce.
    for (const [b, other] of [[fwd, back], [back, fwd]]) {
      try {
        for (const l of (await b.src.poll(b.room, { wait: 0 })).lines ?? []) other.pushed.add(l);
      } catch { /* best effort */ }
    }
    if (once) return;
    await Promise.all([pump(fwd, `fwd ${r8}…`), pump(back, `back ${r8}…`)]);
    return;
  }
  info(`carrying the backlog`);
  await fwd.carry().catch((e) => error("backlog carry failed", e.message ?? e));
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
  // Returns the bridges it started, so `--once` can await them.  It used
  // to return nothing and fire-and-forget, which meant `process.exit(0)`
  // below ran before any relay had been contacted: `--rooms … --once`
  // reported the rooms it found and then exited having done nothing.
  const scan = () => {
    const started = [];
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
        started.push(runBridge(room, p.from, p.to, stateDir, { both: Boolean(p.both ?? cfg.both ?? arg("both", false)) }).catch((e) => {
          error(`bridge ${r8}… died`, e.message ?? e);
          running.delete(r8); // allow rescan to restart it
        }));
      }
      info(`watching room ${r8}… (${f})`, `${pairs.length} bridge(s)`);
    }
    return started;
  };
  const firstScan = scan();
  if (once) {
    // Carry every backlog, report what happened, and only then exit.
    await Promise.all(firstScan);
    process.exit(0);
  }
  setInterval(scan, 15000);
  setInterval(() => {}, 1 << 30);
} else {
  if (!invite || !from || !to) {
    console.error(`usage: node server/forward.mjs --invite '<link>' --from <relay> --to <relay> [--both]
       node server/forward.mjs --rooms <dir> [--default-from <relay>] [--default-to <relay>] [--both]`);
    process.exit(2);
  }
  const room = roomOfInvite(invite);
  const both = Boolean(arg("both", false));
  if (once) {
    await runBridge(room, from, to, "/tmp", { both }).catch((e) => { error("once carry failed", e.message ?? e); process.exit(1); });
    process.exit(0);
  }
  runBridge(room, from, to, "/tmp", { both }).catch((e) => { error("fwd loop died", e.message ?? e); process.exit(1); });
  setInterval(() => {}, 1 << 30);
}
