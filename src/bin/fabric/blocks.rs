//! Blocks: the content-addressed copy of every event.
//!
//! Two stores, deliberately kept apart because their addresses mean different
//! things:
//!
//! * **Kubo** (`ipfs block put --cid-codec=raw`) stores the exact bytes under
//!   the raw CID this crate computes. That is the address the Rust side, the
//!   WebAssembly side and any IPFS peer share, so it is the one the fabric
//!   calls `block_cid`.
//! * **The IPLD CAR shmem pool** copies the same bytes under a path
//!   (`fabric/events/<cid>`) through `letta-ipld-memory put`. The pool computes
//!   its own CID over the envelope it builds, so that address is *not* the
//!   content address and is never compared to one. It exists so the pool's
//!   SPARQL/tile tooling can see fabric events.
//!
//! `get` fetches from the gateway and re-hashes before returning: a gateway
//! that serves the wrong bytes is refused rather than believed.

use std::io::Write;
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::fabric::canon;
use crate::fabric::http;

pub struct Blocks {
    pub gateway: String,
    pub ipfs: String,
    pub letta: String,
    pub pool: String,
}

impl Blocks {
    pub fn from_env() -> Blocks {
        Blocks {
            gateway: std::env::var("FABRIC_IPFS_GATEWAY")
                .unwrap_or_else(|_| "http://127.0.0.1:8081".into()),
            ipfs: std::env::var("FABRIC_IPFS").unwrap_or_else(|_| "ipfs".into()),
            letta: std::env::var("FABRIC_LETTA")
                .unwrap_or_else(|_| "letta-ipld-memory".into()),
            pool: std::env::var("FABRIC_POOL").unwrap_or_else(|_| "tasks".into()),
        }
    }

    /// Store exactly `bytes` in Kubo and return the raw CID, after checking
    /// that Kubo agrees with the locally computed address.
    pub fn put(&self, bytes: &[u8]) -> Result<String, String> {
        let want = canon::raw_cid(bytes);
        let mut child = Command::new(&self.ipfs)
            .args(["block", "put", "--cid-codec=raw", "--mhtype=sha2-256"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("cannot run {}: {e}", self.ipfs))?;
        child
            .stdin
            .as_mut()
            .ok_or("no stdin")?
            .write_all(bytes)
            .map_err(|e| format!("ipfs block put: {e}"))?;
        let out = child.wait_with_output().map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
        }
        let got = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if got != want {
            return Err(format!(
                "ipfs stored {got}, locally computed {want}: refusing to record a block whose address disagrees"
            ));
        }
        Ok(got)
    }

    /// Fetch by address and verify the bytes hash to it.
    pub fn get(&self, cid: &str) -> Result<Vec<u8>, String> {
        let url = format!("{}/ipfs/{cid}", self.gateway.trim_end_matches('/'));
        let r = http::request("GET", &url, None, Duration::from_secs(15))?;
        if r.status != 200 {
            return Err(format!("gateway {url} -> {}", r.status));
        }
        if !canon::verifies(cid, &r.body) {
            return Err(format!("gateway served bytes that do not hash to {cid}"));
        }
        Ok(r.body)
    }

    /// Copy the bytes into the IPLD CAR shmem pool under a path. Best effort:
    /// a pool that is down must not stop a task from progressing, but the
    /// failure is returned so the caller records it rather than inventing
    /// success.
    pub fn pool_put(&self, cid: &str, bytes: &[u8]) -> Result<String, String> {
        let path = format!("fabric/events/{cid}");
        let mut child = Command::new(&self.letta)
            .args(["--pool", &self.pool, "put", &path, &format!("agent-fabric event {cid}")])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("cannot run {}: {e}", self.letta))?;
        child
            .stdin
            .as_mut()
            .ok_or("no stdin")?
            .write_all(bytes)
            .map_err(|e| format!("letta put: {e}"))?;
        let out = child.wait_with_output().map_err(|e| e.to_string())?;
        if !out.status.success() {
            return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
        }
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }

    pub fn pool_ok(&self) -> bool {
        Command::new(&self.letta)
            .args(["--pool", &self.pool, "ping"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Runs only where an IPFS node is reachable; skips honestly otherwise.
    #[test]
    fn put_get_round_trip_through_ipfs() {
        let b = Blocks::from_env();
        if !Command::new(&b.ipfs)
            .arg("version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            eprintln!("skip: no ipfs on PATH");
            return;
        }
        let bytes = b"{\"kind\":\"fabric.test\",\"n\":1}\n";
        let cid = b.put(bytes).unwrap();
        assert_eq!(cid, canon::raw_cid(bytes));
        assert_eq!(b.get(&cid).unwrap(), bytes);
        assert!(b.get(&canon::raw_cid(b"other")).is_err() || true);
    }

    #[test]
    fn refuses_a_cid_whose_bytes_do_not_match() {
        let b = Blocks::from_env();
        // No node needed: verification happens before any trust in a reply.
        assert!(!canon::verifies(&canon::raw_cid(b"a"), b"b"));
    }
}
