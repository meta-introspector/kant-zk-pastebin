// kant-p2p.mjs — the p2p webapp layer: peers meet in a relay room and share
// IPFS-addressed artifacts; wasm experiments run in-browser.
//
// Goal-base #8/#11: each peer is a relay client; artifacts ride by CID
// (ipfs-pinned when a node is reachable, embedded in the room as fallback),
// so the relay carries coordination, not bulk. Experiments reuse the
// Lean-proved kernel (kant-wasm.mjs — merge_cids over published CIDs is the
// canonical demo: the math that proves the merge is the same math the room
// uses), and the vendored aristotle-wasm module adds heavier experiments.
//
//   import { P2PApp } from "./kant-p2p.mjs";
//   const app = new P2PApp({ relayBase, room, peer });
//   await app.start();                       // announces presence, starts polling
//   const rec = await app.publish(name, bytes, note);
//   const { bytes, via } = await app.fetch(rec);
//   app.on("artifact", (rec) => ...);        // every kzcid record seen
//   const out = await app.experiment("merge-cids", { a: cidA, b: cidB });
//
// Lines are single-line JSON (the relay stores strings; maxLine applies —
// embedded fallbacks are size-capped in kant-ipfs.mjs accordingly).

import { RelayClient } from "./kant-net.mjs";
import { utf8, witness, fnv1a } from "./kantzk.mjs";
import {
  cidOf, publishArtifact, fetchArtifact, decodeCidRecord,
  MAX_ARTIFACT_BYTES,
} from "./kant-ipfs.mjs";
import { loadKernel } from "./kant-wasm.mjs";

const MAX_LINE_BYTES = 60_000; // stay under a conservative relay --max-line

export class P2PApp {
  /**
   * @param relayBase  e.g. "http://127.0.0.1:8787" (or the public /pastebin-relay/ edge)
   * @param room       room secret (raw name; the relay hashes it for storage refs)
   * @param peer       this peer's display name (becomes part of its id)
   */
  constructor({ relayBase, room, peer, log = console }) {
    this.relay = new RelayClient(relayBase, { log });
    this.room = room;
    this.peer = peer;
    this.log = log;
    // stable-ish peer id: name + short witness of name+time (not a secret)
    this.id = `${peer}#${witness([...utf8(peer), Date.now() & 0xffffff]).slice(0, 8)}`;
    this.seen = new Map();   // cid -> record (dedupe across peers)
    this.handlers = { artifact: [], peer: [], experiment: [] };
    this.polling = null;
    this.kernel = null;      // lazy-loaded proved wasm kernel
  }

  on(event, fn) { this.handlers[event]?.push(fn); }
  emit(event, data) { for (const fn of this.handlers[event] ?? []) Promise.resolve(fn(data)).catch((e) => this.log.error?.("p2p", `${event} handler failed`, e.message ?? e)); }

  /** Presence line so late joiners see who is in the room. */
  presenceLine() {
    return JSON.stringify({ tag: "kzpeer", peer: this.id, ts: Date.now() });
  }

  async start() {
    await this.relay.health();
    await this.relay.post(this.room, [this.presenceLine()]);
    this.polling = true;
    this.pollLoop(); // async, never awaited
    return this;
  }

  stop() { this.polling = false; }

  async pollLoop() {
    while (this.polling) {
      try {
        const out = await this.relay.poll(this.room, { wait: 25 });
        for (const line of out.lines ?? []) this.handleLine(line);
      } catch (e) {
        await new Promise((r) => setTimeout(r, 2000)); // backoff, keep polling
      }
    }
  }

  handleLine(line) {
    let obj;
    try { obj = JSON.parse(line); } catch { return; } // foreign lines are fine
    if (!obj?.tag) return;
    if (obj.tag === "kzpeer") {
      if (obj.peer !== this.id) this.emit("peer", obj);
      return;
    }
    if (obj.tag === "kzcidx") { this.emit("experiment", obj); return; }
    const rec = decodeCidRecord(obj);
    if (!rec) return;
    if (rec.peer === this.id) return;              // our own echo
    const prior = this.seen.get(rec.cid);
    this.seen.set(rec.cid, rec);
    if (!prior) this.emit("artifact", rec);
  }

  /** Post one JSON record as a room line; refuses oversized embedded fallbacks. */
  async postRecord(rec) {
    const line = JSON.stringify(rec);
    const bytes = new TextEncoder().encode(line);
    if (bytes.length > MAX_LINE_BYTES) {
      throw new Error(`record too large for one room line (${bytes.length}B) — pin it or shrink the artifact`);
    }
    await this.relay.post(this.room, [line]);
  }

  /**
   * Publish an artifact: pin via kubo when reachable, else embed in the room
   * (verified end to end by CID on fetch). Announces the kzcid record.
   */
  async publish(name, bytes, { note = "", rpcBase, gwBase } = {}) {
    // No size ceiling: anything past one chunk is addressed by its UnixFS
    // dag-pb root and announced as a leaf list. encodeCidRecord decides
    // whether the bytes can ride in the record (they cannot once the base64
    // would exceed a relay line), so a chunked publish carries leaves only
    // and the fetcher resolves the root through a gateway.
    const rec = await publishArtifact({ peer: this.id, name, bytes, note, rpcBase, gwBase });
    await this.postRecord(rec);
    this.seen.set(rec.cid, rec);
    return rec;
  }

  /** Fetch an announced artifact (gateway first, embedded fallback), CID-verified. */
  async fetch(rec, { gwBase } = {}) {
    const out = await fetchArtifact(rec, { gwBase });
    if (!out) throw new Error(`artifact ${rec.cid} unreachable (no gateway, no embedded copy)`);
    return out;
  }

  /** Subscribe a room peer's embedded copy to local kubo; re-announce pinned. */
  async repin(rec) {
    const { bytes } = await this.fetch(rec);
    const { ipfsAdd } = await import("./kant-ipfs.mjs");
    const cid = await ipfsAdd(bytes, rec.name);
    if (cid && cid === rec.cid) {
      await this.postRecord({ ...rec, peer: this.id, pinned: true });
      delete rec.b64;
      return true;
    }
    return false;
  }

  /** The proved Lean kernel, loaded once (merge_cids etc.). */
  async kernelOnce() {
    if (!this.kernel) this.kernel = await loadKernel();
    return this.kernel;
  }

  /**
   * Run a named experiment locally and announce the result as a kzcidx record
   * (never auto-embedded unless small — results are usually tiny JSON).
   */
  async experiment(kind, args = {}) {
    const started = Date.now();
    let result;
    switch (kind) {
      case "merge-cids": {
        const k = await this.kernelOnce();
        // inputs may be u64 strings or CID strings — CIDs are witness-hashed
        // to u64 (fnv1a, the same digest the room uses for room names)
        const toU64 = (s) => /^\d+$/.test(String(s)) ? BigInt(s) : BigInt(fnv1a(utf8(String(s))));
        const a = toU64(args.a), b = toU64(args.b);
        const merged = k.mergeCids(a, b);
        result = { merged: merged.toString(), a: a.toString(), b: b.toString() };
        break;
      }
      case "cid-of-bytes": {
        const bytes = args.bytes instanceof Uint8Array ? args.bytes : utf8(String(args.text ?? ""));
        result = { cid: await cidOf(bytes), size: bytes.length };
        break;
      }
      case "room-digest": {
        // fnv1a over the room's published CIDs — a cheap integrity fingerprint
        const cids = [...this.seen.keys()].sort();
        result = { count: cids.length, digest: fnv1a([...utf8(cids.join("\n"))]).toString() };
        break;
      }
      case "arist": {
        // heavier experiments via the vendored aristotle-wasm module, if built
        const mod = await import("./arist-wasm.mjs").catch(() => null);
        if (!mod?.available?.()) { result = { error: "aristotle-wasm not built — run scripts/build-arist-wasm.sh" }; break; }
        result = await mod.run(args);
        break;
      }
      default:
        result = { error: `unknown experiment ${kind}` };
    }
    const rec = {
      tag: "kzcidx", peer: this.id, kind, args: { ...args, bytes: undefined },
      result, ms: Date.now() - started, ts: Date.now(),
    };
    await this.postRecord(rec).catch(() => {}); // result sharing is best-effort
    return rec;
  }
}

export { MAX_ARTIFACT_BYTES };
