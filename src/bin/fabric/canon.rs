//! Canonical bytes and content addresses.
//!
//! A fabric event is a JSON object with no insignificant whitespace and keys in
//! sorted order (serde_json's default map is a `BTreeMap`, so `to_vec` gives
//! exactly one byte string per value). Its address is a CIDv1 with the `raw`
//! codec over SHA-256 of those bytes:
//!
//!     0x01 0x55 0x12 0x20 <32-byte sha256>
//!
//! That is the same address `ipfs block put --cid-codec=raw` produces, which is
//! what makes the Rust side and the WebAssembly/IPFS side comparable at all.
//! `tests` pins one vector computed externally with `ipfs block put`.

use sha2::{Digest, Sha256};

/// The multibase alphabet for base32-lower (RFC 4648, no padding).
const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";

/// Canonical bytes for a JSON value. Sorted keys, compact separators.
pub fn canonical_bytes(v: &serde_json::Value) -> Vec<u8> {
    serde_json::to_vec(v).expect("a serde_json::Value always serialises")
}

pub fn sha256(bytes: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(bytes);
    let out = h.finalize();
    let mut a = [0u8; 32];
    a.copy_from_slice(&out);
    a
}

fn base32_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity((bytes.len() * 8 + 4) / 5);
    let mut buf: u32 = 0;
    let mut bits = 0u32;
    for &b in bytes {
        buf = (buf << 8) | b as u32;
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(ALPHABET[((buf >> bits) & 0x1f) as usize] as char);
        }
    }
    if bits > 0 {
        out.push(ALPHABET[((buf << (5 - bits)) & 0x1f) as usize] as char);
    }
    out
}

fn base32_decode(s: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(s.len() * 5 / 8);
    let mut buf: u32 = 0;
    let mut bits = 0u32;
    for c in s.bytes() {
        let v = ALPHABET.iter().position(|&a| a == c)? as u32;
        buf = (buf << 5) | v;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xff) as u8);
        }
    }
    Some(out)
}

/// CIDv1/raw over `bytes`, as a `b...` base32 string.
pub fn raw_cid(bytes: &[u8]) -> String {
    let digest = sha256(bytes);
    let mut framed = Vec::with_capacity(36);
    framed.extend_from_slice(&[0x01, 0x55, 0x12, 0x20]);
    framed.extend_from_slice(&digest);
    format!("b{}", base32_encode(&framed))
}

/// The 32-byte digest a CIDv1/raw address names, or `None` if this is not one.
pub fn cid_digest(cid: &str) -> Option<[u8; 32]> {
    let body = cid.strip_prefix('b')?;
    let bytes = base32_decode(body)?;
    if bytes.len() != 36 || bytes[..4] != [0x01, 0x55, 0x12, 0x20] {
        return None;
    }
    let mut d = [0u8; 32];
    d.copy_from_slice(&bytes[4..]);
    Some(d)
}

/// True exactly when `bytes` hash to the address `cid` names.
pub fn verifies(cid: &str, bytes: &[u8]) -> bool {
    match cid_digest(cid) {
        Some(d) => d == sha256(bytes),
        None => false,
    }
}

// --------------------------------------------------- the wasm-agreed digest
//
// `Kant.Bytes.digest` is four salted FNV-1a 64-bit rounds, each expanded to
// eight big-endian bytes. The Lean-extracted WebAssembly kernel exports it
// (`web/kant-wasm.mjs`'s `digest`), so this reimplementation is the second
// implementation of the same function: the wasm peer and the Rust daemon
// compute it over the same bytes fetched from IPFS and must agree. The
// vectors below were printed by the wasm kernel, not by this code.

const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn fnv1a_step(h: u64, b: u64) -> u64 {
    (h ^ b).wrapping_mul(FNV_PRIME)
}

pub fn kant_digest(bytes: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    for i in 0..4u64 {
        let mut h = fnv1a_step(FNV_OFFSET, i);
        for &b in bytes {
            h = fnv1a_step(h, b as u64);
        }
        let be = h.to_be_bytes();
        out[(i as usize) * 8..(i as usize) * 8 + 8].copy_from_slice(&be);
    }
    out
}

pub fn kant_digest_hex(bytes: &[u8]) -> String {
    hex::encode(kant_digest(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Computed outside this code: `printf 'agent-fabric probe\n' |
    /// ipfs block put --cid-codec=raw --mhtype=sha2-256`.
    const PROBE_CID: &str = "bafkreidjpypm7olfcrcy2qd6r5avyqr5hfrmp6ijkmg7ajhgjvxpicgs24";

    #[test]
    fn cid_matches_ipfs() {
        assert_eq!(raw_cid(b"agent-fabric probe\n"), PROBE_CID);
    }

    #[test]
    fn cid_round_trips() {
        let d = cid_digest(PROBE_CID).expect("valid cid");
        assert_eq!(d, sha256(b"agent-fabric probe\n"));
        assert!(verifies(PROBE_CID, b"agent-fabric probe\n"));
        assert!(!verifies(PROBE_CID, b"agent-fabric probe"));
    }

    #[test]
    fn rejects_other_multihashes_and_codecs() {
        // A CIDv0 is base58 and has no `b` prefix; a dag-pb CIDv1 is not raw.
        assert_eq!(cid_digest("QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"), None);
        assert_eq!(
            cid_digest("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"),
            None
        );
        assert_eq!(cid_digest("b"), None);
        assert_eq!(cid_digest(""), None);
    }

    #[test]
    fn canonical_bytes_are_key_sorted_and_stable() {
        let a: serde_json::Value =
            serde_json::from_str(r#"{"z":1,"a":{"y":2,"b":[3,4]},"m":"x"}"#).unwrap();
        let b: serde_json::Value =
            serde_json::from_str(r#"{"m":"x","a":{"b":[3,4],"y":2},"z":1}"#).unwrap();
        assert_eq!(canonical_bytes(&a), canonical_bytes(&b));
        assert_eq!(
            std::str::from_utf8(&canonical_bytes(&a)).unwrap(),
            r#"{"a":{"b":[3,4],"y":2},"m":"x","z":1}"#
        );
    }

    /// Printed by the wasm kernel: `k.digest(new TextEncoder().encode("hello"))`.
    #[test]
    fn kant_digest_matches_the_wasm_kernel() {
        assert_eq!(
            kant_digest_hex(b"hello"),
            "3b6dba0d69908e25e65788c860f9c52ca465011c2cfbddaba2898e4e474fc1ba"
        );
        assert_eq!(
            kant_digest_hex(b"agent-fabric probe\n"),
            "85eb3003fc1fcbfe20616e6924d7a537fb32ba935fce02608d950b5c826303b9"
        );
    }

    #[test]
    fn kant_digest_is_not_the_ipfs_digest() {
        // Different functions, different purposes: one is the wasm/Lean content
        // digest, the other is the multihash inside a CIDv1.
        assert_ne!(kant_digest(b"hello").to_vec(), sha256(b"hello").to_vec());
    }

    #[test]
    fn base32_round_trip() {
        for n in 0..40usize {
            let bytes: Vec<u8> = (0..n).map(|i| (i * 7 + 3) as u8).collect();
            assert_eq!(base32_decode(&base32_encode(&bytes)).unwrap(), bytes);
        }
    }
}
