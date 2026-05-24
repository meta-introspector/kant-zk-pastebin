// ZOS Server tile — plugin system browser and ELF analysis
// Integrates with ~/zos-server to provide binary analysis,
// plugin registry browsing, and system monitoring via the pastebin.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct ZosPlugin;

impl ZosPlugin {
    pub fn new() -> Self { Self }

    /// Browse available ZOS plugins
    fn list_plugins() -> Vec<String> {
        let zos_dir = std::path::Path::new("/home/mdupont/zos-server/src/plugins");
        let mut plugins = Vec::new();
        if let Ok(entries) = std::fs::read_dir(zos_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.ends_with(".rs") && !name.starts_with("mod") {
                    plugins.push(name.replace(".rs", ""));
                }
            }
        }
        // Also check extra_plugins
        let extra_dir = std::path::Path::new("/home/mdupont/zos-server/src/extra_plugins");
        if let Ok(entries) = std::fs::read_dir(extra_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.ends_with(".rs") && !name.starts_with("mod") {
                    plugins.push(format!("extra/{}", name.replace(".rs", "")));
                }
            }
        }
        plugins.sort();
        plugins
    }

    /// Get plugin description from its source
    fn get_plugin_info(name: &str) -> Option<String> {
        let paths = [
            format!("/home/mdupont/zos-server/src/plugins/{}.rs", name),
            format!("/home/mdupont/zos-server/src/extra_plugins/{}.rs", name.trim_start_matches("extra/")),
        ];
        for path in &paths {
            if let Ok(content) = std::fs::read_to_string(path) {
                // Extract doc comments
                let doc: Vec<&str> = content.lines()
                    .take(30)
                    .filter(|l| l.trim().starts_with("//"))
                    .map(|l| l.trim_start_matches("//").trim())
                    .take(10)
                    .collect();
                if !doc.is_empty() {
                    return Some(doc.join("\n"));
                }
            }
        }
        None
    }

    /// Analyze an ELF binary (using goblin-like output from the ZOS server)
    fn analyze_elf(path: &str) -> Result<String, String> {
        // Try using the zos_server binary if available
        if let Ok(output) = Command::new("zos_server")
            .args(["analyze", path])
            .output()
        {
            if output.status.success() {
                return Ok(String::from_utf8_lossy(&output.stdout).to_string());
            }
        }

        // Fallback: basic file analysis
        let metadata = std::fs::metadata(path).map_err(|e| format!("file error: {}", e))?;
        let size = metadata.len();
        
        // Read first bytes to determine ELF
        let data = std::fs::read(path).map_err(|e| format!("read error: {}", e))?;
        let is_elf = data.starts_with(&[0x7f, 0x45, 0x4c, 0x46]);
        
        // Count sections roughly
        let section_count = if is_elf {
            data.windows(8).filter(|w| {
                w[0] == 0x2e && (w[1] == 0x74 || w[1] == 0x64 || w[1] == 0x72)
            }).count()
        } else {
            0
        };

        // DA51-style orbifold coords (from zos plugin_loader.rs pattern)
        let n = (size % 71) as u8;
        let m = ((size / 1000) % 59) as u8;
        let c = (section_count as u64 % 47) as u8;

        Ok(serde_json::to_string_pretty(&serde_json::json!({
            "file": path,
            "size_bytes": size,
            "is_elf": is_elf,
            "sections_estimate": section_count,
            "da51_orbifold": {
                "n": n,
                "m": m,
                "c": c,
                "dasl": format!("DA51:{:02x}{:02x}{:02x}", n, m, c),
            },
            "plugins_count": Self::list_plugins().len(),
        })).unwrap_or_default())
    }
}

impl Plugin for ZosPlugin {
    fn name(&self) -> &str { "zos" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "ZOS Server — binary analysis, plugin browser, and DA51 orbifold coordinate system" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");

        match action {
            "browse" => {
                let plugins = Self::list_plugins();
                let mut html = String::from(
                    "<h1>⚡ ZOS Server</h1>
<p>Plugin browser for the Zero Operating System server.</p>
<style>
.plugin-grid { display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:8px; }
.plugin-card { background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:12px; }
.plugin-card h3 { margin:0 0 4px 0;color:#58a6ff;font-size:14px; }
.plugin-card p { margin:0;color:#8b949e;font-size:12px; }
.plugin-card code { font-size:11px; }
</style>
<div class='plugin-grid'>"
                );

                for p in plugins.iter().take(50) {
                    let info = Self::get_plugin_info(p).unwrap_or_default();
                    let short_desc = info.lines().next().unwrap_or("(no docs)");
                    html.push_str(&format!(
                        r#"<div class="plugin-card">
<h3>{}</h3>
<p>{}</p>
<code>zos</code>
</div>"#, p, short_desc
                    ));
                }
                html.push_str("</div>");
                if plugins.len() > 50 {
                    html.push_str(&format!("<p>... and {} more</p>", plugins.len() - 50));
                }
                map.insert("html".to_string(), html);
            }
            "plugins" => {
                let plugins = Self::list_plugins();
                map.insert("count".to_string(), plugins.len().to_string());
                map.insert("plugins".to_string(), plugins.join("\n"));
            }
            "plugin_info" => {
                let name = input.extra.get("name").cloned().unwrap_or_default();
                let info = Self::get_plugin_info(&name).unwrap_or_else(|| "Plugin not found".to_string());
                map.insert("info".to_string(), info);
            }
            "analyze" => {
                let path = input.extra.get("path").cloned().unwrap_or_default();
                match Self::analyze_elf(&path) {
                    Ok(json) => {
                        map.insert("content".to_string(), json);
                        map.insert("content_type".to_string(), "application/json".to_string());
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            _ => {
                map.insert("error".to_string(), format!("Unknown action: {}", action));
            }
        }
        Ok(map)
    }
}
