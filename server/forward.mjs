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
const from = arg("from", null);
const to = arg("to", null);
if (!invite || !from || !to) {
  console.error(`usage: node server/forward.mjs --invite '<link>' --from <relay> --to <relay>`);
  process.exit(2);
}

const { witness, hexDecode } = await import("../web/kantzk.mjs");
const frag = String(invite).match(/#(.+)$/)?.[1];
const fields = frag.slice(frag.indexOf(":") + 1).split(":");
const room = witness(hexDecode(fields[1]));
const statePath = arg("state", `/tmp/kant-forward-${room.slice(0, 8)}.json`);
info(`room ${room.slice(0, 8)}…`, `${from} -> ${to}`);

const fwd = new Bridge({ from, to, room, statePath, interval: arg("interval", 10) });

// First carry the backlog once, then loop: long-poll the source, post
// whatever arrives, and (in --both mode) the same the other way.
info(`carrying the backlog`);
await fwd.carry().catch((e) => error("backlog carry failed", e.message ?? e));

async function loop(bridge, label) {
  for (;;) {
    try {
      const out = await bridge.src.poll(bridge.room, { wait: 10 });
      const lines = out.lines ?? [];
      if (lines.length) {
        await bridge.dst.post(bridge.room, lines);
        bridge.state.carried += lines.length;
        bridge.save();
        info(`${label}: carried ${lines.length} line(s)`, `total ${bridge.state.carried}`);
      }
    } catch (e) {
      error(`${label} poll cycle failed`, e.message ?? e);
      await new Promise((r) => setTimeout(r, bridge.interval * 1000));
    }
  }
}
loop(fwd, "fwd").catch((e) => { error("fwd loop died", e.message ?? e); process.exit(1); });
setInterval(() => {}, 1 << 30);
