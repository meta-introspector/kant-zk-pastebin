// kant-ipfs.mjs — IPFS attachment layer for the kant p2p webapp.
//
// Goal (goal-base #8/#11): artifacts (pastes, wasm experiment bundles, results)
// are shared peer-to-peer by exchanging CIDs over relay rooms; each peer that
// can reach an IPFS node pins and serves them, so the relay itself never learns
// or stores artifact bytes unless a peer explicitly embeds them as a fallback.
//
// CIDs are computed CLIENT-SIDE as CIDv1/raw/sha2-256, and `ipfsAdd` asks kubo
// for exactly that form (`cid-version=1&raw-leaves=true`), so the CID a peer
// announces always matches what every other peer computes from the bytes —
// independent of kubo's defaults (which would be CIDv0/dag-pb).
//
//   import { cidOf, ipfsAdd, ipfsCat, encodeCidRecord, decodeCidRecord } from "./kant-ipfs.mjs";
//   const cid = await cidOf(bytes);            // works offline, no node needed
//   const pinned = await ipfsAdd(bytes, name); // null when no local kubo
//   const bytes = await ipfsCat(cid);          // gateway fetch, null when unreachable
//
// Size discipline: artifacts up to MAX_ARTIFACT_BYTES (one kubo chunk, 256 KiB)
// are single-block, which is what makes the client-side CID identical to
// kubo's. Larger artifacts must be chunked by the caller (or use the local
// kubo directly and only announce the CID).

import { utf8, fromUtf8, hexDecode } from "./kantzk.mjs";

// ── the Rust core (pastebin-wasm), preferred over the JS path ──────────
//
// `pastebin-wasm` (pastebin-wasm/src/lib.rs) computes the very same
// CIDv1/raw/sha2-256 in compiled Rust — cross-checked byte-for-byte
// against this module by scripts/wasm-crosscheck.mjs.  Loaded lazily;
// when unavailable (old browser, blocked wasm) the pure-JS path below
// keeps working.
let wasmCore = null;
let wasmTried = false;

/** The wasm core, or `null` when it cannot load. */
export async function wasmOnce() {
  if (wasmTried) return wasmCore;
  wasmTried = true;
  try {
    const mod = await import("./pastebin_wasm.js");
    try {
      await mod.default();
    } catch {
      // Node (and some sandboxes) cannot fetch the wasm over file:// URLs:
      // hand the glue the bytes explicitly.  Browsers take the fetch path.
      const { readFileSync } = await import("node:fs");
      const bytes = readFileSync(new URL("./pastebin_wasm_bg.wasm", import.meta.url));
      await mod.default({ module_or_path: bytes });
    }
    wasmCore = mod;
  } catch {
    wasmCore = null;
  }
  return wasmCore;
}

/** One kubo chunk; ≤ this size the client CID == the node CID. */
export const MAX_ARTIFACT_BYTES = 262144;

/** Default kubo RPC and gateway endpoints (override via p2papp settings). */
export const KUBO_RPC = "http://127.0.0.1:5001";
export const GATEWAY = "http://127.0.0.1:8080";

// ── CIDv1 raw sha2-256 ──────────────────────────────────────────────────

/** RFC4648 base32, lowercase, no padding — the multibase identity for `b`. */
export function base32NoPad(bytes) {
  const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
  let bits = 0, value = 0, out = "";
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += alphabet[(value << (5 - bits)) & 31];
  return out;
}

/**
 * CIDv1, codec `raw` (0x55), multihash sha2-256 (0x12, length 0x20):
 *   <0x01 0x55> <0x12 0x20> <32-byte digest>, multibase base32, `b` prefix.
 * Matches `kubo add --cid-version=1 --raw-leaves` for ≤ one-chunk inputs.
 */
export async function cidOf(bytes) {
  if (bytes.length > MAX_ARTIFACT_BYTES) {
    throw new Error(`artifact ${bytes.length}B > ${MAX_ARTIFACT_BYTES}B — chunk it or use kubo directly`);
  }
  const core = await wasmOnce();
  if (core) return core.wasm_cid_of_bytes(bytes);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const cidBytes = new Uint8Array(2 + 2 + digest.length);
  cidBytes[0] = 0x01;              // CIDv1
  cidBytes[1] = 0x55;              // raw codec
  cidBytes[2] = 0x12;              // sha2-256
  cidBytes[3] = 0x20;              // 32-byte digest length
  cidBytes.set(digest, 4);
  return "b" + base32NoPad(cidBytes);
}

/** Round-trip helper used by tests: CID string → the 36 identity bytes. */
export function cidBytes(cid) {
  if (!cid.startsWith("b")) throw new Error(`not a base32 multibase CID: ${cid}`);
  const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
  const s = cid.slice(1);
  let bits = 0, value = 0;
  const out = [];
  for (const ch of s) {
    const idx = alphabet.indexOf(ch);
    if (idx < 0) throw new Error(`bad base32 char ${ch}`);
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8Array.from(out);
}

// ── kubo RPC / gateway (both optional at runtime) ───────────────────────

/**
 * Add + pin via a local kubo RPC. Returns the CID string, or null when kubo
 * is unreachable/CORS-blocked — callers then fall back to embedding the bytes
 * in the room record. `rpcBase` injectable for tests.
 */
export async function ipfsAdd(bytes, name = "artifact.bin", rpcBase = KUBO_RPC) {
  if (bytes.length > MAX_ARTIFACT_BYTES) return null;
  try {
    const form = new FormData();
    form.append("file", new Blob([bytes]), name);
    const res = await fetch(
      `${rpcBase}/api/v0/add?cid-version=1&raw-leaves=true&pin=true&quieter=true`,
      { method: "POST", body: form },
    );
    if (!res.ok) return null;
    const lines = (await res.text()).trim().split("\n");
    const last = JSON.parse(lines[lines.length - 1]);
    return last.Hash ?? null;
  } catch {
    return null;
  }
}

/**
 * Fetch artifact bytes from an IPFS gateway. Returns null when unreachable —
 * callers then ask the room for an embedded copy. `gwBase` injectable.
 */
export async function ipfsCat(cid, gwBase = GATEWAY, timeoutMs = 8000) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetch(`${gwBase}/ipfs/${cid}`, { signal: ctl.signal });
    if (!res.ok) return null;
    return new Uint8Array(await res.arrayBuffer());
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// ── kzcid room records ──────────────────────────────────────────────────
// A room line carrying TAG_CID announces an artifact:
//   { tag:"kzcid", peer, name, cid, size, pinned, b64? }
// `pinned:false` + `b64` means "embed fallback": the bytes ride the room until
// a peer with a node pins them and announces the same CID (which peers detect
// and may then drop the embedded copy from their local view).

const TAG_CID = utf8("kzcid");

export function bytesToB64(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

export function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Build the room-line object for an artifact. */
export async function encodeCidRecord({ peer, name, bytes, pinned, note = "" }) {
  const cid = await cidOf(bytes);
  const rec = { tag: "kzcid", peer, name, cid, size: bytes.length, note, ts: Date.now() };
  if (pinned) {
    rec.pinned = true;
  } else {
    rec.pinned = false;
    rec.b64 = bytesToB64(bytes);
  }
  return rec;
}

export function decodeCidRecord(lineObj) {
  if (!lineObj || lineObj.tag !== "kzcid") return null;
  if (typeof lineObj.cid !== "string" || !lineObj.cid.startsWith("b")) return null;
  if (lineObj.pinned === false && typeof lineObj.b64 !== "string") return null;
  return lineObj;
}

/**
 * Full publish: compute CID, try to pin via kubo, fall back to embedding.
 * Returns the room record ready to POST as a line.
 */
export async function publishArtifact({ peer, name, bytes, note = "", rpcBase, gwBase } = {}) {
  const pinned = (await ipfsAdd(bytes, name, rpcBase)) !== null;
  const rec = await encodeCidRecord({ peer, name, bytes, pinned, note });
  rec.via = pinned ? "ipfs" : "room";
  return rec;
}

/**
 * Full fetch for an announced record: gateway first, embedded fallback second.
 * Returns { bytes, via } or null.
 */
export async function fetchArtifact(rec, { gwBase } = {}) {
  const r = decodeCidRecord(rec);
  if (!r) return null;
  const gw = await ipfsCat(r.cid, gwBase);
  if (gw) {
    if ((await cidOf(gw)) !== r.cid) return null;  // integrity: never trust a lying gateway
    return { bytes: gw, via: "ipfs" };
  }
  if (r.b64) {
    const bytes = b64ToBytes(r.b64);
    if ((await cidOf(bytes)) !== r.cid) return null; // integrity: room copy is verified too
    return { bytes, via: "room" };
  }
  return null;
}

/** True when an incoming record duplicates one already known (same CID). */
export const sameArtifact = (a, b) => a?.cid && a.cid === b?.cid;
