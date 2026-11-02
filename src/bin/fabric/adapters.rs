//! Probes for everything the one unit is supposed to work with.
//!
//! `gate` is what `ExecStartPre` runs: it must exit non-zero when a dependency
//! the fabric needs is not answering, so the unit does not come up pretending
//! to be part of a system that is not there. `capabilities` is the same set of
//! probes plus what this host can actually offer an agent (GPU, git mounts,
//! the IPLD pool), and it is reported rather than assumed.

use std::process::{Command, Stdio};
use std::time::Duration;

use serde_json::{json, Value};

use crate::fabric::blocks::Blocks;
use crate::fabric::chat::Relay;
use crate::fabric::http;
use crate::fabric::store::Store;

pub struct Deps {
    pub pastebin: String,
    pub shmem: String,
    pub cf_api: String,
    pub do_url: String,
    pub git_mounts: Vec<String>,
}

impl Deps {
    pub fn from_env() -> Deps {
        let mounts = std::env::var("FABRIC_GIT_MOUNTS")
            .or_else(|_| std::env::var("GIT_MOUNTS"))
            .unwrap_or_else(|_| "/home/mdupont/dasl".into());
        Deps {
            pastebin: std::env::var("FABRIC_PASTEBIN")
                .unwrap_or_else(|_| "http://127.0.0.1:8090".into()),
            shmem: std::env::var("FABRIC_SHMEM")
                .unwrap_or_else(|_| "http://127.0.0.1:8154".into()),
            cf_api: std::env::var("FABRIC_CF_API")
                .unwrap_or_else(|_| "http://127.0.0.1:3323".into()),
            do_url: std::env::var("FABRIC_DO_URL").unwrap_or_default(),
            git_mounts: mounts
                .split(':')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
        }
    }
}

fn get_json(url: &str, timeout_secs: u64) -> Result<Value, String> {
    let r = http::request("GET", url, None, Duration::from_secs(timeout_secs))?;
    if r.status != 200 {
        return Err(format!("{url} -> {}", r.status));
    }
    r.json()
}

fn probe_http(url: &str, path: &str) -> (bool, String) {
    match http::request(
        "GET",
        &format!("{}{}", url.trim_end_matches('/'), path),
        None,
        Duration::from_secs(5),
    ) {
        Ok(r) if r.status == 200 => (true, format!("200 ({} bytes)", r.body.len())),
        Ok(r) => (false, format!("status {}", r.status)),
        Err(e) => (false, e),
    }
}

pub fn gpu() -> Option<Value> {
    let out = Command::new("nvidia-smi")
        .args([
            "--query-gpu=index,name,memory.total,driver_version",
            "--format=csv,noheader",
        ])
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if text.is_empty() {
        return None;
    }
    let gpus: Vec<Value> = text
        .lines()
        .map(|l| {
            let f: Vec<&str> = l.split(',').map(|s| s.trim()).collect();
            json!({
                "index": f.first().unwrap_or(&""),
                "name": f.get(1).unwrap_or(&""),
                "memory": f.get(2).unwrap_or(&""),
                "driver": f.get(3).unwrap_or(&""),
            })
        })
        .collect();
    Some(json!(gpus))
}

/// A git mount is usable when `git -C <root> rev-parse HEAD` answers. The
/// pastebin has a `git_mount` module but the deployed service registers no
/// route for it and sets no `GIT_MOUNTS`, so this reads the same environment
/// directly and the report says which mounts answered.
pub fn git_mounts(mounts: &[String]) -> Vec<Value> {
    mounts
        .iter()
        .map(|m| {
            let head = Command::new("git")
                .args(["-C", m, "rev-parse", "HEAD"])
                .stderr(Stdio::null())
                .output();
            match head {
                Ok(o) if o.status.success() => {
                    let sha = String::from_utf8_lossy(&o.stdout).trim().to_string();
                    let branch = Command::new("git")
                        .args(["-C", m, "rev-parse", "--abbrev-ref", "HEAD"])
                        .stderr(Stdio::null())
                        .output()
                        .ok()
                        .map(|b| String::from_utf8_lossy(&b.stdout).trim().to_string())
                        .unwrap_or_default();
                    json!({"root": m, "ok": true, "head": sha, "branch": branch})
                }
                _ => json!({"root": m, "ok": false, "error": "git rev-parse failed"}),
            }
        })
        .collect()
}

/// The gate. Empty `failures` means the unit may start.
pub fn gate(store: &Store, blocks: &Blocks, relay: &Relay, deps: &Deps) -> (Vec<String>, Value) {
    let mut failures = Vec::new();
    let mut report = serde_json::Map::new();

    match store.count() {
        Ok((e, t)) => {
            report.insert("postgres".into(), json!({"ok": true, "events": e, "tasks": t}));
        }
        Err(e) => {
            failures.push(format!("postgres: {e}"));
            report.insert("postgres".into(), json!({"ok": false, "error": e}));
        }
    }

    let (ok, detail) = probe_http(&deps.pastebin, "/");
    report.insert(
        "pastebin".into(),
        json!({"ok": ok, "url": deps.pastebin, "detail": detail}),
    );
    if !ok {
        failures.push(format!("pastebin at {}: {detail}", deps.pastebin));
    }

    match get_json(&format!("{}/health", deps.shmem.trim_end_matches('/')), 5) {
        Ok(v) => {
            report.insert("ipld_shmem".into(), json!({"ok": true, "health": v}));
        }
        Err(e) => {
            failures.push(format!("ipld shmem at {}: {e}", deps.shmem));
            report.insert("ipld_shmem".into(), json!({"ok": false, "error": e}));
        }
    }

    match relay.health() {
        Ok(v) => {
            report.insert("relay".into(), json!({"ok": true, "health": v}));
        }
        Err(e) => {
            failures.push(format!("relay at {}: {e}", relay.url));
            report.insert("relay".into(), json!({"ok": false, "error": e}));
        }
    }

    let (ok, detail) = probe_http(&deps.cf_api, "/health");
    report.insert(
        "cloudflare_api".into(),
        json!({"ok": ok, "url": deps.cf_api, "detail": detail}),
    );
    if !ok {
        failures.push(format!("cloudflare api at {}: {detail}", deps.cf_api));
    }

    let ipfs_ok = Command::new(&blocks.ipfs)
        .arg("version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    report.insert("ipfs".into(), json!({"ok": ipfs_ok, "endpoint": blocks.ipfs}));
    if !ipfs_ok {
        failures.push("ipfs: `ipfs version` failed".into());
    }

    let pool = blocks.pool_ok();
    report.insert(
        "ipld_pool".into(),
        json!({"ok": pool, "pool": blocks.pool, "letta": blocks.letta}),
    );
    if !pool {
        failures.push(format!("ipld pool {}: letta ping failed", blocks.pool));
    }

    let gpus = gpu();
    report.insert("gpu".into(), json!({"ok": gpus.is_some(), "devices": gpus}));

    report.insert("git_mounts".into(), json!(git_mounts(&deps.git_mounts)));

    if !deps.do_url.is_empty() {
        let (ok, detail) = probe_http(&deps.do_url, "/health");
        report.insert(
            "durable_object".into(),
            json!({"ok": ok, "url": deps.do_url, "detail": detail}),
        );
        // The DO is a mirror, not the source of truth: its absence is reported
        // but does not stop local work.
    }

    (failures, Value::Object(report))
}
