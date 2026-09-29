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
//       [--interval 10] [--state f.json]
//
// The invite's room (a digest of the secret, which neither relay ever
// learns) names the same room on both relays: that is the interlink.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { RelayClient } from "../web/kant-net.mjs";

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
  constructor({ from, to, room, statePath, interval = 10 }) {
    this.src = new RelayClient(from);
    this.dst = new RelayClient(to);
    this.from = from;
    this.to = to;
    this.room = room;
    this.interval = Math.max(1, Number(interval) || 10);
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
const interval = Number(arg("interval", 10)) || 10;
const once = arg("once", false);

const { witness, hexDecode } = await import("../web/kantzk.mjs");

// The room name from an invite link fragment:
const roomOfInvite = (link) => {
  const frag = String(link).match(/#(.+)$/)?.[1];
  const fields = frag.slice(frag.indexOf(":") + 1).split(":");
  return witness(hexDecode(fields[1]));
};

async function runBridge(room, fromRelay, toRelay, stateDir) {
  const statePath = `${stateDir}/kant-forward-${room.slice(0, 8)}.json`;
  info(`room ${room.slice(0, 8)}…`, `${fromRelay} -> ${toRelay}`);
  const fwd = new Bridge({ from: fromRelay, to: toRelay, room, statePath, interval });
  info(`carrying the backlog`);
  await fwd.carry().catch((e) => error("backlog carry failed", e.message ?? e));
  if (once) return;
  for (;;) {
    try {
      const out = await fwd.src.poll(fwd.room, { wait: 10 });
      const lines = out.lines ?? [];
      if (lines.length) {
        await fwd.dst.post(fwd.room, lines);
        fwd.state.carried += lines.length;
        fwd.save();
        info(`fwd ${room.slice(0, 8)}…: carried ${lines.length} line(s)`, `total ${fwd.state.carried}`);
      }
    } catch (e) {
      error(`fwd ${room.slice(0, 8)}… poll cycle failed`, e.message ?? e);
      await new Promise((r) => setTimeout(r, interval * 1000));
    }
  }
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
        runBridge(room, p.from, p.to, stateDir).catch((e) => {
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
    console.error(`usage: node server/forward.mjs --invite '<link>' --from <relay> --to <relay>
       node server/forward.mjs --rooms <dir> [--default-from <relay>] [--default-to <relay>]`);
    process.exit(2);
  }
  const room = roomOfInvite(invite);
  if (once) {
    await runBridge(room, from, to, "/tmp").catch((e) => { error("once carry failed", e.message ?? e); process.exit(1); });
    process.exit(0);
  }
  runBridge(room, from, to, "/tmp").catch((e) => { error("fwd loop died", e.message ?? e); process.exit(1); });
  setInterval(() => {}, 1 << 30);
}
