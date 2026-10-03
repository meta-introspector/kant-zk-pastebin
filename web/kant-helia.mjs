// kant-helia.mjs — in-browser Helia (js-ipfs) node manager.
//
// Vendored ESM bundle at ./vendor/helia.mjs (built via flake.nix heliaVendor:
// npm install helia + esbuild bundling).  Consumed by kant-ipfs.mjs:
//
//   - ipfsAdd  → compute the CID client-side, put bytes under that exactly CID
//               into Helia's local blockstore + recursively pin, then verify the
//               returned CID matches the WASM ground truth.  Falls back to kubo.
//   - ipfsCat  → serve the artifact from the local blockstore through the
//               Content API; falls back to the gateway.
//
// The CID contract is unchanged: `cidOf` / `unixfsCidOf` (Rust core, byte-
// identical to this module's UnixFS implementation) compute exactly the same
// CIDv1/raw/sha2-256 as `kubo add --cid-version=1 --raw-leaves` at any size, so
// pre-computed CIDs always match.  No `content.add()` round-trip — we put and
// pin by construction, which eliminates codec/chunking drift entirely.

import { createHelia, CID } from "./vendor/helia.mjs";

/** Minimal base32 decoder for the cidIdentity bytes used below. */
const MULTIBASE_B = 0x62;

/** The Helia node singleton — null when the vendor bundle failed to load. */
let _node = null;
let _nodeTried = false;

/** Start a self-contained Helia node (WebSocket + WebTransport transports). */
async function initNode() {
  if (_nodeTried) return _node;
  _nodeTried = true;
  try {
    _node = await createHelia();
  } catch {
    _node = null;
  }
  return _node;
}

/** The Helia node, or null when the bundle could not start the node. */
export async function heliaNode() {
  return await initNode();
}

/** True when a Helia node is available (no network call, just a process check). */
export async function heliaAvailable() {
  try {
    const node = await initNode();
    return node !== null;
  } catch {
    return false;
  }
}

/** Concatenate a list of Uint8Arrays into one (browser-safe). */
function u8cat(parts) {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

/**
 * Helia-backed cat: retrieve bytes by CID through the Content API.
 * Returns null when Helia is unavailable or the CID is not local.
 * (Callers fall back to the gateway.)
 */
export async function heliaCat(cid) {
  try {
    const node = await initNode();
    if (!node) return null;
    const it = await node.content.cat(CID.parse(cid));
    const parts = [];
    for await (const chunk of it) parts.push(chunk);
    return parts.length ? u8cat(parts) : null;
  } catch {
    return null;
  }
}

/**
 * Helia-backed add: pin bytes under the pre-computed CID so the local node
 * serves exactly the block the rest of the stack announced.  No
 * `content.add()` is ever called — the CID comes from `cidOf`/UnixFS (WASM),
 * and we `blockstore.put` the block under that CID then `pins.add` it.
 *
 * Returns the CID string (matching `cidOf`), or null when Helia is unavailable.
 */
export async function heliaAdd(bytes, name = "artifact") {
  try {
    const node = await initNode();
    if (!node) return null;

    // CID + chunking plan, computed client-side and shared with the WASM core.
    const { unixfsPlanOf, unixfsRoot } = await import("./kant-ipfs.mjs");
    const plan = await unixfsPlanOf(bytes);

    // Pin every leaf block under its pre-computed raw-leaf CID.
    for (const { cid: leafCid, size, offset } of plan.leaves) {
      const block = bytes.subarray(offset, offset + size);
      await node.blockstore.put(CID.parse(leafCid), block);
    }

    // For multi-chunk files, also store the dag-pb root under its pre-computed
    // CID so `content.cat(root)` reassembles the file.
    if (plan.chunked) {
      const links = plan.leaves.map((l) => ({
        hash: CID.parse(l.cid).toBytes(),  // full cidIdentity (version|codec|digest)
        tsize: l.size,
      }));
      const rootBytes = unixfsRoot(links, bytes.length, plan.leaves.map((l) => l.size));
      await node.blockstore.put(CID.parse(plan.root), rootBytes);
    }

    // Recursively pin the root (and its links) so the DAG survives GC.  For
    // single-chunk artifacts this pins the leaf directly.
    await node.pins.add(CID.parse(plan.root), { recursive: true });
    return plan.root;
  } catch {
    return null;
  }
}
