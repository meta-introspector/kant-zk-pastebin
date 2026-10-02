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
// are single-block, and the client CID is the raw leaf itself. Larger
// artifacts are split at the same boundary and addressed by a UnixFS dag-pb
// root, so `cidOf` returns exactly what `kubo add --cid-version=1
// --raw-leaves` returns at any size. See `unixfsCidOf` below; the encoding
// notes there are the ones that actually change the hash.

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
  const core = await wasmOnce();
  if (core) return core.wasm_unixfs_cid(bytes);
  return unixfsCidOf(bytes);
}

/** The block sizes an artifact of `size` bytes is split into. */
export function chunkPlanOf(size) {
  if (!Number.isInteger(size) || size < 1) throw new Error("empty artifact");
  const sizes = [];
  for (let left = size; left > 0; left -= MAX_ARTIFACT_BYTES) {
    sizes.push(Math.min(left, MAX_ARTIFACT_BYTES));
  }
  return sizes;
}

// ── UnixFS dag-pb (the multi-chunk path) ─────────────────────────────────
//
// The Rust core does this in pastebin-wasm/src/lib.rs; this is the fallback
// for browsers that cannot load the wasm. The two are held byte-identical by
// scripts/wasm-crosscheck.mjs. Four details are not obvious from the spec and
// each one changes the CID if you get it wrong, so they are pinned here:
//
//   * links come before the Data message;
//   * every link carries a Name that is present but *empty* (`0x12 0x00`) —
//     omitting it still parses, it just hashes differently;
//   * Tsize is that leaf's own size, not a running total;
//   * blocksizes are written unpacked (one `0x20` varint per chunk), not as
//     the packed `0x22` blob protobuf would also accept.

const CODEC_RAW = 0x55;
const CODEC_DAG_PB = 0x70;

function varint(value) {
  const out = [];
  let v = value;
  for (;;) {
    const byte = v & 0x7f;
    v >>>= 7;
    if (v === 0) { out.push(byte); return out; }
    out.push(byte | 0x80);
  }
}

const field = (n) => (n << 3);
const lenField = (n) => (n << 3) | 2;

/** The 36 CID identity bytes for a codec + digest. */
function cidIdentity(codec, digest) {
  const out = new Uint8Array(4 + digest.length);
  out[0] = 0x01;      // CIDv1
  out[1] = codec;
  out[2] = 0x12;      // sha2-256
  out[3] = 0x20;      // 32-byte digest
  out.set(digest, 4);
  return out;
}

const sha256 = async (bytes) => new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));

/** The raw leaf CID for one chunk. */
export async function rawCidOf(chunk) {
  return "b" + base32NoPad(cidIdentity(CODEC_RAW, await sha256(chunk)));
}

/** UnixFS `Data`: Type = File(2), filesize, unpacked blocksizes. */
function unixfsData(filesize, blocksizes) {
  const out = [...varint(field(1)), ...varint(2)];
  const push = (v) => out.push(...v);
  push(varint(field(3)));
  push(varint(filesize));
  for (const size of blocksizes) {
    push(varint(field(4)));
    push(varint(size));
  }
  return out;
}

/** The dag-pb root PBNode for a flat UnixFS file. */
function unixfsRoot(links, filesize, blocksizes) {
  const out = [];
  for (const { hash, tsize } of links) {
    const link = [
      ...varint(lenField(1)), ...varint(hash.length), ...hash,   // Hash
      ...varint(lenField(2)), ...varint(0),                      // Name: empty
      ...varint(field(3)), ...varint(tsize),                     // Tsize
    ];
    out.push(...varint(lenField(2)), ...varint(link.length), ...link);
  }
  const data = unixfsData(filesize, blocksizes);
  out.push(...varint(lenField(1)), ...varint(data.length), ...data);
  return Uint8Array.from(out);
}

/**
 * The CID an artifact is published under, matching
 * `kubo add --cid-version=1 --raw-leaves` at any size. Within one chunk this
 * is the raw leaf CID, so artifacts already published under it keep working.
 */
export async function unixfsCidOf(bytes) {
  const sizes = chunkPlanOf(bytes.length);
  if (sizes.length === 1) return rawCidOf(bytes);

  const links = [];
  for (let at = 0, i = 0; at < bytes.length; at += MAX_ARTIFACT_BYTES, i += 1) {
    const chunk = bytes.subarray(at, at + sizes[i]);
    links.push({ hash: cidIdentity(CODEC_RAW, await sha256(chunk)), tsize: sizes[i] });
  }
  const root = unixfsRoot(links, bytes.length, sizes);
  return "b" + base32NoPad(cidIdentity(CODEC_DAG_PB, await sha256(root)));
}

/** The full plan: root CID, size, chunk size, and every leaf in order. */
export async function unixfsPlanOf(bytes) {
  const sizes = chunkPlanOf(bytes.length);
  const leaves = [];
  let offset = 0;
  for (let at = 0, i = 0; at < bytes.length; at += MAX_ARTIFACT_BYTES, i += 1) {
    const chunk = bytes.subarray(at, at + sizes[i]);
    leaves.push({ index: i, cid: await rawCidOf(chunk), size: sizes[i], offset });
    offset += sizes[i];
  }
  return { root: await unixfsCidOf(bytes), size: bytes.length, chunkSize: MAX_ARTIFACT_BYTES, chunked: leaves.length > 1, leaves };
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
  // No size ceiling here: kubo applies the same 256 KiB chunking this module
  // does and returns the same root CID, so large artifacts pin fine.
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
  const plan = await unixfsPlanOf(bytes);
  if (plan.chunked) {
    // A room line is capped (the relay answers 413 above 262144B), so a
    // chunked artifact's bytes can never ride in the record: base64 of a
    // 400 KB zip is ~533 KB. Announce the leaves and let the fetcher pull
    // them. The root CID is what the reassembly is verified against.
    rec.pinned = Boolean(pinned);
    rec.chunked = true;
    rec.chunkSize = plan.chunkSize;
    rec.leaves = plan.leaves.map((l) => ({ cid: l.cid, size: l.size, offset: l.offset }));
  } else if (pinned) {
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
  if (lineObj.chunked !== true && lineObj.pinned === false && typeof lineObj.b64 !== "string") return null;
  if (lineObj.chunked === true) {
    // The bytes live behind the leaves, so a record without a usable leaf
    // list announces nothing anyone could fetch.
    if (!Array.isArray(lineObj.leaves) || !lineObj.leaves.length) return null;
    if (typeof lineObj.chunkSize !== "number") return null;
    const total = lineObj.leaves.reduce((a, l) => a + (typeof l.size === "number" ? l.size : 0), 0);
    if (total !== lineObj.size) return null;
  }
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
