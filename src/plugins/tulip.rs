// Tulip tile — graph visualization with Tulip, for large-scale graph analysis
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct TulipPlugin;

impl TulipPlugin {
    pub fn new() -> Self { Self }

    fn render_tlp(&self, tlp: &str, layout: &str) -> Result<Vec<u8>, String> {
        let tmp_dir = std::env::temp_dir();
        let tlp_file = tmp_dir.join("input.tlp");
        let out_file = tmp_dir.join("output.svg");
        std::fs::write(&tlp_file, tlp).map_err(|e| format!("write: {}", e))?;

        let output = Command::new("tulip")
            .args([
                tlp_file.to_str().unwrap(),
                "--layout", layout,
                "--export", out_file.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| format!("tulip not found: {}", e))?;

        if output.status.success() {
            std::fs::read(&out_file).map_err(|e| format!("read output: {}", e))
        } else {
            Err(format!("tulip error: {}", String::from_utf8_lossy(&output.stderr)))
        }
    }

    fn analyze(&self, tlp: &str) -> Result<String, String> {
        let tmp_dir = std::env::temp_dir();
        let tlp_file = tmp_dir.join("input.tlp");
        std::fs::write(&tlp_file, tlp).map_err(|e| format!("write: {}", e))?;

        let output = Command::new("tulip")
            .args([
                tlp_file.to_str().unwrap(),
                "--statistics",
            ])
            .output()
            .map_err(|e| format!("tulip: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(format!("tulip stat error: {}", String::from_utf8_lossy(&output.stderr)))
        }
    }
}

impl Plugin for TulipPlugin {
    fn name(&self) -> &str { "tulip" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Tulip graph visualization tile — large-scale graph layout, analysis, and export" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");
        let content = std::str::from_utf8(&input.content).unwrap_or("");

        match action {
            "render" => {
                let layout = input.extra.get("layout").map(|s| s.as_str()).unwrap_or("FM^3(OpenGL)");
                match self.render_tlp(content, layout) {
                    Ok(svg) => {
                        map.insert("content".to_string(), format!("{:?}", svg));
                        map.insert("content_type".to_string(), "image/svg+xml".to_string());
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "analyze" => {
                match self.analyze(content) {
                    Ok(stats) => { map.insert("statistics".to_string(), stats); }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "browse" => {
                let files = locate_files("tlp", 100);
                let html = files.iter().map(|(name, path)| {
                    format!(r#"<li><a href="?action=view&path={}">{}</a></li>"#, path, name)
                }).collect::<Vec<_>>().join("\n");
                map.insert("html".to_string(), format!(
                    "<h1>🔗 Tulip Graphs</h1>
<p>Tulip graph visualization — large-scale graph analysis with multiple layout algorithms.</p>
<form><textarea name='tlp' rows='10' cols='80' placeholder='(nodes 0 1 2)(edges 0 1 1 2 2 0)'></textarea>
<br>layout: <select name='layout'><option>FM^3(OpenGL)</option><option>Tree</option>
<option>Circular</option><option>Kamada Kawai</option></select>
<button>Render</button> <button>Analyze</button></form>
<h3>Existing files:</h3><ul>{}</ul>", html));
            }
            _ => {
                map.insert("error".to_string(), format!("Unknown action: {}", action));
            }
        }
        Ok(map)
    }
}

fn locate_files(ext: &str, max: usize) -> Vec<(String, String)> {
    let output = std::process::Command::new("locate")
        .args(["-r", &format!("\\.{}$", ext)])
        .output().ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default();
    output.lines()
        .filter(|l| !l.is_empty())
        .take(max)
        .map(|l| {
            let name = std::path::Path::new(l).file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| l.to_string());
            (name, l.to_string())
        })
        .collect()
}
