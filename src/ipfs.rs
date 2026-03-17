//! # IPFS Content Addressing
//!
//! Pure Rust IPFS integration for kant-pastebin. Computes content-addressed
//! CIDs and writes blocks directly to the go-ipfs/kubo flatfs block store
//! on the local filesystem when a Kubo repo is present.
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
//! 4. The service can proxy that CID via `/ipfs/{cid}`. A local `ipfs cat <CID>`
//!    only works from a machine that is pointing at the same repo we wrote.
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

use ipld_core::cid::Cid;
use rust_unixfs::file::adder::FileAdder;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

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
    std::env::var("IPFS_PATH")
        .ok()
        .or_else(|| dirs_next::home_dir().map(|h| format!("{}/.ipfs", h.display())))
        .filter(|p| std::path::Path::new(p).exists())
}

/// Write a raw block to go-ipfs flatfs.
///
/// Block path: `{repo}/blocks/{shard}/{key}.data`
/// - `key` = base32upper(multihash)
/// - `shard` = next-to-last 2 characters of `key` (go-ipfs sharding scheme)
fn write_block(cid: &Cid, block: &[u8]) -> bool {
    let Some(repo) = ipfs_repo() else {
        return false;
    };
    let mh_bytes = cid.hash().to_bytes();
    let key = data_encoding::BASE32_NOPAD.encode(&mh_bytes);
    let shard = if key.len() >= 3 {
        &key[key.len() - 3..key.len() - 1]
    } else {
        "AA"
    };
    let dir = format!("{}/blocks/{}", repo, shard);
    if std::fs::create_dir_all(&dir).is_err() {
        return false;
    }
    let path = format!("{}/{}.data", dir, key);
    if std::fs::write(&path, block).is_ok() {
        log::info!("📦 IPFS block: {}", path);
        true
    } else {
        false
    }
}

fn store_blocks<I, B>(blocks: I, root_cid: &mut Option<Cid>) -> bool
where
    I: IntoIterator<Item = (Cid, B)>,
    B: AsRef<[u8]>,
{
    for (cid, block) in blocks {
        if !write_block(&cid, block.as_ref()) {
            return false;
        }
        *root_cid = Some(cid);
    }
    true
}

/// Add content to IPFS via pure Rust. Encodes as UnixFS dag-pb blocks using
/// [`FileAdder`], writes each block to the local flatfs store, and returns
/// the root CID (CIDv0 `Qm...` string).
///
/// For files under 256KB (default chunk size), produces a single leaf block.
/// Larger files are chunked into a balanced Merkle DAG automatically.
pub fn ipfs_add_bytes(data: &[u8]) -> Option<String> {
    ipfs_repo()?;

    let mut adder = FileAdder::default();
    let mut root_cid = None;

    let (blocks, consumed) = adder.push(data);
    if !store_blocks(blocks, &mut root_cid) {
        return None;
    }
    if consumed < data.len() {
        let (blocks, _) = adder.push(&data[consumed..]);
        if !store_blocks(blocks, &mut root_cid) {
            return None;
        }
    }
    if !store_blocks(adder.finish(), &mut root_cid) {
        return None;
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
    let shard = if key.len() >= 3 {
        &key[key.len() - 3..key.len() - 1]
    } else {
        "AA"
    };
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
        format!(
            "b{}",
            data_encoding::BASE32_NOPAD.encode(&bytes).to_lowercase()
        )
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
    fn name(&self) -> &str {
        "rust-unixfs"
    }
    fn add(&self, data: &[u8]) -> Option<String> {
        ipfs_add_bytes(data)
    }
}

/// DASL/CBOR content store. Wraps content in a Monster symmetry envelope
/// before adding to IPFS. The returned CID addresses the envelope, not
/// the raw content.
pub struct DaslCborStore;
impl ContentStore for DaslCborStore {
    fn name(&self) -> &str {
        "dasl-cbor"
    }
    fn add(&self, data: &[u8]) -> Option<String> {
        let (cbor, _) = wrap_dasl_cbor(data);
        ipfs_add_bytes(&cbor)
    }
}

/// CLI fallback: shells out to `ipfs add`. Requires kubo/go-ipfs on PATH.
pub struct IpfsCliStore;
impl ContentStore for IpfsCliStore {
    fn name(&self) -> &str {
        "ipfs-cli"
    }
    fn add(&self, data: &[u8]) -> Option<String> {
        use std::io::Write;
        use std::process::Command;
        let mut child = Command::new("ipfs")
            .args(["add", "-Q", "--pin=false"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn()
            .ok()?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(data).ok()?;
        }
        let out = child.wait_with_output().ok()?;
        let cid = String::from_utf8(out.stdout).ok()?.trim().to_string();
        if cid.is_empty() {
            None
        } else {
            Some(cid)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, OnceLock};

    struct EnvVarGuard {
        name: &'static str,
        original: Option<String>,
    }

    impl EnvVarGuard {
        fn set(name: &'static str, value: Option<&str>) -> Self {
            let original = std::env::var(name).ok();
            match value {
                Some(value) => std::env::set_var(name, value),
                None => std::env::remove_var(name),
            }
            Self { name, original }
        }
    }

    impl Drop for EnvVarGuard {
        fn drop(&mut self) {
            match &self.original {
                Some(value) => std::env::set_var(self.name, value),
                None => std::env::remove_var(self.name),
            }
        }
    }

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    #[test]
    fn ipfs_add_bytes_returns_none_without_a_repo() {
        let _guard = env_lock().lock().unwrap();
        let missing_repo =
            std::env::temp_dir().join(format!("kant-pastebin-missing-ipfs-{}", std::process::id()));
        let _ipfs_path = EnvVarGuard::set("IPFS_PATH", Some(missing_repo.to_str().unwrap()));
        assert!(ipfs_add_bytes(b"hello world").is_none());
    }
}
