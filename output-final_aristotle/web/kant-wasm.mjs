// Loader for the Lean-extracted WebAssembly kernel.
//
// `dist/kant_kernel.wasm` is produced by `lake exe emitwasm dist`, whose
// encoder lives in `RequestProject/Wasm/Encode.lean`. Every exported function
// is an `i64 -> ... -> i64` and is proved in `RequestProject/Wasm/KernelSpec.lean`
// to compute the corresponding `Kant.*` definition.
//
//   import { loadKernel } from "./kant-wasm.mjs";
//   const k = await loadKernel();
//   k.mergeCids(a, b);        // BigInt in, BigInt out (unsigned)

const DEFAULT_URL = new URL("../dist/kant_kernel.wasm", import.meta.url);

/** Names exported by the module, in the order the code section holds them. */
export const KERNEL_EXPORTS = [
  "hex_digit", "cid_prefix", "cid_type", "cid_payload", "mk_cid", "merge_cids",
  "credits_for", "capacity_bytes", "social_chunks", "fits_social", "lsb_embed",
  "lsb_extract", "hex_hi", "hex_lo", "fnv_offset", "fnv1a_step", "u64_byte",
  "cantor_pair", "rotate71", "reflect59", "dual47",
];

const u64 = (x) => BigInt.asUintN(64, BigInt(x));

async function fetchBytes(url) {
  if (typeof fetch === "function" && !String(url).startsWith("file:")) {
    const res = await fetch(url);
    return new Uint8Array(await res.arrayBuffer());
  }
  const { readFile } = await import("node:fs/promises");
  return new Uint8Array(await readFile(url));
}

/**
 * Instantiate the kernel. Returns the raw exports plus camel-cased wrappers
 * that take and return unsigned `BigInt`s.
 */
export async function loadKernel(url = DEFAULT_URL) {
  const bytes = await fetchBytes(url);
  if (!WebAssembly.validate(bytes)) throw new Error("kant_kernel.wasm failed validation");
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const raw = instance.exports;
  for (const name of KERNEL_EXPORTS) {
    if (typeof raw[name] !== "function") throw new Error(`kernel is missing export ${name}`);
  }
  const call = (name) => (...args) => u64(raw[name](...args.map((a) => u64(a))));
  const kernel = {
    raw,
    bytes,
    hexDigit: call("hex_digit"),
    cidPrefix: call("cid_prefix"),
    cidType: call("cid_type"),
    cidPayload: call("cid_payload"),
    mkCid: call("mk_cid"),
    mergeCids: call("merge_cids"),
    creditsFor: call("credits_for"),
    capacityBytes: call("capacity_bytes"),
    socialChunks: call("social_chunks"),
    fitsSocial: (n) => call("fits_social")(n) === 1n,
    lsbEmbed: call("lsb_embed"),
    lsbExtract: call("lsb_extract"),
    hexHi: call("hex_hi"),
    hexLo: call("hex_lo"),
    fnvOffset: () => u64(raw.fnv_offset()),
    fnv1aStep: call("fnv1a_step"),
    u64Byte: call("u64_byte"),
    cantorPair: call("cantor_pair"),
    /** FNV-1a 64-bit hash of a byte array, one verified step at a time. */
    fnv1a: (bytes) => {
      let h = u64(raw.fnv_offset());
      for (const b of bytes) h = call("fnv1a_step")(h, BigInt(b));
      return h;
    },
    /**
     * 32-byte content digest: four salted FNV-1a rounds, big-endian expanded.
     * Mirrors `Kant.Bytes.digest`, computed only from proved kernel exports.
     */
    digest: (bytes) => {
      const out = [];
      for (let i = 0; i < 4; i++) {
        let h = call("fnv1a_step")(u64(raw.fnv_offset()), BigInt(i));
        for (const b of bytes) h = call("fnv1a_step")(h, BigInt(b));
        for (let k = 0; k < 8; k++) out.push(Number(call("u64_byte")(h, BigInt(k))));
      }
      return out;
    },
    /** Lowercase hex of a byte array, using the verified digit functions. */
    hexEncode: (bytes) =>
      Array.from(bytes, (b) =>
        String.fromCharCode(Number(call("hex_hi")(b))) +
        String.fromCharCode(Number(call("hex_lo")(b)))).join(""),
    rotate71: call("rotate71"),
    reflect59: call("reflect59"),
    dual47: call("dual47"),
  };
  /** The witness of a paste: hex of the content digest (`Kant.Bytes.witness`). */
  kernel.witness = (bytes) => kernel.hexEncode(kernel.digest(bytes));
  return kernel;
}
