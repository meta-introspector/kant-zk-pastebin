// Nix tile — Nix flake introspection, build outputs, derivation analysis
// Each flake.nix becomes a tile showing its outputs, inputs, and build status.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;
use std::path::Path;

pub struct NixTilePlugin;

impl NixTilePlugin {
    pub fn new() -> Self { Self }

    fn discover_flakes(root: &str) -> Vec<(String, String)> {
        let mut flakes = Vec::new();

        let flake_path = Path::new(root).join("flake.nix");
        if flake_path.exists() {
            let name = Path::new(root).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            flakes.push((name, root.to_string()));
        }

        // Walk one level deep
        if let Ok(entries) = std::fs::read_dir(root) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() && !path.to_string_lossy().contains("target") && !path.to_string_lossy().contains(".git") {
                    let flake = path.join("flake.nix");
                    if flake.exists() {
                        let name = format!("{}/{}",
                            Path::new(root).file_name().map(|n| n.to_string_lossy()).unwrap_or_default(),
                            path.file_name().map(|n| n.to_string_lossy()).unwrap_or_default());
                        flakes.push((name, path.to_string_lossy().to_string()));
                    }
                }
            }
        }

        flakes
    }

    fn get_flake_metadata(path: &str) -> Result<serde_json::Value, String> {
        // First try `nix flake metadata` as JSON
        let output = Command::new("nix")
            .args(["flake", "metadata", "--json", path])
            .output()
            .map_err(|e| format!("nix not found: {}", e))?;

        if output.status.success() {
            serde_json::from_slice(&output.stdout).map_err(|e| format!("JSON: {}", e))
        } else {
            // Fallback: parse flake.nix directly
            let flake_nix = format!("{}/flake.nix", path);
            let content = std::fs::read_to_string(&flake_nix).map_err(|e| format!("read: {}", e))?;
            Ok(serde_json::json!({
                "description": content.lines().next().unwrap_or(""),
                "inputs_count": content.matches("url =").count(),
                "outputs_count": content.matches("packages.").count() + content.matches("apps.").count(),
                "raw": &content[..content.len().min(500)],
            }))
        }
    }

    fn get_build_status(path: &str, attr: &str) -> Result<String, String> {
        let output = Command::new("nix")
            .args(["build", "--no-link", "--json", &format!("{}#{}", path, attr)])
            .output()
            .map_err(|e| format!("nix build: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }
}

impl Plugin for NixTilePlugin {
    fn name(&self) -> &str { "nix" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Nix tile — flake introspection, build outputs, and derivation analysis" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");
        let root = input.extra.get("root").cloned().unwrap_or_else(|| "/home/mdupont/dasl".to_string());

        match action {
            "browse" => {
                let flakes = Self::discover_flakes(&root);
                let mut html = String::from("<h1>❄️ Nix Flakes</h1><div class='flake-grid' style='display:grid;grid-template-columns:repeat(auto-fill,minmax(350px,1fr));gap:10px'>");

                for (name, path) in &flakes {
                    let meta = Self::get_flake_metadata(path);
                    match meta {
                        Ok(m) => {
                            let desc = m.get("description").and_then(|d| d.as_str()).unwrap_or("?");
                            let inputs = m.get("inputs_count").and_then(|i| i.as_u64()).unwrap_or(0);
                            let outputs = m.get("outputs_count").and_then(|o| o.as_u64()).unwrap_or(0);
                            let raw = m.get("raw").and_then(|r| r.as_str()).unwrap_or("");

                            html.push_str(&format!(
                                r#"<div class="flake-card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:12px">
<h3 style="margin:0 0 4px 0;color:#7c3aed">{}</h3>
<div style="font-size:12px;color:#8b949e">{}</div>
<div style="margin:4px 0;font-size:11px">📥 {} inputs | 📤 {} outputs</div>
<pre style="font-size:10px;max-height:100px;overflow:auto;background:#0d1117;padding:6px;border-radius:4px">{}</pre>
<a href="?action=inspect&path={}" style="font-size:11px">🔍 Inspect</a>
</div>"#,
                                name, desc, inputs, outputs, &raw[..raw.len().min(200)], path
                            ));
                        }
                        Err(e) => {
                            html.push_str(&format!(
                                r#"<div class="flake-card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:12px">
<h3 style="margin:0">{}</h3>
<div style="color:#f85149;font-size:11px">⚠️ {}</div>
</div>"#, name, e));
                        }
                    }
                }
                html.push_str("</div>");
                html.push_str(&format!("<p style='font-size:12px;color:#8b949e'>{} flake.nix files found</p>", flakes.len()));
                map.insert("html".to_string(), html);
            }
            "inspect" => {
                let path = input.extra.get("path").cloned().unwrap_or_default();
                let meta = Self::get_flake_metadata(&path);

                match meta {
                    Ok(m) => {
                        let flake_nix = format!("{}/flake.nix", &path);
                        let content = std::fs::read_to_string(&flake_nix).unwrap_or_default();
                        let html = format!(
                            r#"<h1>❄️ Nix Flake: <code>{}</code></h1>
<pre style="background:#0d1117;padding:12px;border-radius:4px;max-height:600px;overflow:auto">{}</pre>
<pre style="background:#1f2937;padding:12px;border-radius:4px;margin-top:8px;max-height:300px;overflow:auto">{}</pre>
<a href="?action=browse">← Back</a>"#,
                            path,
                            serde_json::to_string_pretty(&m).unwrap_or_default(),
                            &content[..content.len().min(2000)]
                        );
                        map.insert("html".to_string(), html);
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "build" => {
                let path = input.extra.get("path").cloned().unwrap_or_default();
                let attr = input.extra.get("attr").cloned().unwrap_or_else(|| "default".to_string());
                match Self::get_build_status(&path, &attr) {
                    Ok(out) => { map.insert("build_output".to_string(), out); }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            _ => { map.insert("error".to_string(), format!("Unknown: {}", action)); }
        }
        Ok(map)
    }
}
