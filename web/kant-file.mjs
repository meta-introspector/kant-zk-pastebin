// kant-file.mjs — a file dropped into a room.
//
// The file never leaves the browser in the clear: it is cut into chunks,
// each chunk encrypted with a key the room already shares (the secret in
// the invite link), and only the ciphertext is pinned on the relay.
// Every chunk is content-addressed — its name is the digest of its
// ciphertext — so a peer can fetch it from any relay or any other peer
// and know it got exactly the bytes that were pinned.  The relay never
// learns the name, the type, or a single plaintext byte.
//
// The announcement travels as an ordinary self-certifying room line
// (`kzfile`): the manifest names the file, its size, the per-file nonce,
// and the chunk digests, and carries the same style of witness as a
// kzchat line, so a forged or mangled announcement is refused by every
// peer before a single chunk is fetched.
//
//   RequestProject/Kant/File.lean — spec to follow; until then the
//   witness construction mirrors `Kant.Msg.core` exactly.

import {
  asciiBytes, asciiChars, bytesBEToNat, envelopeDecode, envelopeEncode,
  fromUtf8, natToBytesBE, utf8, witness,
} from "./kantzk.mjs";

const eqBytes = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

export const TAG_FILE = asciiBytes("kzfile");

/** Chunks are 256 KiB of plaintext; the relay's --max-block is larger so
 *  the ciphertext (with its GCM tag) always fits one block write. */
export const CHUNK_SIZE = 262144;

/** The digest that names a chunk — the relay recomputes it on write. */
export const cidOf = (bytes) => witness(Array.from(bytes));

// -------------------------------------------------------------- crypto

const subtle = () => globalThis.crypto.subtle;

// ── the Rust core (pastebin-wasm), preferred over WebCrypto ──────────
//
// `pastebin-wasm/src/lib.rs` is an exact port of `encryptFile` below: same
// HKDF over the room secret salted with the file nonce, same index-into-the
// last-four-bytes nonce, same bare `ciphertext || tag` output with no
// version byte and no AAD. scripts/wasm-crosscheck.mjs checks the two agree
// byte-for-byte, including past the 256 KiB chunk boundary, so this is a
// swap of implementation and not of format — a manifest written by one is
// read by the other.
//
// Loaded lazily and independently of kant-ipfs.mjs's own copy, because a
// caller may want the file crypto with no IPFS daemon in sight. When the
// wasm cannot load (old browser, blocked wasm) WebCrypto below still works,
// so dropping a file never hard-fails on this.
let cryptoCore = null;
let cryptoTried = false;

/** The Rust chunk crypto, or `null` when it cannot load. */
export async function cryptoOnce() {
  if (cryptoTried) return cryptoCore;
  cryptoTried = true;
  try {
    const mod = await import("./pastebin_wasm.js");
    try {
      await mod.default();
    } catch {
      // Node (and some sandboxes) cannot fetch the wasm over file:// URLs:
      // hand the glue the bytes explicitly. Browsers take the fetch path.
      const { readFileSync } = await import("node:fs");
      const bytes = readFileSync(new URL("./pastebin_wasm_bg.wasm", import.meta.url));
      await mod.default({ module_or_path: bytes });
    }
    cryptoCore = mod;
  } catch {
    cryptoCore = null;
  }
  return cryptoCore;
}

/** Encrypt one chunk through whichever core is available. */
async function encryptChunk(secret, nonce, index, plain) {
  const core = await cryptoOnce();
  if (core) return new Uint8Array(core.wasm_encrypt_chunk(secret, nonce, index, plain));
  return new Uint8Array(await subtle().encrypt(
    { name: "AES-GCM", iv: Uint8Array.from(chunkNonce(nonce, index)) },
    await fileKey(secret, nonce), plain));
}

/** Decrypt one chunk through whichever core is available. */
async function decryptChunk(secret, nonce, index, cipher) {
  const core = await cryptoOnce();
  if (core) return new Uint8Array(core.wasm_decrypt_chunk(secret, nonce, index, cipher));
  return new Uint8Array(await subtle().decrypt(
    { name: "AES-GCM", iv: Uint8Array.from(chunkNonce(nonce, index)) },
    await fileKey(secret, nonce), cipher));
}

/** The file key: the room secret, stretched per file so two files in one
 *  room never share a key (`Kant.File.derive`). */
async function fileKey(secret, nonce) {
  const base = await subtle().importKey("raw", Uint8Array.from(secret), "HKDF", false, ["deriveKey"]);
  return subtle().deriveKey(
    { name: "HKDF", hash: "SHA-256", salt: Uint8Array.from(nonce), info: Uint8Array.from(utf8("kant-file")) },
    base, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}

/** One nonce per file; the chunk index rides in its last four bytes, so
 *  a nonce is never reused for two different plaintexts under one key. */
const chunkNonce = (nonce, index) => {
  const out = nonce.slice();
  out[8] ^= (index >>> 24) & 0xff;
  out[9] ^= (index >>> 16) & 0xff;
  out[10] ^= (index >>> 8) & 0xff;
  out[11] ^= index & 0xff;
  return out;
};

/** Cut, encrypt, name.  Returns the manifest (without room/sender/seq)
 *  and the encrypted chunks in order. */
export async function encryptFile(secret, name, mime, data) {
  const nonce = Array.from(globalThis.crypto.getRandomValues(new Uint8Array(12)));
  const chunks = [];
  const cids = [];
  for (let off = 0, i = 0; off < data.length || i === 0; off += CHUNK_SIZE, i += 1) {
    const plain = data.slice(off, Math.min(off + CHUNK_SIZE, data.length));
    const cipher = await encryptChunk(secret, nonce, i, plain);
    chunks.push(cipher);
    cids.push(cidOf(cipher));
    if (off + CHUNK_SIZE >= data.length) break;
  }
  return {
    name, mime, size: data.length,
    nonce, cids, chunks,
  };
}

/** Fetch and decrypt every chunk back into the original bytes; any chunk
 *  whose digest does not match its cid is refused. */
export async function decryptFile(secret, manifest, fetchChunk) {
  const out = new Uint8Array(manifest.size);
  for (let i = 0; i < manifest.cids.length; i += 1) {
    const cipher = new Uint8Array(await fetchChunk(manifest.cids[i]));
    if (cidOf(cipher) !== manifest.cids[i]) {
      throw new Error(
        `chunk ${i} is not its own name (expected ${manifest.cids[i].slice(0, 12)}…)`);
    }
    const plain = await decryptChunk(secret, manifest.nonce, i, cipher);
    out.set(plain, i * CHUNK_SIZE);
  }
  return out;
}

// ---------------------------------------------------------- the manifest

export const manifest = (room, sender, seq, name, mime, size, nonce, cids, ipfs = []) =>
  ({ room, sender, seq, name, mime, size, nonce, cids, ipfs });

/** The bytes a manifest commits to — same shape as `Msg.core`.
 *
 *  The IPFS names are committed to only when the manifest carries them,
 *  so a relay-only manifest hashes to exactly the bytes it always did
 *  and an older line still verifies against its own witness. */
export const manifestCore = (f) => [
  ...asciiBytes(f.room), 0, ...asciiBytes(f.sender), 0,
  ...natToBytesBE(f.seq), 0,
  ...utf8(f.name), 0, ...utf8(f.mime), 0,
  ...natToBytesBE(f.size), 0,
  ...f.nonce, 0, ...utf8(f.cids.join(" ")),
  ...(f.ipfs && f.ipfs.length ? [0, ...utf8(f.ipfs.join(" "))] : []),
];

export const manifestWitness = (f) => witness(manifestCore(f));

export const ofManifest = (f) => ({
  tag: TAG_FILE,
  fields: [
    asciiBytes(f.room), asciiBytes(f.sender), natToBytesBE(f.seq),
    utf8(f.name), utf8(f.mime), natToBytesBE(f.size),
    f.nonce.slice(), utf8(f.cids.join(" ")),
    ...(f.ipfs && f.ipfs.length ? [utf8(f.ipfs.join(" "))] : []),
    asciiBytes(manifestWitness(f)),
  ],
});

/** Read a manifest back, refusing anything whose witness does not match.
 *  Both the 9-field (relay-only) and 10-field (IPFS) shapes are accepted. */
export function toManifest(e) {
  if (!e || !eqBytes(e.tag, TAG_FILE)) return null;
  if (e.fields.length !== 9 && e.fields.length !== 10) return null;
  const [r, s, q, n, mi, sz, nc, cs, ...rest] = e.fields;
  const ipfs = e.fields.length === 10 ? fromUtf8(rest[0]).split(" ").filter(Boolean) : [];
  const w = rest[rest.length - 1];
  const f = {
    room: asciiChars(r), sender: asciiChars(s),
    seq: Number(bytesBEToNat(q)),
    name: fromUtf8(n), mime: fromUtf8(mi),
    size: Number(bytesBEToNat(sz)),
    nonce: nc.slice(), cids: fromUtf8(cs).split(" ").filter(Boolean),
    ipfs,
  };
  if (f.cids.length !== f.ipfs.length && f.ipfs.length !== 0) return null;
  return manifestWitness(f) === asciiChars(w) ? f : null;
}

/** Each chunk as { witness, ipfs } — witness is what the signature covers,
 *  ipfs is where the bytes can be fetched. They are independent names. */
export const manifestChunks = (f) =>
  f.cids.map((witness, i) => ({ witness, ipfs: f.ipfs?.[i] ?? null }));

/** A manifest as one self-certifying room line. */
export const printManifest = (f) => envelopeEncode(ofManifest(f));

/** Read a room line as a manifest (null when it is some other line). */
export const parseManifest = (s) => toManifest(envelopeDecode(s));
