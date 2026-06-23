// Git2Nora plugin — detect Rust crate source code and publish to nora registry.
//
// When pasted content looks like a publishable crate (has Cargo.toml with
// [package] name + version), the paste view renders a "Push to Nora" button.
// On click: writes crate files to a workspace dir, runs cargo package + publish.
//
// Environment:
//   NORA_URL — base URL of the nora registry (default: http://127.0.0.1:4000)
//   UUCP_SPOOL — path to pastebin spool (default: /mnt/data1/spool/uucp/pastebin)
//
// The git2nora pipeline in pipelight.toml automates batch publishing from spool.

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::path::PathBuf;

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/// Returns true if `content` looks like a Rust crate's Cargo.toml
/// containing a `[package]` section with `name` and `version`.
pub fn is_crate_cargo_toml(content: &str) -> bool {
    let trimmed = content.trim();
    // Must have [package] header
    if !trimmed.contains("[package]") {
        return false;
    }
    let has_name = content.lines().any(|l| {
        let l = l.trim();
        l.starts_with("name") && l.contains('"')
    });
    let has_version = content.lines().any(|l| {
        let l = l.trim();
        l.starts_with("version") && l.contains('"')
    });
    has_name && has_version
}

/// Returns true if `content` contains Rust source code that could be part of a crate.
/// Matches on: `fn main()`, `use crate::`, `mod ` (module decls), `impl `, `struct `, `enum `.
pub fn is_rust_source(content: &str) -> bool {
    let keywords = [
        "fn main(",
        "use crate::",
        "mod ",
        "pub struct",
        "pub enum",
        "pub fn",
        "impl ",
    ];
    let count = keywords.iter().filter(|k| content.contains(*k)).count();
    count >= 2
}

/// Returns true if content is a git URL (clone-able) that could point to a crate.
pub fn is_git_url(content: &str) -> bool {
    let t = content.trim();
    t.starts_with("https://") || t.starts_with("git@") || t.starts_with("http://")
}

/// Returns true if the paste content looks publishable to nora.
pub fn is_publishable_crate(content: &str) -> bool {
    is_crate_cargo_toml(content) || is_rust_source(content)
}

// ---------------------------------------------------------------------------
// Tile HTML
// ---------------------------------------------------------------------------

/// Render the "Push to Nora" tile HTML snippet for a paste.
pub fn render_git2nora_tile_html(paste_id: &str, base_path: &str) -> String {
    let escaped_id = paste_id.replace('"', "&quot;");
    let escaped_base = base_path.trim_end_matches('/');
    format!(
        r#"<div class="git2nora-tile" style="background:#1a1a2e;border:1px solid #f90;border-radius:8px;padding:15px;margin:15px 0;font-family:monospace">
<h3 style="color:#f90;margin:0 0 10px 0">📦 Push to Nora</h3>
<p style="color:#ccc;font-size:13px;margin:0 0 10px 0">Publish this crate to the local Nora artifact registry</p>
<div style="display:flex;gap:10px;flex-wrap:wrap">
<button class="git2nora-btn" onclick="git2noraAction('{0}','inspect')" style="background:#f90;color:#000;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">🔍 Inspect</button>
<button class="git2nora-btn" onclick="git2noraAction('{0}','publish')" style="background:#ff6600;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">🚀 Publish to Nora</button>
</div>
<pre id="git2nora-output-{0}" style="background:#0d0d1a;padding:10px;border-radius:4px;margin-top:10px;max-height:300px;overflow:auto;font-size:12px;display:none;white-space:pre-wrap"></pre>
</div>
<script>
function git2noraAction(id,action){{
  const prefix='{1}';
  const pre=document.getElementById('git2nora-output-'+id);
  if(!pre)return;
  pre.style.display='block';
  pre.innerHTML='⏳ '+action+'...';
  fetch(prefix+'/plugin/git2nora/'+id,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{action:action}})}})
  .then(r=>r.json())
  .then(data=>{{pre.innerHTML=data.status==='ok'?'✅ OK\n'+data.output:'❌ Error\n'+data.output;}})
  .catch(err=>{{pre.innerHTML='❌ '+err;}});
}}
</script>"#,
        escaped_id, escaped_base
    )
}

// ---------------------------------------------------------------------------
// Nora publishing
// ---------------------------------------------------------------------------

/// Get nora registry URL from env or default
fn nora_url() -> String {
    std::env::var("NORA_URL").unwrap_or_else(|_| "http://127.0.0.1:4000".to_string())
}

/// Get spool directory
fn spool_dir() -> String {
    std::env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string())
}

/// Find the paste content file in the spool by ID
fn find_paste_file(paste_id: &str) -> Option<String> {
    let dir = spool_dir();
    let entries = std::fs::read_dir(&dir).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.contains(paste_id) && name.ends_with(".txt") {
            return std::fs::read_to_string(entry.path()).ok();
        }
    }
    None
}

/// Inspect the paste to see what kind of crate content it is.
fn inspect_paste(paste_id: &str) -> Result<String, String> {
    let content = find_paste_file(paste_id)
        .ok_or_else(|| format!("paste {} not found in spool", paste_id))?;

    // Parse headers and body
    let (headers, body) = parse_paste_headers(&content);

    let has_cargo_toml = is_crate_cargo_toml(body);
    let is_rust = is_rust_source(body);
    let is_git = is_git_url(body);
    let lines = body.lines().count();
    let bytes = body.len();

    let mut report = String::new();
    report.push_str(&format!("Paste: {}\n", paste_id));
    report.push_str(&format!(
        "Title: {}\n",
        headers.get("Title").unwrap_or(&"N/A".to_string())
    ));
    report.push_str(&format!("Size: {} lines, {} bytes\n", lines, bytes));
    report.push_str(&format!(
        "Has Cargo.toml: {}\n",
        if has_cargo_toml { "YES" } else { "no" }
    ));
    report.push_str(&format!(
        "Is Rust source: {}\n",
        if is_rust { "YES" } else { "no" }
    ));
    report.push_str(&format!(
        "Is Git URL: {}\n",
        if is_git { "YES" } else { "no" }
    ));
    report.push_str(&format!(
        "Publishable: {}\n",
        if is_publishable_crate(body) {
            "YES"
        } else {
            "no"
        }
    ));

    if has_cargo_toml {
        report.push_str("\n--- Crate info ---\n");
        for line in body.lines() {
            let t = line.trim();
            if t.starts_with("name")
                || t.starts_with("version")
                || t.starts_with("edition")
                || t.starts_with("authors")
            {
                report.push_str(&format!("  {}\n", line));
            }
        }
    }

    Ok(report)
}

/// Parse paste content into (headers, body).
fn parse_paste_headers(content: &str) -> (HashMap<String, String>, &str) {
    let mut headers = HashMap::new();
    let mut body_start = 0;
    for (i, line) in content.lines().enumerate() {
        if line.is_empty() && i > 0 {
            body_start = content.lines().take(i + 1).map(|l| l.len() + 1).sum();
            break;
        }
        if let Some((key, value)) = line.split_once(':') {
            headers.insert(key.trim().to_string(), value.trim().to_string());
        }
    }
    let body = if body_start > 0 && body_start < content.len() {
        &content[body_start..]
    } else {
        content
    };
    (headers, body)
}

/// Create a publishable crate workspace from the paste content and publish to nora.
fn publish_to_nora(paste_id: &str) -> Result<String, String> {
    let content = find_paste_file(paste_id)
        .ok_or_else(|| format!("paste {} not found in spool", paste_id))?;

    let (headers, body) = parse_paste_headers(&content);

    // Create workspace dir
    let work_dir = PathBuf::from("/tmp/git2nora").join(paste_id.replace('/', "_"));
    std::fs::create_dir_all(&work_dir).map_err(|e| format!("mkdir: {}", e))?;

    // Determine crate name
    let crate_name = if is_crate_cargo_toml(body) {
        let found = body.lines().find(|l| l.trim().starts_with("name"));
        let name = found
            .and_then(|l| l.split_once('='))
            .map(|(_, v)| {
                let v = v.trim();
                v.strip_prefix('"')
                    .and_then(|s| s.strip_suffix('"'))
                    .or_else(|| {
                        v.strip_suffix(',').and_then(|s| {
                            s.trim()
                                .strip_prefix('"')
                                .and_then(|s2| s2.strip_suffix('"'))
                        })
                    })
                    .unwrap_or(v.trim_matches('"').trim_matches(','))
            })
            .unwrap_or("unnamed")
            .to_string();
        name
    } else {
        headers
            .get("Title")
            .map(|s| s.replace(|c: char| !c.is_alphanumeric() && c != '_' && c != '-', "_"))
            .unwrap_or_else(|| paste_id.to_string())
    };

    // If body is a single Cargo.toml, use it directly
    // Otherwise, create Cargo.toml + src/lib.rs
    if is_crate_cargo_toml(body) {
        // Write the Cargo.toml
        std::fs::write(work_dir.join("Cargo.toml"), body)
            .map_err(|e| format!("write Cargo.toml: {}", e))?;

        // Ensure src/lib.rs exists (cargo package requires it)
        let src_dir = work_dir.join("src");
        std::fs::create_dir_all(&src_dir).map_err(|e| format!("mkdir src: {}", e))?;
        let lib_rs = src_dir.join("lib.rs");
        if !lib_rs.exists() {
            std::fs::write(&lib_rs, "// Generated by git2nora\npub fn hello() -> &'static str { \"published via git2nora\" }\n")
                .map_err(|e| format!("write lib.rs: {}", e))?;
        }
    } else {
        // Write content as lib.rs, create minimal Cargo.toml
        let src_dir = work_dir.join("src");
        std::fs::create_dir_all(&src_dir).map_err(|e| format!("mkdir src: {}", e))?;
        std::fs::write(src_dir.join("lib.rs"), body).map_err(|e| format!("write lib.rs: {}", e))?;

        let cargo_toml = format!(
            r#"[package]
name = "{}"
version = "0.1.0"
edition = "2021"

[dependencies]
"#,
            crate_name
        );
        std::fs::write(work_dir.join("Cargo.toml"), &cargo_toml)
            .map_err(|e| format!("write Cargo.toml: {}", e))?;
    }

    // Set up cargo config for nora registry
    let cargo_dir = work_dir.join(".cargo");
    std::fs::create_dir_all(&cargo_dir).map_err(|e| format!("mkdir .cargo: {}", e))?;
    let nora = nora_url();
    let cargo_config = format!(
        r#"[registries.nora]
index = "{nora}/cargo/git"

[registry]
default = "nora"
"#
    );
    std::fs::write(cargo_dir.join("config.toml"), &cargo_config)
        .map_err(|e| format!("write .cargo/config.toml: {}", e))?;

    // Shell-out disabled per system requirements
    return Err("publish_to_nora disabled: cargo shell-out not allowed".to_string());
}

// ---------------------------------------------------------------------------
// Plugin implementation
// ---------------------------------------------------------------------------

pub struct Git2NoraPlugin;

impl Git2NoraPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for Git2NoraPlugin {
    fn name(&self) -> &str {
        "git2nora"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "Push source code pastes to the Nora artifact registry — cargo publish from the pastebin"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let content = String::from_utf8_lossy(&input.content);
        let action = input
            .extra
            .get("action")
            .map(|s| s.as_str())
            .unwrap_or("detect");
        let mut result = HashMap::new();

        match action {
            "detect" => {
                let is_publishable = is_publishable_crate(&content);
                result.insert("is_publishable".into(), is_publishable.to_string());
                result.insert(
                    "detected_type".into(),
                    if is_crate_cargo_toml(&content) {
                        "cargo_toml".to_string()
                    } else if is_rust_source(&content) {
                        "rust_source".to_string()
                    } else {
                        "unknown".to_string()
                    },
                );
                if is_publishable {
                    let bp = input
                        .extra
                        .get("base_path")
                        .map(|s| s.as_str())
                        .unwrap_or("");
                    result.insert("tile_html".into(), render_git2nora_tile_html(&input.id, bp));
                }
            }
            "inspect" | "publish" => {
                result.insert("status".into(), "error".into());
                result.insert(
                    "output".into(),
                    "git2nora CLI actions disabled: no shell-out allowed".to_string(),
                );
            }
            other => {
                result.insert("error".into(), format!("unknown action: {}", other));
                result.insert("status".into(), "error".into());
            }
        }

        Ok(result)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_cargo_toml() {
        let content = r#"[package]
name = "my-crate"
version = "0.1.0"
edition = "2021"
"#;
        assert!(is_crate_cargo_toml(content));
    }

    #[test]
    fn test_detect_cargo_toml_no_version() {
        let content = r#"[package]
name = "my-crate"
"#;
        // Needs both name and version
        assert!(!is_crate_cargo_toml(content));
    }

    #[test]
    fn test_detect_rust_source() {
        let content = r#"
fn main() {
    println!("hello");
}

pub fn helper() -> i32 { 42 }
"#;
        assert!(is_rust_source(content));
    }

    #[test]
    fn test_detect_plain_text() {
        assert!(!is_rust_source("hello world, this is not code"));
        assert!(!is_crate_cargo_toml("just some text"));
    }

    #[test]
    fn test_render_tile_html() {
        let html = render_git2nora_tile_html("test-123", "/pastebin");
        assert!(html.contains("git2nora-tile"));
        assert!(html.contains("test-123"));
        assert!(html.contains("Push to Nora"));
        assert!(html.contains("Publish"));
        assert!(html.contains("Inspect"));
    }

    #[test]
    fn test_is_git_url() {
        assert!(is_git_url("https://github.com/user/repo.git"));
        assert!(is_git_url("git@github.com:user/repo.git"));
        assert!(!is_git_url("just a sentence"));
    }
}
