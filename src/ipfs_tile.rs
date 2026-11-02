//! IPFS Tile — displays CID links, downloads, and pin status.
//!
//! This tile is served at `/tile/ipfs` and provides:
//! - CID link rendering with gateway URLs
//! - Download links
//! - Pin/unpin management
//! - Daemon status

use serde_json::{json, Value};

/// Render the IPFS tile as HTML.
pub fn render_tile() -> String {
    let status = crate::ipfs_daemon::daemon_status();
    let pins = crate::ipfs_daemon::list_pins().unwrap_or_default();
    let peers = crate::ipfs_daemon::list_peers().unwrap_or_default();

    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>IPFS Tile</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; padding: 20px; background: #1a1a2e; color: #e0e0e0; }}
  h1 {{ color: #4cc9f0; border-bottom: 2px solid #4cc9f0; padding-bottom: 10px; }}
  .status {{ display: flex; align-items: center; gap: 10px; margin-bottom: 20px; }}
  .dot {{ width: 12px; height: 12px; border-radius: 50%; }}
  .dot.running {{ background: #4caf50; }}
  .dot.stopped {{ background: #f44336; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 15px; }}
  .card {{ background: #16213e; border-radius: 8px; padding: 15px; }}
  .card h3 {{ margin-top: 0; color: #4cc9f0; }}
  .cid {{ font-family: monospace; font-size: 0.9em; word-break: break-all; }}
  .peer {{ font-family: monospace; font-size: 0.85em; word-break: break-all; }}
  .rep {{ font-size: 0.8em; font-weight: bold; }}
  .rep.high {{ color: #4caf50; }}
  .rep.medium {{ color: #ffa726; }}
  .rep.low {{ color: #f44336; }}
  .btn {{ display: inline-block; padding: 8px 16px; margin: 4px; background: #4cc9f0; color: #000; border-radius: 4px; text-decoration: none; font-size: 0.9em; }}
  .btn:hover {{ background: #3aa8d0; }}
  .btn.secondary {{ background: #6c757d; color: #fff; }}
  .btn.secondary:hover {{ background: #5a6268; }}
  a {{ color: #4cc9f0; }}
</style>
</head>
<body>
  <h1>📦 IPFS Tile</h1>
  <div class="status">
    <span class="dot {}"></span>
    <span>Daemon: {} | Gateway: {} | API: {}</span>
  </div>
  <div class="grid">
    <div class="card">
      <h3>Daemon Control</h3>
      <a class="btn" href="/tile/ipfs/start">Start</a>
      <a class="btn secondary" href="/tile/ipfs/stop">Stop</a>
      <a class="btn secondary" href="/tile/ipfs/restart">Restart</a>
    </div>
    <div class="card">
      <h3>Pinned CIDs ({})</h3>
      {}
    </div>
    <div class="card">
      <h3>Connected Peers ({})</h3>
      {}
    </div>
  </div>
</body>
</html>"#,
        if status["running"].as_bool().unwrap_or(false) { "running" } else { "stopped" },
        if status["running"].as_bool().unwrap_or(false) { "Online" } else { "Offline" },
        status["gateway_url"],
        status["api_url"],
        pins.len(),
        pins.iter().map(|cid| format!("<div class=\"cid\"><a href=\"/ipfs/{}\" target=\"_blank\">{}</a> <a class=\"btn secondary\" href=\"/tile/ipfs/unpin/{}\">unpin</a></div>", cid, &cid[..cid.len().min(20)], cid)).collect::<Vec<_>>().join(""),
        peers.len(),
        peers.iter().map(|p| {
            let rep_color = if p.reputation >= 0.7 { "high" } else if p.reputation >= 0.4 { "medium" } else { "low" };
            format!("<div class=\"peer\"><span class=\"rep {}\">{:.1}</span> {}<br><div style=\"font-size:0.75em;color:#888\">{}</div></div>", rep_color, p.reputation, p.id, p.addresses.join(", "))
        }).collect::<Vec<_>>().join(""),
    )
}

/// Render a simple JSON status for API calls.
pub fn status_json() -> Value {
    json!({
        "tile": "ipfs",
        "daemon": crate::ipfs_daemon::daemon_status(),
        "pins": crate::ipfs_daemon::list_pins().unwrap_or_default(),
        "peers": crate::ipfs_daemon::list_peers().unwrap_or_default(),
    })
}