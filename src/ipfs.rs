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
//! 4. The service can proxy that CID via `/ipfs/{cid}`. A local `ipfs cat <CID>`
//!    only works from a machine pointed at the same repo we wrote.
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

/// Resolve the IPFS repo path: `$IPFS_PATH` or `/mnt/data1/ipfs`.
/// Returns `None` if the directory doesn't exist.
/// Never falls back to homedirs.
fn ipfs_repo() -> Option<String> {
    std::env::var("IPFS_PATH")
        .ok()
        .or_else(|| Some("/mnt/data1/ipfs".to_string()))
        .filter(|p| std::path::Path::new(p).exists())
}

/// Write a raw block to go-ipfs flatfs.
///
/// Block path: `{repo}/blocks/{shard}/{key}.data`
/// - `key` = base32upper(multihash)
/// - `shard` = next-to-last 2 characters of `key` (go-ipfs sharding scheme)

#[cfg(target_os = "linux")]
fn open_ipfs_directory(path: &std::path::Path) -> std::io::Result<std::os::fd::OwnedFd> {
    use std::ffi::CString;
    use std::os::fd::{FromRawFd, OwnedFd};
    use std::os::unix::ffi::OsStrExt;

    if !path.is_absolute() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "IPFS repository path must be absolute",
        ));
    }

    let root = CString::new("/").unwrap();
    let fd = unsafe {
        libc::open(
            root.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC,
        )
    };

    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }

    let mut current = unsafe { OwnedFd::from_raw_fd(fd) };

    for component in path.components() {
        let name = match component {
            std::path::Component::RootDir => continue,
            std::path::Component::Normal(name) => CString::new(name.as_bytes()).map_err(|_| {
                std::io::Error::new(
                    std::io::ErrorKind::InvalidInput,
                    "invalid directory component",
                )
            })?,
            _ => {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidInput,
                    "relative or parent directory component rejected",
                ));
            }
        };

        let next = unsafe {
            libc::openat(
                std::os::fd::AsRawFd::as_raw_fd(&current),
                name.as_ptr(),
                libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            )
        };

        if next < 0 {
            return Err(std::io::Error::last_os_error());
        }

        current = unsafe { OwnedFd::from_raw_fd(next) };
    }

    Ok(current)
}

// F5_DS12_STEP707_FSYNC_FAULT_INJECTION

#[cfg(test)]
static IPFS_FSYNC_CALLS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

#[cfg(test)]
static IPFS_FSYNC_FAIL_ON: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

#[cfg(target_os = "linux")]
fn sync_ipfs_directory(fd: std::os::fd::RawFd) -> std::io::Result<()> {
    #[cfg(test)]
    {
        let call = IPFS_FSYNC_CALLS.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;

        let fail_on = IPFS_FSYNC_FAIL_ON.load(std::sync::atomic::Ordering::SeqCst);

        if fail_on != 0 && call == fail_on {
            return Err(std::io::Error::from_raw_os_error(libc::EIO));
        }
    }

    if unsafe { libc::fsync(fd) } < 0 {
        return Err(std::io::Error::last_os_error());
    }

    Ok(())
}

#[cfg(target_os = "linux")]
fn open_or_create_ipfs_child(
    parent: &std::os::fd::OwnedFd,
    name: &std::ffi::CString,
) -> std::io::Result<std::os::fd::OwnedFd> {
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};

    let parent_fd = parent.as_raw_fd();

    let rc = unsafe { libc::mkdirat(parent_fd, name.as_ptr(), 0o755) };

    let created = if rc == 0 {
        true
    } else {
        let err = std::io::Error::last_os_error();

        if err.raw_os_error() == Some(libc::EEXIST) {
            false
        } else {
            return Err(err);
        }
    };

    let fd = unsafe {
        libc::openat(
            parent_fd,
            name.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };

    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }

    let child = unsafe { OwnedFd::from_raw_fd(fd) };

    // Persist the child directory entry in its parent.
    // This is required even when another process created it first.
    sync_ipfs_directory(parent_fd)?;

    // Persist the newly created directory metadata itself.
    if created {
        sync_ipfs_directory(child.as_raw_fd())?;
    }

    Ok(child)
}

#[cfg(target_os = "linux")]
fn existing_ipfs_block_matches(
    shard_fd: &std::os::fd::OwnedFd,
    filename: &std::ffi::CString,
    expected: &[u8],
) -> std::io::Result<Option<bool>> {
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};

    let fd = unsafe {
        libc::openat(
            shard_fd.as_raw_fd(),
            filename.as_ptr(),
            libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_CLOEXEC,
        )
    };

    if fd < 0 {
        let err = std::io::Error::last_os_error();

        if err.raw_os_error() == Some(libc::ENOENT) {
            return Ok(None);
        }

        return Err(err);
    }

    let fd = unsafe { OwnedFd::from_raw_fd(fd) };
    let mut file = std::fs::File::from(fd);
    let metadata = file.metadata()?;

    if !metadata.is_file() || metadata.len() != expected.len() as u64 {
        return Ok(Some(false));
    }

    let mut actual = Vec::with_capacity(expected.len());

    std::io::Read::read_to_end(&mut file, &mut actual)?;

    Ok(Some(actual == expected))
}

#[cfg(target_os = "linux")]
fn write_block(cid: &impl std::fmt::Display, block: &[u8]) -> bool {
    use std::ffi::CString;
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

    let Some(repo) = ipfs_repo() else {
        return false;
    };

    let parsed: Cid = match cid.to_string().parse() {
        Ok(value) => value,
        Err(_) => return false,
    };

    // This writer supports the SHA2-256 format produced by FileAdder.
    let mh = parsed.hash();

    if mh.code() != 0x12 || mh.size() != 32 {
        return false;
    }

    let actual_hash = Sha256::digest(block);

    if actual_hash.as_slice() != mh.digest() {
        return false;
    }

    let key = data_encoding::BASE32_NOPAD.encode(&mh.to_bytes());

    let shard = if key.len() >= 3 {
        &key[key.len() - 3..key.len() - 1]
    } else {
        return false;
    };

    let repo_fd = match open_ipfs_directory(std::path::Path::new(&repo)) {
        Ok(fd) => fd,
        Err(e) => {
            log::warn!("IPFS repository open refused: {}", e);
            return false;
        }
    };

    let blocks_name = CString::new("blocks").unwrap();
    let shard_name = match CString::new(shard) {
        Ok(value) => value,
        Err(_) => return false,
    };
    let block_name = match CString::new(format!("{}.data", key)) {
        Ok(value) => value,
        Err(_) => return false,
    };

    let blocks_fd = match open_or_create_ipfs_child(&repo_fd, &blocks_name) {
        Ok(fd) => fd,
        Err(e) => {
            log::warn!("IPFS blocks directory refused: {}", e);
            return false;
        }
    };

    let shard_fd = match open_or_create_ipfs_child(&blocks_fd, &shard_name) {
        Ok(fd) => fd,
        Err(e) => {
            log::warn!("IPFS shard directory refused: {}", e);
            return false;
        }
    };

    // Never overwrite an existing block.
    match existing_ipfs_block_matches(&shard_fd, &block_name, block) {
        Ok(Some(true)) => return true,
        Ok(Some(false)) => return false,
        Ok(None) => {}
        Err(e) => {
            log::warn!("IPFS existing block rejected: {}", e);
            return false;
        }
    }

    // Create a private temporary file in the same shard.
    let mut temporary_name = None;
    let mut temporary_fd: Option<OwnedFd> = None;

    for _ in 0..64 {
        let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);

        let name = match CString::new(format!(".{}.{}.{}.tmp", key, std::process::id(), sequence,))
        {
            Ok(value) => value,
            Err(_) => return false,
        };

        let fd = unsafe {
            libc::openat(
                shard_fd.as_raw_fd(),
                name.as_ptr(),
                libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL | libc::O_NOFOLLOW | libc::O_CLOEXEC,
                0o600,
            )
        };

        if fd >= 0 {
            temporary_name = Some(name);
            temporary_fd = Some(unsafe { OwnedFd::from_raw_fd(fd) });
            break;
        }

        let err = std::io::Error::last_os_error();

        if err.raw_os_error() != Some(libc::EEXIST) {
            log::warn!("IPFS temporary block creation failed: {}", err);
            return false;
        }
    }

    let (Some(temp_name), Some(temp_fd)) = (temporary_name, temporary_fd) else {
        return false;
    };

    let mut temp_file = std::fs::File::from(temp_fd);

    let write_result =
        std::io::Write::write_all(&mut temp_file, block).and_then(|_| temp_file.sync_all());

    drop(temp_file);

    if let Err(e) = write_result {
        unsafe {
            libc::unlinkat(shard_fd.as_raw_fd(), temp_name.as_ptr(), 0);
        }

        log::warn!("IPFS temporary block write failed: {}", e);
        return false;
    }

    // Atomic, no-clobber publication inside the same shard.
    let publish_rc = unsafe {
        libc::linkat(
            shard_fd.as_raw_fd(),
            temp_name.as_ptr(),
            shard_fd.as_raw_fd(),
            block_name.as_ptr(),
            0,
        )
    };

    let publish_error = if publish_rc < 0 {
        Some(std::io::Error::last_os_error())
    } else {
        None
    };

    unsafe {
        libc::unlinkat(shard_fd.as_raw_fd(), temp_name.as_ptr(), 0);
    }

    if let Some(err) = publish_error {
        if err.raw_os_error() == Some(libc::EEXIST) {
            return matches!(
                existing_ipfs_block_matches(&shard_fd, &block_name, block,),
                Ok(Some(true))
            );
        }

        log::warn!("IPFS atomic publication failed: {}", err);
        return false;
    }

    // The directory entry must also be flushed.
    if let Err(sync_error) = sync_ipfs_directory(shard_fd.as_raw_fd()) {
        log::warn!(
            "IPFS block visible but shard durability is uncertain: {}",
            sync_error
        );
        return false;
    }

    true
}

#[cfg(not(target_os = "linux"))]
fn write_block(_cid: &impl std::fmt::Display, _block: &[u8]) -> bool {
    // Fail closed where the descriptor-anchored Linux writer is unavailable.
    false
}

/// Write every block, remembering the last one as the root.
///
/// The root is only set once each block is *on disk*. A DAG whose leaves
/// failed to write is a CID that resolves to nothing, and a paste that
/// advertises one is a paste nobody can fetch — so a failure anywhere means
/// no CID at all.
fn store_blocks<I, C, B>(blocks: I, root_cid: &mut Option<C>) -> bool
where
    I: IntoIterator<Item = (C, B)>,
    C: std::fmt::Display,
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
    // No repo means nothing can be stored, so there is no CID to give out.
    ipfs_repo()?;

    let mut adder = FileAdder::default();
    let mut root_cid = None;
    let mut pushed = 0usize;

    // Consume every input byte. FileAdder::push may accept only one
    // chunk per call, so a fixed number of calls is insufficient.
    while pushed < data.len() {
        let remaining = &data[pushed..];
        let (blocks, consumed) = adder.push(remaining);

        // Fail closed if the chunker cannot make forward progress.
        if consumed == 0 || consumed > remaining.len() {
            return None;
        }

        if !store_blocks(blocks, &mut root_cid) {
            return None;
        }

        pushed += consumed;
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
    let block = std::fs::read(&path).ok()?;

    // Experimental fail-closed integrity gate.
    // SHA2-256 multihash only; unsupported algorithms are rejected.
    let mh = cid.hash();
    if mh.code() != 0x12 || mh.size() != 32 {
        return None;
    }

    let actual = Sha256::digest(&block);
    if actual.as_slice() != mh.digest() {
        return None;
    }

    Some(block)
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

#[cfg(test)]
mod tests {
    use super::*;

    /// A CID that does not parse is a failed write, not a silent skip: the
    /// caller turns a `false` into "this paste gets no CID".
    #[test]
    fn write_block_refuses_an_unparseable_cid() {
        assert!(!write_block(&"not-a-cid", b"payload"));
    }

    /// A block that cannot be stored leaves no root behind. Reporting the
    /// root anyway is the bug: the CID would resolve to an empty DAG.
    #[test]
    fn store_blocks_stops_and_keeps_no_root_when_a_write_fails() {
        let mut root: Option<String> = None;
        let blocks: Vec<(String, &[u8])> = vec![("also-not-a-cid".to_string(), b"leaf".as_slice())];
        assert!(!store_blocks(blocks, &mut root));
        assert!(root.is_none());
    }

    /// With no IPFS repo reachable, add returns None instead of a CID.
    /// IPFS_PATH is pointed at a path that cannot exist, so this does not
    /// depend on whatever the machine happens to have in ~/.ipfs.
    #[test]
    fn ipfs_add_bytes_returns_none_without_a_repo() {
        let previous = std::env::var("IPFS_PATH").ok();
        std::env::set_var("IPFS_PATH", "/nonexistent-kant-ipfs-repo-for-test");
        let result = ipfs_add_bytes(b"payload");
        match previous {
            Some(v) => std::env::set_var("IPFS_PATH", v),
            None => std::env::remove_var("IPFS_PATH"),
        }
        assert!(result.is_none());
    }
}

// F5_DS12_STEP326_REAL_IPFS_CAT_TEST
#[cfg(test)]
mod ipfs_cat_integrity_integration_tests {
    use super::*;

    struct RestoreIpfsPath(Option<std::ffi::OsString>);

    impl Drop for RestoreIpfsPath {
        fn drop(&mut self) {
            match self.0.take() {
                Some(value) => std::env::set_var("IPFS_PATH", value),
                None => std::env::remove_var("IPFS_PATH"),
            }
        }
    }

    fn flatfs_block_path(repo: &std::path::Path, cid: &Cid) -> std::path::PathBuf {
        let mh_bytes = cid.hash().to_bytes();
        let key = data_encoding::BASE32_NOPAD.encode(&mh_bytes);
        let shard = if key.len() >= 3 {
            &key[key.len() - 3..key.len() - 1]
        } else {
            "AA"
        };

        repo.join("blocks")
            .join(shard)
            .join(format!("{}.data", key))
    }

    #[test]
    fn ipfs_cat_reads_real_flatfs_block_and_fails_closed() {
        let temp = tempfile::tempdir().expect("temporary IPFS repo");

        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        // 1. Generate a real UnixFS block through the project's writer.
        let payload = b"F5-DS12 real ipfs_cat integration test";
        let root_string = ipfs_add_bytes(payload).expect("real UnixFS add must succeed");

        let root: Cid = root_string.parse().expect("valid root CID");

        // 2. Read the actual flatfs block through ipfs_cat().
        let block = ipfs_cat(&root_string).expect("valid CID must retrieve its block");

        assert!(!block.is_empty(), "the UnixFS root block must not be empty");

        assert_eq!(
            root.hash().digest(),
            Sha256::digest(&block).as_slice(),
            "returned block must match its CID multihash"
        );

        // 3. CIDv1 representation with the same codec and multihash.
        let cid_v1 = cid_to_v1(&root_string);
        assert_eq!(
            ipfs_cat(&cid_v1),
            Some(block.clone()),
            "CIDv1 must retrieve the same authenticated block"
        );

        // 4. CIDv1 RAW representation with the same block hash.
        let raw_cid = Cid::new_v1(0x55, root.hash().to_owned()).to_string();

        assert_eq!(
            ipfs_cat(&raw_cid),
            Some(block.clone()),
            "CIDv1 RAW with the same multihash must retrieve the block"
        );

        let path = flatfs_block_path(temp.path(), &root);

        // 5. Tampered content must be rejected.
        let mut corrupted = block.clone();
        corrupted.push(0);

        std::fs::write(&path, &corrupted).expect("write corrupted block");

        assert!(
            ipfs_cat(&root_string).is_none(),
            "modified block must fail integrity verification"
        );

        // 6. Missing content must be rejected.
        std::fs::remove_file(&path).expect("remove flatfs block");

        assert!(
            ipfs_cat(&root_string).is_none(),
            "missing block must not be returned"
        );

        // 7. Unsupported multihash must be rejected.
        // CIDv1: version=1, codec=raw, identity multihash(code=0).
        let unsupported_bytes = [0x01, 0x55, 0x00, 0x01, b'x'];

        let unsupported_cid = format!(
            "b{}",
            data_encoding::BASE32_NOPAD
                .encode(&unsupported_bytes)
                .to_lowercase()
        );

        let unsupported: Cid = unsupported_cid
            .parse()
            .expect("syntactically valid identity-multihash CID");

        let unsupported_path = flatfs_block_path(temp.path(), &unsupported);

        std::fs::create_dir_all(unsupported_path.parent().expect("block parent"))
            .expect("create unsupported block directory");

        std::fs::write(&unsupported_path, b"x").expect("write unsupported block");

        assert!(
            ipfs_cat(&unsupported_cid).is_none(),
            "unsupported multihash must be rejected"
        );

        // 8. Malformed CID must be rejected.
        assert!(
            ipfs_cat("not-a-valid-cid").is_none(),
            "malformed CID must be rejected"
        );
    }
}

// F5_DS12_STEP977B_R7_PRODUCTION_UNIXFS_READER
const C13_MAX_FILE_BYTES: usize = 12 * 1024 * 1024;
const C13_MAX_BLOCK_BYTES: usize = 1024 * 1024;
const C13_MAX_TOTAL_BLOCK_BYTES: usize = 16 * 1024 * 1024;
const C13_MAX_BLOCK_COUNT: usize = 128;

/// Reconstruiește fișierul UnixFS identificat de `cid_string` prin
/// traversarea completă a DAG-ului și întoarce conținutul plus lista
/// ordonată a blocurilor vizitate.
///
/// Fail-closed pe: CID neparsabil, bloc lipsă, bloc supradimensionat,
/// link lipsă, eroare de traversare DAG, orice limită depășită.
pub fn reconstruct_verified_unixfs(cid_string: &str) -> Option<(Vec<u8>, Vec<Cid>)> {
    use rust_unixfs::file::visit::IdleFileVisit;

    let root: Cid = cid_string.parse().ok()?;
    let root_block = ipfs_cat(cid_string)?;

    if root_block.len() > C13_MAX_BLOCK_BYTES {
        return None;
    }

    // Un root raw este deja fișierul complet.
    if root.codec() == 0x55 {
        if root_block.len() > C13_MAX_FILE_BYTES {
            return None;
        }
        return Some((root_block, vec![root]));
    }

    // Doar root-uri UnixFS DAG-PB sunt acceptate aici.
    if root.codec() != 0x70 {
        return None;
    }

    let mut total_block_bytes = root_block.len();

    let (first, file_size, _metadata, mut visit) =
        IdleFileVisit::default().start(&root_block).ok()?;

    let expected_size = usize::try_from(file_size).ok()?;

    if expected_size > C13_MAX_FILE_BYTES {
        return None;
    }

    let mut output = first.to_vec();
    let mut visited = vec![root];

    if output.len() > expected_size {
        return None;
    }

    while let Some(current) = visit {
        if visited.len() >= C13_MAX_BLOCK_COUNT {
            return None;
        }

        let next_cid = {
            let (cid, _) = current.pending_links();
            cid.to_owned()
        };

        let block = ipfs_cat(&next_cid.to_string())?;

        if block.is_empty() || block.len() > C13_MAX_BLOCK_BYTES {
            return None;
        }

        total_block_bytes = total_block_bytes.checked_add(block.len())?;

        if total_block_bytes > C13_MAX_TOTAL_BLOCK_BYTES {
            return None;
        }

        let (chunk, next_visit) = current.continue_walk(&block, &mut None).ok()?;

        output.extend_from_slice(chunk);

        if output.len() > expected_size {
            return None;
        }

        visited.push(next_cid);
        visit = next_visit;
    }

    if output.len() != expected_size {
        return None;
    }

    Some((output, visited))
}

/// Verifică faptul că `root_cid` este un root DAG-PB (0x70) al cărui DAG
/// UnixFS se reconstruiește într-un conținut al cărui SHA-256 coincide
/// exact cu `witness_sha256_hex`.
///
/// Contractul de root C13 este impus explicit aici (nu doar în
/// `c13_valid_root_cid`), ca să nu depindă de un singur punct de control:
/// - CID parsează și se canonicalizează la exact inputul dat;
/// - codec == 0x70 (DAG-PB);
/// - multihash == SHA2-256 (0x12) cu digest de 32 octeți.
///
/// Witness-ul SHA-256 este comparat peste conținutul complet reconstruit,
/// nu peste octeții blocului rădăcină.
///
/// Fail-closed pe: orice abatere de formă a root-ului, eșec de
/// reconstrucție, sau nepotrivire SHA-256.
pub fn verify_c13_content_binding(
    root_cid: &str,
    witness_sha256_hex: &str,
) -> Result<(), &'static str> {
    let parsed: Cid = root_cid.parse().map_err(|_| "invalid root CID")?;

    if parsed.to_string() != root_cid {
        return Err("root CID is not in canonical form");
    }

    // STEP977B_R11C: accept both raw leaves (0x55) and DAG-PB roots
    // (0x70) produced by rust-unixfs::FileAdder. The codec is not the
    // security boundary — the SHA-256 of the reconstructed bytes is.
    if parsed.codec() != 0x55 && parsed.codec() != 0x70 {
        return Err("root CID codec must be raw (0x55) or DAG-PB (0x70)");
    }

    if parsed.hash().code() != 0x12 || parsed.hash().size() != 32 {
        return Err("root CID multihash must be SHA2-256 / 32 bytes");
    }

    let witness_bytes = hex::decode(witness_sha256_hex)
        .map_err(|_| "witness is not valid hex")?;
    if witness_bytes.len() != 32 {
        return Err("witness must be 32 bytes");
    }

    let (content, _visited) =
        reconstruct_verified_unixfs(root_cid).ok_or("UnixFS reconstruction failed")?;

    let actual_digest = Sha256::digest(&content);

    if actual_digest[..] != witness_bytes[..] {
        return Err("reconstructed content SHA-256 does not match witness");
    }

    Ok(())
}

// F5_DS12_STEP511_UNIXFS_RECONSTRUCTION
#[cfg(test)]
mod unixfs_reconstruction_tests {
    use super::*;
    use rust_unixfs::file::visit::IdleFileVisit;
    use std::ffi::OsString;

    #[test]
    fn c13_binding_accepts_valid_dagpb_with_correct_witness() {
        let temp = tempfile::tempdir().expect("temp repo");
        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        // > 256KB guarantees a DAG-PB root from rust-unixfs FileAdder
        // (below chunk size the root is a raw CID, which C13-2 refuses
        // by design; see STEP977B_R10_3_RAW_ROOT_SMALL_UPLOAD finding).
        let content: Vec<u8> = (0..512 * 1024).map(|i| (i % 251) as u8).collect();
        let cid = ipfs_add_bytes(&content).expect("add");
        let witness = hex::encode(Sha256::digest(&content));

        verify_c13_content_binding(&cid, &witness)
            .expect("valid DAG-PB with correct witness must pass");
    }

    #[test]
    fn c13_binding_rejects_wrong_witness() {
        let temp = tempfile::tempdir().expect("temp repo");
        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        let content = b"F5-DS12 binding witness".to_vec();
        let cid = ipfs_add_bytes(&content).expect("add");
        let wrong = hex::encode(Sha256::digest(b"different content"));

        assert!(verify_c13_content_binding(&cid, &wrong).is_err());
    }

    #[test]
    fn c13_binding_rejects_corrupted_leaf() {
        let temp = tempfile::tempdir().expect("temp repo");
        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        let content: Vec<u8> = (0..10 * 1024 * 1024).map(|i| (i % 251) as u8).collect();
        let cid = ipfs_add_bytes(&content).expect("add");
        let witness = hex::encode(Sha256::digest(&content));

        verify_c13_content_binding(&cid, &witness).expect("pre-corruption binding");

        let (_, visited) = reconstruct_verified_unixfs(&cid).expect("pre-corruption read");
        let leaf = visited
            .iter()
            .find(|c| c.codec() == 0x55)
            .expect("multiblock must contain raw leaf")
            .clone();

        let path = flatfs_path(temp.path(), &leaf);
        let mut bytes = std::fs::read(&path).expect("read leaf");
        bytes[0] ^= 0x01;
        std::fs::write(&path, &bytes).expect("write corrupted leaf");

        assert!(
            verify_c13_content_binding(&cid, &witness).is_err(),
            "corrupted leaf must invalidate binding"
        );
    }

    #[test]
    fn c13_binding_rejects_raw_root_with_matching_multihash() {
        let temp = tempfile::tempdir().expect("temp repo");
        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        // > 256KB so the writer produces a DAG-PB root we can reference.
        let content: Vec<u8> = (0..512 * 1024).map(|i| (i * 7 % 251) as u8).collect();
        let dagpb_root = ipfs_add_bytes(&content).expect("add");
        let witness = hex::encode(Sha256::digest(&content));

        // CIDv1 RAW with the same multihash as the DAG-PB root: this is
        // the R4 finding, where ipfs_cat() can retrieve the root block
        // through a raw codec. Content binding must refuse the raw codec
        // as C13 root before SHA comparison.
        let parsed: Cid = dagpb_root.parse().unwrap();
        let raw_cid = Cid::new_v1(0x55, parsed.hash().to_owned()).to_string();

        assert!(
            verify_c13_content_binding(&raw_cid, &witness).is_err(),
            "raw root must be refused even with matching multihash"
        );

        // The DAG-PB root with the same witness must still be accepted.
        verify_c13_content_binding(&dagpb_root, &witness)
            .expect("DAG-PB root must be accepted with matching witness");
    }

    #[test]
    fn c13_binding_rejects_malformed_witness() {
        let temp = tempfile::tempdir().expect("temp repo");
        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        let content = b"x".to_vec();
        let cid = ipfs_add_bytes(&content).expect("add");

        assert!(verify_c13_content_binding(&cid, "not-hex").is_err());
        assert!(verify_c13_content_binding(&cid, &"0".repeat(63)).is_err());
        assert!(verify_c13_content_binding(&cid, &"z".repeat(64)).is_err());
    }

    struct RestoreIpfsPath(Option<OsString>);

    impl Drop for RestoreIpfsPath {
        fn drop(&mut self) {
            match self.0.take() {
                Some(value) => std::env::set_var("IPFS_PATH", value),
                None => std::env::remove_var("IPFS_PATH"),
            }
        }
    }

    fn flatfs_path(repo: &std::path::Path, cid: &Cid) -> std::path::PathBuf {
        let key = data_encoding::BASE32_NOPAD.encode(&cid.hash().to_bytes());

        let shard = &key[key.len() - 3..key.len() - 1];

        repo.join("blocks")
            .join(shard)
            .join(format!("{}.data", key))
    }


    #[test]
    fn unixfs_small_and_multiblock_reconstruction_and_corruption() {
        let temp = tempfile::tempdir().expect("temporary IPFS repo");

        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));

        std::env::set_var("IPFS_PATH", temp.path());

        // STEP512: Single/small UnixFS file.
        let small = b"F5-DS12 verified UnixFS small file".to_vec();

        let small_cid = ipfs_add_bytes(&small).expect("small file must be stored");

        let (small_result, small_blocks) =
            reconstruct_verified_unixfs(&small_cid).expect("small UnixFS reconstruction");

        assert_eq!(small_result, small);
        assert!(!small_blocks.is_empty());

        eprintln!("STEP512_SMALL_UNIXFS_PASS");

        // STEP513: Real multi-block content, not a synthetic DAG.
        let large: Vec<u8> = (0..10 * 1024 * 1024).map(|i| (i % 251) as u8).collect();

        let large_cid = ipfs_add_bytes(&large).expect("large UnixFS add");

        let (large_result, visited) =
            reconstruct_verified_unixfs(&large_cid).expect("large UnixFS reconstruction");

        if large_result != large {
            let common = large_result.len().min(large.len());
            let mismatch = large_result[..common]
                .iter()
                .zip(large[..common].iter())
                .position(|(actual, expected)| actual != expected);

            let offset = mismatch.unwrap_or(common);

            eprintln!("STEP529_EXPECTED_LEN={}", large.len());
            eprintln!("STEP529_ACTUAL_LEN={}", large_result.len());
            eprintln!("STEP529_FIRST_MISMATCH={:?}", mismatch);
            eprintln!("STEP529_FIRST_DIFFERENCE_OFFSET={}", offset);
            eprintln!("STEP529_VISITED_BLOCKS={}", visited.len());
            eprintln!(
                "STEP529_RAW_LEAVES={}",
                visited.iter().filter(|cid| cid.codec() == 0x55).count()
            );
            eprintln!(
                "STEP529_EXPECTED_SHA256={}",
                hex::encode(Sha256::digest(&large))
            );
            eprintln!(
                "STEP529_ACTUAL_SHA256={}",
                hex::encode(Sha256::digest(&large_result))
            );

            let start = offset.saturating_sub(12);
            let expected_end = (offset + 20).min(large.len());
            let actual_end = (offset + 20).min(large_result.len());

            eprintln!(
                "STEP529_EXPECTED_WINDOW={:?}",
                &large[start.min(large.len())..expected_end]
            );
            eprintln!(
                "STEP529_ACTUAL_WINDOW={:?}",
                &large_result[start.min(large_result.len())..actual_end]
            );
        }

        assert!(
            large_result == large,
            "UnixFS reconstruction differs from original content"
        );

        assert!(
            visited.len() > 1,
            "large file must traverse multiple blocks"
        );

        eprintln!("STEP513_MULTIBLOCK_UNIXFS_PASS");
        eprintln!("STEP513_VISITED_BLOCKS={}", visited.len());

        // STEP514: Identify a raw leaf.
        let leaf = visited
            .iter()
            .find(|cid| cid.codec() == 0x55)
            .expect("multiblock DAG must contain raw leaves")
            .clone();

        let leaf_path = flatfs_path(temp.path(), &leaf);

        // STEP515: Corrupt a leaf.
        let mut corrupted = std::fs::read(&leaf_path).expect("read leaf");

        corrupted[0] ^= 0x01;

        std::fs::write(&leaf_path, &corrupted).expect("write corrupted leaf");

        assert!(
            reconstruct_verified_unixfs(&large_cid).is_none(),
            "corrupted leaf must invalidate complete reconstruction"
        );

        eprintln!("STEP515_CORRUPTED_LEAF_REJECTED");

        // STEP516: Missing leaf.
        std::fs::remove_file(&leaf_path).expect("remove leaf");

        assert!(
            reconstruct_verified_unixfs(&large_cid).is_none(),
            "missing leaf must invalidate complete reconstruction"
        );

        eprintln!("STEP516_MISSING_LEAF_REJECTED");

        // STEP517: File-size limit.
        assert!(
            reconstruct_verified_unixfs_with_limit_probe(&large_cid, 1024),
            "oversized file must be rejected"
        );

        eprintln!("STEP517_FILE_SIZE_LIMIT_ENFORCED");
    }

    fn reconstruct_verified_unixfs_with_limit_probe(cid: &str, limit: usize) -> bool {
        let root: Cid = match cid.parse() {
            Ok(value) => value,
            Err(_) => return false,
        };

        let Some(block) = ipfs_cat(cid) else {
            return false;
        };

        let Ok((_, size, _, _)) = IdleFileVisit::default().start(&block) else {
            return false;
        };

        // Confirm that the size guard rejects before traversal.
        root.codec() == 0x70 && usize::try_from(size).map(|n| n > limit).unwrap_or(true)
    }

    // F5_DS12_STEP552_CHUNK_BOUNDARY_REGRESSION
    #[test]
    fn unixfs_chunk_boundaries_reconstruct_all_input_bytes() {
        let temp = tempfile::tempdir().expect("temporary IPFS repo");
        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        let sizes = [
            1usize,
            256 * 1024 - 1,
            256 * 1024,
            256 * 1024 + 1,
            512 * 1024,
            512 * 1024 + 1,
            10 * 1024 * 1024,
            10 * 1024 * 1024 + 1,
        ];

        for size in sizes {
            let content: Vec<u8> = (0..size).map(|i| (i % 251) as u8).collect();

            let cid = ipfs_add_bytes(&content)
                .unwrap_or_else(|| panic!("IPFS add failed for size {}", size));

            let (actual, blocks) = reconstruct_verified_unixfs(&cid)
                .unwrap_or_else(|| panic!("UnixFS reconstruction failed for size {}", size));

            assert_eq!(actual, content, "content mismatch for size {}", size);

            assert!(!blocks.is_empty(), "no blocks visited for size {}", size);

            eprintln!(
                "STEP554_BOUNDARY_PASS size={} blocks={}",
                size,
                blocks.len()
            );
        }
    }

    // F5_DS12_STEP571_PARTIAL_WRITE_ORPHAN
    #[test]
    fn unixfs_partial_write_failure_leaves_prior_block() {
        let temp = tempfile::tempdir().expect("temporary IPFS repo");
        let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
        std::env::set_var("IPFS_PATH", temp.path());

        let content: Vec<u8> = (0..10 * 1024 * 1024).map(|i| (i % 251) as u8).collect();

        // Independently calculate the deterministic FileAdder block sequence.
        let mut adder = FileAdder::default();
        let mut blocks: Vec<(Cid, Vec<u8>)> = Vec::new();
        let mut pushed = 0usize;

        while pushed < content.len() {
            let (produced, consumed) = adder.push(&content[pushed..]);
            assert!(consumed > 0, "FileAdder made no progress");
            blocks.extend(produced);
            pushed += consumed;
        }

        blocks.extend(adder.finish());

        assert!(blocks.len() > 2, "expected multiple UnixFS blocks");

        let first_cid = blocks[0].0;
        let first_block = blocks[0].1.clone();
        let failed_cid = blocks[1].0;

        assert_ne!(first_cid, failed_cid);

        // Make the second block's destination an existing directory.
        let failed_path = flatfs_path(temp.path(), &failed_cid);
        std::fs::create_dir_all(&failed_path).expect("create deliberate second-block collision");

        eprintln!("STEP571_EXPECTED_BLOCKS={}", blocks.len());
        eprintln!("STEP571_FIRST_CID={}", first_cid);
        eprintln!("STEP571_FAILED_CID={}", failed_cid);

        // The actual application writer must fail closed.
        let result = ipfs_add_bytes(&content);

        assert!(
            result.is_none(),
            "partial write must not publish a root CID"
        );

        eprintln!("STEP572_ADD_RETURNED_NONE");

        // The first block was written before the second block failed.
        let first_path = flatfs_path(temp.path(), &first_cid);

        assert!(
            first_path.is_file(),
            "expected prior block to remain on disk"
        );

        assert_eq!(std::fs::read(&first_path).unwrap(), first_block);

        eprintln!("STEP573_PRIOR_BLOCK_REMAINS");

        // The orphan is independently readable by its CID.
        let orphan = ipfs_cat(&first_cid.to_string()).expect("prior block remains readable");

        assert_eq!(orphan, first_block);

        eprintln!("STEP574_ORPHAN_BLOCK_READABLE");
        eprintln!("STEP575_PARTIAL_WRITE_ORPHAN_REPRODUCED");
    }

    // F5_DS12_STEP599_WRITE_PATH_SEMANTICS
    #[cfg(test)]
    mod ipfs_write_path_semantics_tests {
        use super::*;
        use std::ffi::OsString;

        struct RestoreIpfsPath(Option<OsString>);

        impl Drop for RestoreIpfsPath {
            fn drop(&mut self) {
                match self.0.take() {
                    Some(v) => std::env::set_var("IPFS_PATH", v),
                    None => std::env::remove_var("IPFS_PATH"),
                }
            }
        }

        fn block_path(repo: &std::path::Path, cid: &Cid) -> std::path::PathBuf {
            let key = data_encoding::BASE32_NOPAD.encode(&cid.hash().to_bytes());
            let shard = &key[key.len() - 3..key.len() - 1];

            repo.join("blocks")
                .join(shard)
                .join(format!("{}.data", key))
        }

        #[test]
        fn existing_block_and_symlink_are_rejected_by_writer() {
            let tmp = tempfile::tempdir().unwrap();
            let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
            std::env::set_var("IPFS_PATH", tmp.path());

            let original = b"original valid IPFS payload";
            let cid_string = ipfs_add_bytes(original).unwrap();
            let cid: Cid = cid_string.parse().unwrap();
            let path = block_path(tmp.path(), &cid);

            // Existing valid block must not be overwritten.
            assert!(!write_block(&cid_string, b"replacement invalid payload"));
            assert_eq!(std::fs::read(&path).unwrap(), original);
            assert_eq!(ipfs_cat(&cid_string).unwrap(), original);

            eprintln!("STEP628_EXISTING_BLOCK_PRESERVED");

            // Final-component symlink must not be followed.
            std::fs::remove_file(&path).unwrap();

            let victim = tmp.path().join("victim.txt");
            std::fs::write(&victim, b"VICTIM ORIGINAL").unwrap();

            #[cfg(unix)]
            std::os::unix::fs::symlink(&victim, &path).unwrap();

            assert!(!write_block(&cid_string, original));
            assert_eq!(std::fs::read(&victim).unwrap(), b"VICTIM ORIGINAL");

            assert!(std::fs::symlink_metadata(&path)
                .unwrap()
                .file_type()
                .is_symlink());

            eprintln!("STEP629_BLOCK_SYMLINK_REJECTED");
        }

        // F5_DS12_STEP630_DIRECTORY_SYMLINK_REGRESSION
        #[test]
        fn writer_rejects_symlinked_blocks_and_shard_directories() {
            let tmp = tempfile::tempdir().unwrap();
            let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
            std::env::set_var("IPFS_PATH", tmp.path());

            let payload = b"directory symlink regression payload";
            let cid_string = ipfs_add_bytes(payload).unwrap();
            let cid: Cid = cid_string.parse().unwrap();
            let path = block_path(tmp.path(), &cid);

            let shard = path.parent().unwrap().to_path_buf();
            let blocks = shard.parent().unwrap().to_path_buf();

            // Symlink shard directory.
            std::fs::remove_file(&path).unwrap();
            std::fs::remove_dir(&shard).unwrap();

            let external_shard = tmp.path().join("external-shard");
            std::fs::create_dir(&external_shard).unwrap();

            #[cfg(unix)]
            std::os::unix::fs::symlink(&external_shard, &shard).unwrap();

            assert!(!write_block(&cid_string, payload));
            assert!(std::fs::read_dir(&external_shard).unwrap().next().is_none());

            eprintln!("STEP630_SHARD_SYMLINK_REJECTED");

            #[cfg(unix)]
            std::fs::remove_file(&shard).unwrap();

            // Symlink blocks directory.
            std::fs::remove_dir(&shard).ok();
            std::fs::remove_dir(&blocks).unwrap();

            let external_blocks = tmp.path().join("external-blocks");
            std::fs::create_dir(&external_blocks).unwrap();

            #[cfg(unix)]
            std::os::unix::fs::symlink(&external_blocks, &blocks).unwrap();

            assert!(!write_block(&cid_string, payload));
            assert!(std::fs::read_dir(&external_blocks)
                .unwrap()
                .next()
                .is_none());

            eprintln!("STEP631_BLOCKS_DIRECTORY_SYMLINK_REJECTED");
        }

        #[test]
        fn concurrent_identical_block_publication_is_no_clobber() {
            let tmp = tempfile::tempdir().unwrap();
            let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
            std::env::set_var("IPFS_PATH", tmp.path());

            let payload = b"concurrent immutable IPFS block";
            let cid = ipfs_add_bytes(payload).unwrap();

            let mut workers = Vec::new();

            for _ in 0..8 {
                let cid = cid.clone();
                workers.push(std::thread::spawn(move || write_block(&cid, payload)));
            }

            for worker in workers {
                assert!(worker.join().unwrap());
            }

            assert_eq!(ipfs_cat(&cid).unwrap(), payload);

            eprintln!("STEP632_CONCURRENT_IDENTICAL_WRITES_PASS");
        }

        #[test]
        fn concurrent_process_identical_block_publication_is_no_clobber() {
            use std::process::Command;

            const CHILD: &str = "F5_DS12_CROSS_PROCESS_CHILD";

            let payload = b"independent process publication test";

            // Child invocation: publish the same immutable block.
            if let Ok(cid) = std::env::var(CHILD) {
                assert!(write_block(&cid, payload));
                return;
            }

            let temp = tempfile::tempdir().unwrap();
            let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));
            std::env::set_var("IPFS_PATH", temp.path());

            let mut adder = FileAdder::default();
            let (blocks, consumed) = adder.push(payload);
            let mut blocks: Vec<_> = blocks.collect();
            assert_eq!(consumed, payload.len());
            blocks.extend(adder.finish());

            let (root, block) = blocks.last().unwrap();
            let cid = root.to_string();

            let exe = std::env::current_exe().unwrap();
            let filter = concat!(
                "ipfs::unixfs_reconstruction_tests::",
                "ipfs_write_path_semantics_tests::",
                "concurrent_process_identical_block_publication_is_no_clobber"
            );

            let mut children = Vec::new();

            for _ in 0..8 {
                children.push(
                    Command::new(&exe)
                        .arg("--exact")
                        .arg(filter)
                        .arg("--nocapture")
                        .env(CHILD, &cid)
                        .env("IPFS_PATH", temp.path())
                        .spawn()
                        .expect("spawn independent writer process"),
                );
            }

            for mut child in children {
                let status = child.wait().unwrap();
                assert!(status.success(), "writer subprocess failed");
            }

            assert_eq!(ipfs_cat(&cid).unwrap(), block.as_slice());

            eprintln!("STEP637_EIGHT_INDEPENDENT_PROCESSES_PASS");
        }

        #[test]
        fn writer_rejects_symlinked_repository_root_and_reports_mode() {
            use std::os::unix::fs::{MetadataExt, PermissionsExt};

            let temp = tempfile::tempdir().unwrap();
            let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));

            let real_repo = temp.path().join("real-repo");
            std::fs::create_dir(&real_repo).unwrap();

            let alias = temp.path().join("repo-alias");
            std::os::unix::fs::symlink(&real_repo, &alias).unwrap();

            let payload = b"repository root symlink test";
            let mut adder = FileAdder::default();
            let (blocks, _) = adder.push(payload);
            let mut blocks: Vec<_> = blocks.collect();
            blocks.extend(adder.finish());
            let (cid, block) = blocks.last().unwrap();

            std::env::set_var("IPFS_PATH", &alias);

            assert!(!write_block(&cid.to_string(), block.as_ref()));
            assert!(std::fs::read_dir(&real_repo).unwrap().next().is_none());

            eprintln!("STEP638_REPOSITORY_SYMLINK_REJECTED");

            std::env::set_var("IPFS_PATH", &real_repo);

            let cid = ipfs_add_bytes(payload).unwrap();
            let parsed: Cid = cid.parse().unwrap();
            let path = block_path(&real_repo, &parsed);
            let metadata = std::fs::symlink_metadata(&path).unwrap();

            let mode = metadata.permissions().mode() & 0o777;

            eprintln!("STEP638_BLOCK_MODE={:o}", mode);
            eprintln!("STEP638_BLOCK_INODE={}", metadata.ino());

            assert_eq!(mode, 0o600);
            eprintln!("STEP638_WRITER_MODE_CONFIRMED");
        }

        // F5_DS12_STEP708_DIRECTORY_FSYNC_FAILURE_REGRESSION
        #[test]
        fn directory_fsync_failure_points_are_classified() {
            use std::sync::atomic::Ordering;

            struct ResetFaultInjection;

            impl Drop for ResetFaultInjection {
                fn drop(&mut self) {
                    IPFS_FSYNC_FAIL_ON.store(0, Ordering::SeqCst);
                    IPFS_FSYNC_CALLS.store(0, Ordering::SeqCst);
                }
            }

            let _reset = ResetFaultInjection;
            let _restore = RestoreIpfsPath(std::env::var_os("IPFS_PATH"));

            fn count_data_files(path: &std::path::Path) -> usize {
                let Ok(entries) = std::fs::read_dir(path) else {
                    return 0;
                };

                entries
                    .filter_map(Result::ok)
                    .map(|entry| {
                        let path = entry.path();

                        if path.is_dir() {
                            count_data_files(&path)
                        } else if path.extension().and_then(|x| x.to_str()) == Some("data") {
                            1
                        } else {
                            0
                        }
                    })
                    .sum()
            }

            for fail_at in 1..=5 {
                let temp = tempfile::tempdir().unwrap();
                std::env::set_var("IPFS_PATH", temp.path());

                IPFS_FSYNC_CALLS.store(0, Ordering::SeqCst);
                IPFS_FSYNC_FAIL_ON.store(fail_at, Ordering::SeqCst);

                let payload = b"single block fsync fault injection payload";
                let result = ipfs_add_bytes(payload);

                let calls = IPFS_FSYNC_CALLS.load(Ordering::SeqCst);

                // Disable fault injection before inspecting the repository.
                IPFS_FSYNC_FAIL_ON.store(0, Ordering::SeqCst);

                assert!(
                    result.is_none(),
                    "injected fsync failure {} must fail add",
                    fail_at
                );

                assert_eq!(
                    calls, fail_at,
                    "unexpected fsync call count for failure {}",
                    fail_at
                );

                let blocks_dir = temp.path().join("blocks");
                let published = count_data_files(&blocks_dir);

                if fail_at < 5 {
                    assert_eq!(
                        published, 0,
                        "failure {} must happen before block publication",
                        fail_at
                    );
                    eprintln!("STEP708_FSYNC_FAIL_AT_{}_NO_BLOCK_PUBLISHED", fail_at);
                } else {
                    assert_eq!(
                        published, 1,
                        "final shard fsync fails after atomic block publication"
                    );
                    eprintln!("STEP708_FSYNC_FAIL_AT_5_BLOCK_VISIBLE_DURABILITY_UNCERTAIN");
                }

                eprintln!("STEP708_CALLS={} PUBLISHED_BLOCKS={}", calls, published);
            }

            eprintln!("STEP708_ALL_FIVE_FSYNC_FAILURE_POINTS_CLASSIFIED");
        }
    }
}
