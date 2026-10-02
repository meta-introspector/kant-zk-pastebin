// kant-file-ipfs.mjs — the chunk store for `kant-file.mjs`, backed by IPFS.
//
// kant-file.mjs stays pure: it cuts a file into chunks, encrypts each one
// with the room key, and names each ciphertext by its Kant witness
// (`cidOf`).  It never decides *where* a chunk lives — `decryptFile` just
// takes a `fetchChunk` callback.  This module supplies that callback over
// IPFS, so the same manifest that today resolves chunks against relay
// blocks can resolve them against a content-addressed store instead.
//
// What goes on IPFS is the *ciphertext*, never the plaintext.  The relay
// path keeps the property that "the relay never learns the name, the type,
// or a single plaintext byte"; pinning to IPFS preserves it, because the
// room key never leaves the peers.  The file's confidentiality now rests
// on the room secret rather than on the transport — see the note on
// IPFS_DURABILITY below before treating this as a substitute.
//
// One thing this module cannot do: derive an IPFS CID from a Kant witness.
// `cidOf` is `Kant.Bytes.digest` — four salted FNV-1a rounds — which is a
// 32-byte value but not SHA-256, so it is not a multihash and no CID can
// be computed from it.  IPFS CIDs therefore have to be carried explicitly
// alongside the witness list; see `ipfsCidsFor`.

import { cidOf } from "./kant-file.mjs";
import { ipfsAdd, ipfsCat, GATEWAY, KUBO_RPC } from "./kant-ipfs.mjs";

/** Pin one encrypted chunk; returns its CID, or null if the daemon refused. */
export async function putChunk(bytes, { name = "chunk.bin", rpcBase = KUBO_RPC } = {}) {
  return ipfsAdd(bytes, name, rpcBase);
}

/**
 * Pin every chunk of an encrypted file and return the CID list, in the
 * same order as `manifest.cids`.  A null entry means that chunk failed to
 * pin — callers must not treat a partial list as complete.
 */
export async function putChunks(chunks, opts = {}) {
  const out = [];
  for (let i = 0; i < chunks.length; i += 1) {
    const cid = await putChunk(chunks[i], { ...opts, name: `chunk-${i}.bin` });
    if (cid === null) return { cids: out, complete: false, failedAt: i };
    out.push(cid);
  }
  return { cids: out, complete: true, failedAt: -1 };
}

/**
 * Read one chunk back.  The Kant witness is checked by `decryptFile`
 * itself, so this only has to return the exact bytes the daemon holds.
 */
export async function getChunk(cid, { gwBase = GATEWAY, timeoutMs = 8000 } = {}) {
  return ipfsCat(cid, gwBase, timeoutMs);
}

/**
 * A `fetchChunk` for `decryptFile`.
 *
 * Note the argument is the Kant *witness*, not an IPFS CID: `decryptFile`
 * iterates `manifest.cids`, which are witnesses. Since no CID can be
 * derived from a witness, the caller must supply the witness -> IPFS
 * mapping (as pairs from `ipfsCidsFor`, or a Map). Throws if a chunk has
 * no location or the daemon cannot serve it, so a half-open file fails
 * loudly rather than silently decrypting to zeros.
 */
export const ipfsFetcher = (pairs, opts = {}) => {
  const lookup = (witness) => {
    if (pairs instanceof Map) return pairs.get(witness);
    if (Array.isArray(pairs)) return pairs.find((p) => p.witness === witness)?.ipfs;
    return undefined;
  };
  return async (witness) => {
    const cid = lookup(witness);
    if (cid === undefined) {
      throw new Error(`no ipfs location for chunk ${witness.slice(0, 12)}…`);
    }
    const bytes = await getChunk(cid, opts);
    if (bytes === null) throw new Error(`ipfs chunk ${cid} unavailable`);
    return bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes);
  };
};

/**
 * The mapping the manifest has to carry: witness in, IPFS location out.
 * Witness and CID are independent names for the same chunk — the witness
 * is what the signature covers, the CID is where to fetch the bytes.
 */
export const ipfsCidsFor = (witnessCids, ipfsCids) => {
  if (witnessCids.length !== ipfsCids.length) {
    throw new Error(
      `witness/ipfs length mismatch: ${witnessCids.length} vs ${ipfsCids.length}`,
    );
  }
  return witnessCids.map((witness, i) => ({ witness, ipfs: ipfsCids[i] }));
};

/** The witness -> IPFS CID lookup `ipfsFetcher` wants, from a CID list. */
export const ipfsMap = (witnessCids, ipfsCids) =>
  new Map(ipfsCidsFor(witnessCids, ipfsCids).map((p) => [p.witness, p.ipfs]));

/** Sanity check a fetched chunk against the witness that named it. */
export const verifyChunk = (witness, bytes) => cidOf(bytes) === witness;

// IPFS is public and permanent: a CID that is known can be fetched by
// anyone, forever, and content addressing means a takedown is not possible.
// Because we only ever pin ciphertext, that leaks the file's *size and
// chunk count*, never its contents — but it does mean the room secret is
// now the only thing standing between a pinned chunk and a reader.
export const IPFS_DURABILITY = "public-permanent-ciphertext-only";