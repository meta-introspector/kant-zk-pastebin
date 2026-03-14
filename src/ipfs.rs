// IPFS - Content addressing via rust-unixfs FileAdder + go-ipfs flatfs writes
use sha2::{Sha256, Digest};
use serde::{Serialize, Deserialize};
use ipfs_unixfs::file::adder::FileAdder;
use ipld_core::cid::Cid;

/// Content addressing backend trait
pub trait ContentStore: Send + Sync {
    fn name(&self) -> &str;
    fn add(&self, data: &[u8]) -> Option<String>;
}

// === IPFS block storage (go-ipfs flatfs compatible) ===

fn ipfs_repo() -> Option<String> {
    std::env::var("IPFS_PATH").ok().or_else(|| {
        dirs_next::home_dir().map(|h| format!("{}/.ipfs", h.display()))
    }).filter(|p| std::path::Path::new(p).exists())
}

/// Write a single block to go-ipfs flatfs: ~/.ipfs/blocks/XX/KEY.data
/// Key = base32upper(multihash), shard = next-to-last/2
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

/// Add content via FileAdder, write all blocks to flatfs, return root CID string
pub fn ipfs_add_bytes(data: &[u8]) -> Option<String> {
    let mut adder = FileAdder::default();
    let mut root_cid = None;

    let (blocks, consumed) = adder.push(data);
    for (cid, block) in blocks {
        write_block(&cid, &block);
        root_cid = Some(cid);
    }
    // push remaining if not fully consumed
    if consumed < data.len() {
        let (blocks, _) = adder.push(&data[consumed..]);
        for (cid, block) in blocks {
            write_block(&cid, &block);
            root_cid = Some(cid);
        }
    }
    // finish tree
    for (cid, block) in adder.finish() {
        write_block(&cid, &block);
        root_cid = Some(cid);
    }

    root_cid.map(|c| c.to_string())
}

pub fn ipfs_add(content: &str) -> Option<String> {
    ipfs_add_bytes(content.as_bytes())
}

/// Read block from go-ipfs flatfs by CID
pub fn ipfs_cat(cid_str: &str) -> Option<Vec<u8>> {
    let repo = ipfs_repo()?;
    let cid: Cid = cid_str.parse().ok()?;
    let mh_bytes = cid.hash().to_bytes();
    let key = data_encoding::BASE32_NOPAD.encode(&mh_bytes);
    let shard = if key.len() >= 3 { &key[key.len()-3..key.len()-1] } else { "AA" };
    let path = format!("{}/blocks/{}/{}.data", repo, shard, key);
    std::fs::read(&path).ok()
}

pub fn local_cid(data: &[u8]) -> String {
    let hash = Sha256::digest(data);
    format!("bafk{}", hex::encode(&hash[..16]))
}

// === CIDv1 string for display (base32lower) ===

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

pub struct RustStore;
impl ContentStore for RustStore {
    fn name(&self) -> &str { "rust-unixfs" }
    fn add(&self, data: &[u8]) -> Option<String> { ipfs_add_bytes(data) }
}

pub struct DaslCborStore;
impl ContentStore for DaslCborStore {
    fn name(&self) -> &str { "dasl-cbor" }
    fn add(&self, data: &[u8]) -> Option<String> {
        let (cbor, _) = wrap_dasl_cbor(data);
        ipfs_add_bytes(&cbor)
    }
}

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
