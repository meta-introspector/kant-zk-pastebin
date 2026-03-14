//! # IPFS Content Addressing
//!
//! Pure Rust IPFS integration for kant-pastebin. Computes content-addressed
//! CIDs and writes blocks directly to the go-ipfs/kubo flatfs block store
//! on the local filesystem — no daemon, no CLI, no HTTP API.
//!
//! ## How it works
//!
//! 1. Content is fed to [`rust_unixfs::file::adder::FileAdder`] which encodes
//!    it as UnixFS dag-pb blocks (the same format `ipfs add` uses).
//! 2. Each block is written to `~/.ipfs/blocks/` using go-ipfs flatfs layout:
//!    - Key = base32upper encoding of the block's multihash
//!    - Shard directory = next-to-last 2 characters of the key
//!    - File = `~/.ipfs/blocks/{shard}/{key}.data`
//! 3. The root CID (CIDv0, `Qm...`) is returned and stored in paste headers.
//! 4. `ipfs cat <CID>` works immediately — kubo reads the blocks we wrote.
//!
//! ## Backends
//!
//! Three [`ContentStore`] implementations are provided:
//! - [`RustStore`] — pure Rust via `rust-unixfs` (default, WASM-compatible)
//! - [`DaslCborStore`] — wraps content in a DASL/CBOR envelope before storing
//! - [`IpfsCliStore`] — shells out to `ipfs add` (fallback)
//!
//! ## DASL/CBOR Integration
//!
//! [`wrap_dasl_cbor`] creates a CBOR envelope containing the content, its IPFS
//! CID, DASL 0xDA51 Monster symmetry address, orbifold coordinates, and Bott
//! periodicity index. This envelope is itself content-addressable.

use sha2::{Sha256, Digest};
use serde::{Serialize, Deserialize};
use rust_unixfs::file::adder::FileAdder;
use ipld_core::cid::Cid;

/// Pluggable content addressing backend.
///
/// Implementations compute a content identifier for arbitrary byte data.
/// The returned string is a valid IPFS CID.
pub trait ContentStore: Send + Sync {
    /// Human-readable backend name (e.g. "rust-unixfs", "ipfs-cli").
    fn name(&self) -> &str;
    /// Add data and return its CID, or `None` on failure.
    fn add(&self, data: &[u8]) -> Option<String>;
}

// === IPFS block storage (go-ipfs/kubo flatfs compatible) ===

/// Resolve the IPFS repo path: `$IPFS_PATH` or `~/.ipfs`.
/// Returns `None` if the directory doesn't exist.
fn ipfs_repo() -> Option<String> {
    std::env::var("IPFS_PATH").ok().or_else(|| {
        dirs_next::home_dir().map(|h| format!("{}/.ipfs", h.display()))
    }).filter(|p| std::path::Path::new(p).exists())
}

/// Write a raw block to go-ipfs flatfs.
///
/// Block path: `{repo}/blocks/{shard}/{key}.data`
/// - `key` = base32upper(multihash)
/// - `shard` = next-to-last 2 characters of `key` (go-ipfs sharding scheme)
fn write_block(cid: &Cid, block: &[u8]) {
    let Some(repo) = ipfs_repo() else { return };
    let mh_bytes = cid.hash().to_bytes();
    let key = data_encoding::BASE32_NOPAD.encode(&mh_bytes);
    let shard = if key.len() >= 3 { &key[key.len()-3..key.len()-1] } else { "AA" };
    let dir = format!("{}/blocks/{}", repo, shard);
    std::fs::create_dir_all(&dir).ok();
    let path = format!("{}/{}.data", dir, key);
    if std::fs::write(&path, block).is_ok() {
        log::info!("📦 IPFS block: {}", path);
    }
}

/// Add content to IPFS via pure Rust. Encodes as UnixFS dag-pb blocks using
/// [`FileAdder`], writes each block to the local flatfs store, and returns
/// the root CID (CIDv0 `Qm...` string).
///
/// For files under 256KB (default chunk size), produces a single leaf block.
/// Larger files are chunked into a balanced Merkle DAG automatically.
pub fn ipfs_add_bytes(data: &[u8]) -> Option<String> {
    let mut adder = FileAdder::default();
    let mut root_cid = None;

    let (blocks, consumed) = adder.push(data);
    for (cid, block) in blocks {
        write_block(&cid, &block);
        root_cid = Some(cid);
    }
    if consumed < data.len() {
        let (blocks, _) = adder.push(&data[consumed..]);
        for (cid, block) in blocks {
            write_block(&cid, &block);
            root_cid = Some(cid);
        }
    }
    for (cid, block) in adder.finish() {
        write_block(&cid, &block);
        root_cid = Some(cid);
    }

    root_cid.map(|c| c.to_string())
}

/// Convenience wrapper: add UTF-8 content to IPFS.
pub fn ipfs_add(content: &str) -> Option<String> {
    ipfs_add_bytes(content.as_bytes())
}

/// Read a raw block from go-ipfs flatfs by CID string.
/// Parses the CID, derives the flatfs path, and reads the block bytes.
pub fn ipfs_cat(cid_str: &str) -> Option<Vec<u8>> {
    let repo = ipfs_repo()?;
    let cid: Cid = cid_str.parse().ok()?;
    let mh_bytes = cid.hash().to_bytes();
    let key = data_encoding::BASE32_NOPAD.encode(&mh_bytes);
    let shard = if key.len() >= 3 { &key[key.len()-3..key.len()-1] } else { "AA" };
    let path = format!("{}/blocks/{}/{}.data", repo, shard, key);
    std::fs::read(&path).ok()
}

/// Quick local content hash (not IPFS-compatible, for dedup only).
pub fn local_cid(data: &[u8]) -> String {
    let hash = Sha256::digest(data);
    format!("bafk{}", hex::encode(&hash[..16]))
}

/// Convert any CID string to CIDv1 base32lower for display.
pub fn cid_to_v1(cid_str: &str) -> String {
    if let Ok(cid) = cid_str.parse::<Cid>() {
        let v1 = Cid::new_v1(cid.codec(), cid.hash().to_owned());
        let bytes = v1.to_bytes();
        format!("b{}", data_encoding::BASE32_NOPAD.encode(&bytes).to_lowercase())
    } else {
        cid_str.to_string()
    }
}

// === DASL/CBOR envelope ===

/// CBOR-serializable envelope wrapping content with DASL Monster symmetry metadata.
///
/// Fields:
/// - `prefix`: always `0xDA51`
/// - `dasl_type`: DASL CID type (3 = nested CID)
/// - `orbifold`: coordinates in Z/71 × Z/59 × Z/47 (Monster prime lattice)
/// - `bott`: Bott periodicity index (0–7)
/// - `data`: raw content bytes
/// - `cid`: IPFS CID string
/// - `dasl`: 64-bit DASL address as hex string
#[derive(Serialize, Deserialize)]
pub struct DaslObject {
    pub prefix: u64,
    pub dasl_type: u8,
    pub orbifold: (u64, u64, u64),
    pub bott: u8,
    #[serde(with = "serde_bytes")]
    pub data: Vec<u8>,
    pub cid: String,
    pub dasl: String,
}

/// Wrap content in a DASL/CBOR envelope. Returns `(cbor_bytes, ipfs_cid)`.
///
/// The envelope includes the content's IPFS CID, DASL address, orbifold
/// coordinates, and Bott index — bridging IPFS content addressing with
/// Monster group symmetry.
pub fn wrap_dasl_cbor(data: &[u8]) -> (Vec<u8>, String) {
    let cid = ipfs_add_bytes(data).unwrap_or_default();
    let dasl_addr = crate::dasl::dasl_cid(data);
    let (l, m, n) = crate::dasl::orbifold_coords(data);
    let hash = Sha256::digest(data);
    let bott = hash[2] % 8;

    let obj = DaslObject {
        prefix: 0xDA51,
        dasl_type: 3,
        orbifold: (l, m, n),
        bott,
        data: data.to_vec(),
        cid: cid.clone(),
        dasl: dasl_addr,
    };

    let mut cbor = Vec::new();
    ciborium::into_writer(&obj, &mut cbor).unwrap_or_default();
    (cbor, cid)
}

// === Backends ===

/// Pure Rust content store using `rust-unixfs` FileAdder + flatfs writes.
/// Default backend. No external dependencies at runtime.
pub struct RustStore;
impl ContentStore for RustStore {
    fn name(&self) -> &str { "rust-unixfs" }
    fn add(&self, data: &[u8]) -> Option<String> { ipfs_add_bytes(data) }
}

/// DASL/CBOR content store. Wraps content in a Monster symmetry envelope
/// before adding to IPFS. The returned CID addresses the envelope, not
/// the raw content.
pub struct DaslCborStore;
impl ContentStore for DaslCborStore {
    fn name(&self) -> &str { "dasl-cbor" }
    fn add(&self, data: &[u8]) -> Option<String> {
        let (cbor, _) = wrap_dasl_cbor(data);
        ipfs_add_bytes(&cbor)
    }
}

/// CLI fallback: shells out to `ipfs add`. Requires kubo/go-ipfs on PATH.
pub struct IpfsCliStore;
impl ContentStore for IpfsCliStore {
    fn name(&self) -> &str { "ipfs-cli" }
    fn add(&self, data: &[u8]) -> Option<String> {
        use std::process::Command;
        use std::io::Write;
        let mut child = Command::new("ipfs")
            .args(["add", "-Q", "--pin=false"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn().ok()?;
        if let Some(mut stdin) = child.stdin.take() { stdin.write_all(data).ok()?; }
        let out = child.wait_with_output().ok()?;
        let cid = String::from_utf8(out.stdout).ok()?.trim().to_string();
        if cid.is_empty() { None } else { Some(cid) }
    }
}
