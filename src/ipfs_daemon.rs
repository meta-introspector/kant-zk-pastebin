//! IPFS Daemon Management — start, stop, status, and gateway for go-ipfs/kubo.
//!
//! This module wraps the local `ipfs` CLI to manage a daemon process
//! that serves content over HTTP gateway. It is used by the IPFS tile
//! and the task-attachments tile to expose CID links and downloads.

use std::process::Command;
use std::sync::Mutex;
use once_cell::sync::Lazy;

/// Global state for the IPFS daemon.
pub struct IpfsDaemon {
    pub running: bool,
    pub gateway_port: u16,
    pub api_port: u16,
    pub repo_path: String,
}

impl Default for IpfsDaemon {
    fn default() -> Self {
        Self {
            running: false,
            gateway_port: 8080,
            api_port: 5001,
            repo_path: "/mnt/data1/ipfs".to_string(),
        }
    }
}

/// Global daemon state, protected by a mutex.
pub static IPFS_DAEMON: Lazy<Mutex<IpfsDaemon>> =
    Lazy::new(|| Mutex::new(IpfsDaemon::default()));

/// Check if the IPFS daemon is currently running.
pub fn is_running() -> bool {
    IPFS_DAEMON.lock().map(|d| d.running).unwrap_or(false)
}

/// Start the IPFS daemon if not already running.
/// Returns Ok(true) if started, Ok(false) if already running, Err on failure.
pub fn start_daemon() -> Result<bool, String> {
    let mut daemon = IPFS_DAEMON.lock().map_err(|e| e.to_string())?;
    if daemon.running {
        return Ok(false);
    }

    // Check if daemon is already running via process check
    let output = Command::new("pgrep")
        .arg("-f")
        .arg("ipfs daemon")
        .output()
        .map_err(|e| format!("pgrep failed: {}", e))?;

    if output.status.success() {
        daemon.running = true;
        return Ok(false);
    }

    // Start the daemon
    let child = Command::new("ipfs")
        .env("IPFS_PATH", &daemon.repo_path)
        .arg("daemon")
        .arg("--enable-gc")
        .spawn()
        .map_err(|e| format!("failed to start ipfs daemon: {}", e))?;

    // Give it a moment to start
    std::thread::sleep(std::time::Duration::from_millis(500));

    // Verify it's running
    let output = Command::new("ipfs")
        .env("IPFS_PATH", &daemon.repo_path)
        .arg("id")
        .output()
        .map_err(|e| format!("ipfs id failed: {}", e))?;

    if output.status.success() {
        daemon.running = true;
        log::info!("IPFS daemon started on api port {}", daemon.api_port);
        Ok(true)
    } else {
        Err(format!(
            "ipfs daemon failed to start: {}",
            String::from_utf8_lossy(&output.stderr)
        ))
    }
}

/// Stop the IPFS daemon.
pub fn stop_daemon() -> Result<bool, String> {
    let mut daemon = IPFS_DAEMON.lock().map_err(|e| e.to_string())?;
    if !daemon.running {
        return Ok(false);
    }

    let output = Command::new("ipfs")
        .env("IPFS_PATH", &daemon.repo_path)
        .arg("daemon")
        .arg("--stop")
        .output()
        .map_err(|e| format!("failed to stop ipfs daemon: {}", e))?;

    if output.status.success() {
        daemon.running = false;
        log::info!("IPFS daemon stopped");
        Ok(true)
    } else {
        Err(format!(
            "ipfs daemon stop failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ))
    }
}

/// Restart the IPFS daemon.
pub fn restart_daemon() -> Result<bool, String> {
    stop_daemon()?;
    std::thread::sleep(std::time::Duration::from_millis(500));
    start_daemon()
}

/// Get daemon status as a JSON-serializable struct.
pub fn daemon_status() -> serde_json::Value {
    let daemon = IPFS_DAEMON.lock().unwrap_or_else(|poisoned| {
        // Recover from poisoned mutex
        poisoned.into_inner()
    });

    serde_json::json!({
        "running": daemon.running,
        "gateway_port": daemon.gateway_port,
        "api_port": daemon.api_port,
        "repo_path": daemon.repo_path,
        "gateway_url": format!("http://127.0.0.1:{}/", daemon.gateway_port),
        "api_url": format!("http://127.0.0.1:{}/api/v0", daemon.api_port),
    })
}

/// Pin a CID to ensure it's retained locally.
pub fn pin_cid(cid: &str) -> Result<bool, String> {
    if !is_running() {
        start_daemon()?;
    }

    let output = Command::new("ipfs")
        .env("IPFS_PATH", "/mnt/data1/ipfs")
        .arg("pin")
        .arg("add")
        .arg(cid)
        .output()
        .map_err(|e| format!("ipfs pin add failed: {}", e))?;

    Ok(output.status.success())
}

/// List all pinned CIDs.
pub fn list_pins() -> Result<Vec<String>, String> {
    if !is_running() {
        start_daemon()?;
    }

    let output = Command::new("ipfs")
        .env("IPFS_PATH", "/mnt/data1/ipfs")
        .arg("pin")
        .arg("ls")
        .arg("--type")
        .arg("recursive")
        .arg("--format")
        .arg("{{.Key}}")
        .output()
        .map_err(|e| format!("ipfs pin ls failed: {}", e))?;

    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        Ok(stdout.lines().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

/// Get gateway URL for a CID.
pub fn gateway_url(cid: &str) -> String {
    let daemon = IPFS_DAEMON.lock().unwrap();
    format!("http://127.0.0.1:{}/ipfs/{}", daemon.gateway_port, cid)
}

/// Get the public gateway URL for a CID.
pub fn public_gateway_url(cid: &str) -> String {
    format!("https://ipfs.io/ipfs/{}", cid)
}

/// List connected IPFS peers.
pub fn list_peers() -> Result<Vec<PeerInfo>, String> {
    if !is_running() {
        start_daemon()?;
    }

    let output = Command::new("ipfs")
        .env("IPFS_PATH", "/mnt/data1/ipfs")
        .arg("swarm")
        .arg("peers")
        .arg("--format")
        .arg("{{.Peer}}|{{.Addresses}}")
        .output()
        .map_err(|e| format!("ipfs swarm peers failed: {}", e))?;

    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        let peers: Vec<PeerInfo> = stdout
            .lines()
            .filter_map(|line| {
                let parts: Vec<&str> = line.splitn(2, '|').collect();
                if parts.len() == 2 {
                    Some(PeerInfo {
                        id: parts[0].to_string(),
                        addresses: parts[1].split(',').map(|s| s.trim().to_string()).collect(),
                        reputation: 1.0,
                    })
                } else {
                    None
                }
            })
            .collect();
        Ok(peers)
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

/// Peer information with reputation tracking.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PeerInfo {
    pub id: String,
    pub addresses: Vec<String>,
    pub reputation: f64,
}

/// Update peer reputation based on successful/failed content retrieval.
pub fn update_peer_reputation(peer_id: &str, delta: f64) {
    // Reputation tracking is stateless in this implementation.
    // In production, this would persist to disk.
    log::info!("Peer {} reputation delta: {}", peer_id, delta);
}

/// Get peer reputation score.
pub fn get_peer_reputation(peer_id: &str) -> f64 {
    // Default reputation for known peers.
    // In production, this would look up persisted reputation data.
    1.0
}