// Cargo tile — Cargo workspace introspection, dependency graphs, crate analysis
// Each Cargo.toml becomes a tile showing its workspace structure, deps, and metadata.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;
use std::path::Path;

pub struct CargoTilePlugin;

impl CargoTilePlugin {
    pub fn new() -> Self { Self }

    fn get_metadata(path: &str) -> Result<serde_json::Value, String> {
        let output = Command::new("cargo")
            .args(["metadata", "--no-deps", "--format-version", "1", "--manifest-path", &format!("{}/Cargo.toml", path)])
            .output()
            .map_err(|e| format!("cargo metadata failed: {}", e))?;

        if output.status.success() {
            serde_json::from_slice(&output.stdout).map_err(|e| format!("JSON parse: {}", e))
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    fn discover_manifests(root: &str) -> Vec<(String, String)> {
        let mut manifests = Vec::new();

        // Check root Cargo.toml
        let root_toml = format!("{}/Cargo.toml", root);
        if Path::new(&root_toml).exists() {
            let name = Path::new(root).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            manifests.push((name, root.to_string()));
        }

        // Walk up to 2 levels for Cargo.toml files (but skip target/ and .git/)
        if let Ok(entries) = std::fs::read_dir(root) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() && !path.to_string_lossy().contains("target") && !path.to_string_lossy().contains(".git") {
                    let cargo = path.join("Cargo.toml");
                    if cargo.exists() {
                        let name = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                        manifests.push((format!("{}/{}", Path::new(root).file_name().map(|n| n.to_string_lossy()).unwrap_or_default(), name), path.to_string_lossy().to_string()));
                    }
                }
            }
        }

        manifests
    }
}

impl Plugin for CargoTilePlugin {
    fn name(&self) -> &str { "cargo" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Cargo tile — workspace introspection, dependency graphs, and crate analysis" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");
        let root = input.extra.get("root").cloned().unwrap_or_else(|| "/home/mdupont/dasl".to_string());

        match action {
            "browse" => {
                let manifests = Self::discover_manifests(&root);
                let mut html = String::from("<h1>📦 Cargo Workspaces</h1><div class='cargo-grid' style='display:grid;grid-template-columns:repeat(auto-fill,minmax(350px,1fr));gap:10px'>");

                for (name, path) in &manifests {
                    let meta = Self::get_metadata(path);
                    let (pkg_name, deps, version, workspace) = match &meta {
                        Ok(m) => {
                            let pkg = m["packages"].as_array().and_then(|a| a.first());
                            let pn = pkg.and_then(|p| p["name"].as_str()).unwrap_or(name);
                            let pv = pkg.and_then(|p| p["version"].as_str()).unwrap_or("?");
                            let ws = m.get("workspace_root").and_then(|w| w.as_str()).map(|w| "📁 workspace").unwrap_or("");
                            let work = m.get("workspace_members")
                                .and_then(|m| m.as_array())
                                .map(|a| a.len())
                                .unwrap_or(0);
                            let dep_count = pkg.and_then(|p| p["dependencies"].as_array()).map(|a| a.len()).unwrap_or(0);
                            (pn.to_string(), dep_count, pv.to_string(), if work > 0 { format!("📁 {} members", work) } else { "📄 crate".to_string() })
                        }
                        Err(_) => (name.clone(), 0, "?".to_string(), "⚠️  metadata error".to_string()),
                    };

                    html.push_str(&format!(
                        r#"<div class="cargo-card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:12px">
<h3 style="margin:0 0 4px 0;color:#58a6ff">{}</h3>
<div style="font-size:12px;color:#8b949e">{}</div>
<div style="margin:4px 0"><code style="font-size:11px">v{}</code></div>
<div style="font-size:11px">📦 {} deps | {}</div>
<div style="font-size:10px;color:#484f58;margin-top:4px">{}</div>
<a href="?action=inspect&path={}" style="font-size:11px">🔍 Inspect</a>
</div>"#,
                        pkg_name, path, version, deps, workspace, path
                    ));
                }
                html.push_str("</div>");
                html.push_str(&format!("<p style='font-size:12px;color:#8b949e'>{} Cargo manifests found</p>", manifests.len()));
                map.insert("html".to_string(), html);
            }
            "inspect" => {
                let path = input.extra.get("path").cloned().unwrap_or_default();
                let meta = Self::get_metadata(&path);

                match meta {
                    Ok(m) => {
                        let packages = m["packages"].as_array().cloned().unwrap_or_default();
                        let mut html = format!("<h1>📦 Cargo Inspect: <code>{}</code></h1>", path);

                        for pkg in &packages {
                            let name = pkg["name"].as_str().unwrap_or("?");
                            let version = pkg["version"].as_str().unwrap_or("?");
                            let deps = pkg["dependencies"].as_array().cloned().unwrap_or_default();
                            let features = pkg["features"].as_object().cloned().unwrap_or_default();

                            html.push_str(&format!(
                                r#"<div class="pkg" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:12px;margin:8px 0">
<h3 style="margin:0">{} <code>v{}</code></h3>
<h4>Dependencies ({}):</h4><ul style="font-size:12px">{}</ul>
<h4>Features ({}):</h4><ul style="font-size:12px">{}</ul>
</div>"#,
                                name, version,
                                deps.len(),
                                deps.iter().map(|d| {
                                    let dn = d["name"].as_str().unwrap_or("?");
                                    let dv = d["req"].as_str().unwrap_or("*");
                                    format!("<li><code>{}</code> = \"{}\"</li>", dn, dv)
                                }).collect::<Vec<_>>().join(""),
                                features.len(),
                                features.keys().map(|k| format!("<li><code>{}</code></li>", k)).collect::<Vec<_>>().join(""),
                            ));
                        }
                        html.push_str("<a href=\"?action=browse\">← Back</a>");
                        map.insert("html".to_string(), html);
                    }
                    Err(e) => {
                        map.insert("error".to_string(), format!("cargo metadata failed: {}", e));
                    }
                }
            }
            _ => { map.insert("error".to_string(), format!("Unknown: {}", action)); }
        }
        Ok(map)
    }
}
