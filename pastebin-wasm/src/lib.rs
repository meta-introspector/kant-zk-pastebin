//! pastebin-wasm — the kant pastebin core compiled to WebAssembly.
//!
//! The same Rust that backs the actix server's artifact addressing
//! (`src/ipfs.rs`), exposed to the browser p2p chat client:
//!
//!   * `cid_of_bytes`   — CIDv1 / raw (0x55) / sha2-256, base32 multibase,
//!     byte-identical to `web/kant-ipfs.mjs` `cidOf()` and to
//!     `kubo add --cid-version=1 --raw-leaves` for ≤ one-chunk inputs;
//!   * `cid_identity`   — the 36 identity bytes behind a CID string
//!     (version + codec + multihash), for cross-checking peers;
//!   * `chunk_plan`     — the ≤ 256 KiB chunking discipline: artifact size →
//!     the list of block sizes a peer must produce/expect;
//!   * `kzcid_record` / `parse_kzcid_record` — encode/decode the kzcid
//!     room-record JSON, with the credential-field guard the fleet rooms
//!     require (docs/SECRET-HAZARDS.md: rooms are public and append-only).
//!
//! Everything here is pure computation — no fetch, no storage, no clock —
//! so the browser does the network I/O and this module stays testable.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use wasm_bindgen::prelude::*;

/// One kubo chunk; at or under this the client CID equals the node CID.
pub const MAX_ARTIFACT_BYTES: usize = 262_144;

const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";

/// RFC4648 base32, lowercase, no padding — the multibase identity for `b`.
pub fn base32_no_pad(bytes: &[u8]) -> String {
    let mut bits: u32 = 0;
    let mut value: u32 = 0;
    let mut out = String::new();
    for &b in bytes {
        value = (value << 8) | b as u32;
        bits += 8;
        while bits >= 5 {
            out.push(ALPHABET[((value >> (bits - 5)) & 31) as usize] as char);
            bits -= 5;
        }
    }
    if bits > 0 {
        out.push(ALPHABET[((value << (5 - bits)) & 31) as usize] as char);
    }
    out
}

/// Inverse of [`base32_no_pad`]; `None` on any character outside the alphabet.
pub fn base32_decode(s: &str) -> Option<Vec<u8>> {
    let mut bits: u32 = 0;
    let mut value: u32 = 0;
    let mut out = Vec::new();
    for ch in s.chars() {
        let idx = ALPHABET.iter().position(|&a| a as char == ch)?;
        value = (value << 5) | idx as u32;
        bits += 5;
        if bits >= 8 {
            out.push((value >> (bits - 8)) as u8);
            bits -= 8;
        }
    }
    Some(out)
}

/// CIDv1, codec `raw` (0x55), multihash sha2-256 (0x12, length 0x20):
/// `<0x01 0x55> <0x12 0x20> <32-byte digest>`, multibase base32, `b` prefix.
pub fn cid_of_bytes(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut cid_bytes = Vec::with_capacity(4 + digest.len());
    cid_bytes.push(0x01); // CIDv1
    cid_bytes.push(0x55); // raw codec
    cid_bytes.push(0x12); // sha2-256
    cid_bytes.push(0x20); // 32-byte digest length
    cid_bytes.extend_from_slice(&digest);
    format!("b{}", base32_no_pad(&cid_bytes))
}

/// The CID string as its 36 identity bytes (2 header + 2 multihash + 32
/// digest), `Err` with a reason when the string is not a CIDv1/raw/sha2-256
/// base32 CID.
pub fn cid_identity(cid: &str) -> Result<Vec<u8>, String> {
    let body = cid.strip_prefix('b').ok_or("not a base32 multibase CID")?;
    let bytes = base32_decode(body).ok_or("bad base32 character")?;
    if bytes.len() != 36 {
        return Err(format!("expected 36 identity bytes, got {}", bytes.len()));
    }
    if bytes[0] != 0x01 {
        return Err(format!("not CIDv1 (version byte 0x{:02x})", bytes[0]));
    }
    if bytes[1] != 0x55 {
        return Err(format!("not raw codec (0x{:02x})", bytes[1]));
    }
    if bytes[2] != 0x12 || bytes[3] != 0x20 {
        return Err("not sha2-256 multihash".into());
    }
    Ok(bytes)
}

/// The chunking discipline: `Ok(chunk_sizes)` when the artifact is within
/// the single-block guarantee (one chunk = the whole artifact), `Err` with
/// the overage when it is not.
pub fn chunk_plan(size: usize) -> Result<Vec<usize>, String> {
    if size == 0 {
        return Err("empty artifact".into());
    }
    if size > MAX_ARTIFACT_BYTES {
        return Err(format!(
            "artifact {size}B > {MAX_ARTIFACT_BYTES}B — chunk it or use kubo directly"
        ));
    }
    Ok(vec![size])
}

// ── kzcid room records ──────────────────────────────────────────────────

/// The kzcid record the room carries (`web/kant-p2p.mjs` emits the same
/// shape).  No credential-shaped fields are ever serialized: rooms are
/// public and append-only.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KzcidRecord {
    pub tag: String,
    pub peer: String,
    pub name: String,
    pub cid: String,
    pub size: usize,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub note: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pinned: Option<bool>,
    /// base64 of the artifact bytes when a peer embeds a fallback copy.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub b64: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ts: Option<u64>,
}

const CREDENTIAL_KEY: &[&str] = &[
    "secret", "token", "password", "passwd", "api_key", "apikey", "authurl",
    "authsecret", "cookie", "totp", "credential", "authorization",
];

/// Refuse credential-shaped fields before anything reaches a public room.
pub fn assert_no_credential_fields(record: &KzcidRecord) -> Result<(), String> {
    let suspicious = [record.name.to_lowercase(), record.note.to_lowercase()]
        .iter()
        .any(|field| CREDENTIAL_KEY.iter().any(|k| field.contains(k)));
    if suspicious {
        return Err("refusing credential-shaped field in name/note".into());
    }
    Ok(())
}

/// Encode a kzcid record to the one-line JSON the room carries.
pub fn kzcid_record_json(record: &KzcidRecord) -> Result<String, String> {
    assert_no_credential_fields(record)?;
    serde_json::to_string(record).map_err(|e| e.to_string())
}

/// Decode a room line into a kzcid record, validating the CID form.
pub fn parse_kzcid_record(line: &str) -> Result<KzcidRecord, String> {
    let record: KzcidRecord =
        serde_json::from_str(line).map_err(|e| format!("not a kzcid record: {e}"))?;
    if record.tag != "kzcid" {
        return Err(format!("not a kzcid record (tag {:?})", record.tag));
    }
    cid_identity(&record.cid)?;
    Ok(record)
}

// ── wasm-bindgen surface ────────────────────────────────────────────────

#[wasm_bindgen]
pub fn wasm_cid_of_bytes(bytes: &[u8]) -> String {
    cid_of_bytes(bytes)
}

#[wasm_bindgen]
pub fn wasm_cid_identity(cid: &str) -> Result<Vec<u8>, JsValue> {
    cid_identity(cid).map_err(|e| JsValue::from_str(&e))
}

#[wasm_bindgen]
pub fn wasm_chunk_plan(size: usize) -> Result<Vec<u32>, JsValue> {
    chunk_plan(size)
        .map(|v| v.iter().map(|&n| n as u32).collect())
        .map_err(|e| JsValue::from_str(&e))
}

#[wasm_bindgen]
pub fn wasm_kzcid_record(
    peer: &str,
    name: &str,
    cid: &str,
    size: usize,
    note: &str,
    pinned: bool,
    ts: f64,
) -> Result<String, JsValue> {
    let record = KzcidRecord {
        tag: "kzcid".into(),
        peer: peer.into(),
        name: name.into(),
        cid: cid.into(),
        size,
        note: note.into(),
        pinned: if pinned { Some(true) } else { None },
        b64: None,
        ts: Some(ts as u64),
    };
    kzcid_record_json(&record).map_err(|e| JsValue::from_str(&e))
}

#[wasm_bindgen]
pub fn wasm_parse_kzcid_record(line: &str) -> Result<JsValue, JsValue> {
    let record = parse_kzcid_record(line).map_err(|e| JsValue::from_str(&e))?;
    serde_wasm_json(&record)
}

// serde_json::value::Serializer output is already `JsValue`-shaped JSON
// text; parse and hand it back as an object rather than a string.
fn serde_wasm_json(record: &KzcidRecord) -> Result<JsValue, JsValue> {
    let text = serde_json::to_string(record).map_err(|e| JsValue::from_str(&e.to_string()))?;
    Ok(JsValue::from_str(&text))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cid_matches_known_shape() {
        // Structure check: version, codec, multihash header, length, prefix.
        let cid = cid_of_bytes(b"hello world");
        assert!(cid.starts_with('b'));
        assert_eq!(cid.len(), 1 + 58); // multibase char + ceil(288/5) base32 chars
        let identity = cid_identity(&cid).unwrap();
        assert_eq!(identity[0], 0x01);
        assert_eq!(identity[1], 0x55);
        assert_eq!(identity[2], 0x12);
        assert_eq!(identity[3], 0x20);
        assert_eq!(identity.len(), 36);
    }

    #[test]
    fn base32_round_trip() {
        for input in [&b""[..], b"a", b"hello world", &[0u8; 36][..]] {
            let encoded = base32_no_pad(input);
            assert_eq!(base32_decode(&encoded).unwrap(), input.to_vec());
        }
    }

    #[test]
    fn chunk_plan_bounds() {
        assert!(chunk_plan(1).is_ok());
        assert!(chunk_plan(MAX_ARTIFACT_BYTES).is_ok());
        assert!(chunk_plan(MAX_ARTIFACT_BYTES + 1).is_err());
        assert!(chunk_plan(0).is_err());
    }

    #[test]
    fn kzcid_round_trip_and_guard() {
        let cid = cid_of_bytes(b"x");
        let record = KzcidRecord {
            tag: "kzcid".into(),
            peer: "peer-a".into(),
            name: "notes.txt".into(),
            cid: cid.clone(),
            size: 1,
            note: String::new(),
            pinned: None,
            b64: None,
            ts: Some(1_700_000_000_000),
        };
        let line = kzcid_record_json(&record).unwrap();
        let back = parse_kzcid_record(&line).unwrap();
        assert_eq!(back.cid, cid);

        let mut bad = record.clone();
        bad.note = "my api_key is inside".into();
        assert!(kzcid_record_json(&bad).is_err());

        let mut wrong_cid = record;
        wrong_cid.cid = "notacid".into();
        assert!(parse_kzcid_record(
            &serde_json::to_string(&wrong_cid).unwrap()
        )
        .is_err());
    }
}
