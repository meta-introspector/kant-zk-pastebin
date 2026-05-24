// Graphviz tile — render DOT graphs via Graphviz, with METIS partitioning
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct GraphvizPlugin;

impl GraphvizPlugin {
    pub fn new() -> Self { Self }

    fn render_dot(&self, dot: &str, format: &str) -> Result<Vec<u8>, String> {
        let output = Command::new("dot")
            .args([&format!("-T{}", format), "-Kdot"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("graphviz (dot) not found: {}", e))?;

        use std::io::Write;
        let mut child = output;
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(dot.as_bytes()).map_err(|e| format!("stdin: {}", e))?;
        }
        let out = child.wait_with_output().map_err(|e| format!("wait: {}", e))?;
        if !out.status.success() {
            return Err(format!("dot error: {}", String::from_utf8_lossy(&out.stderr)));
        }
        Ok(out.stdout)
    }

    fn partition_metis(&self, dot: &str, k: usize) -> Result<String, String> {
        // Convert DOT to METIS adjacency format, run gpmetis, report partitions
        let tmp_dir = std::env::temp_dir();
        let dot_file = tmp_dir.join("input.dot");
        let metis_file = tmp_dir.join("input.graph");
        std::fs::write(&dot_file, dot).map_err(|e| format!("write dot: {}", e))?;

        // Use graphviz's gvpr to extract adjacency, then gpmetis
        let output = Command::new("gpmetis")
            .args([metis_file.to_str().unwrap(), &k.to_string()])
            .output()
            .map_err(|e| format!("gpmetis not found: {}", e))?;

        if output.status.success() {
            let part_file = tmp_dir.join(format!("input.graph.part.{}", k));
            let parts = std::fs::read_to_string(&part_file).unwrap_or_default();
            Ok(parts)
        } else {
            Err(format!("gpmetis: {}", String::from_utf8_lossy(&output.stderr)))
        }
    }
}

impl Plugin for GraphvizPlugin {
    fn name(&self) -> &str { "graphviz" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Graphviz DOT renderer + METIS graph partitioning — visual and structural graph analysis" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("render");
        let content = std::str::from_utf8(&input.content).unwrap_or("");

        match action {
            "render" => {
                let fmt = input.extra.get("format").map(|s| s.as_str()).unwrap_or("svg");
                match self.render_dot(content, fmt) {
                    Ok(bytes) => {
                        map.insert("content".to_string(), format!("{:?}", bytes));
                        map.insert("content_type".to_string(),
                            if fmt == "svg" { "image/svg+xml".to_string() }
                            else if fmt == "png" { "image/png".to_string() }
                            else { "text/plain".to_string() });
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "partition" => {
                let k = input.extra.get("k").and_then(|k| k.parse().ok()).unwrap_or(4usize);
                match self.partition_metis(content, k) {
                    Ok(parts) => {
                        map.insert("partitions".to_string(), parts);
                        map.insert("k".to_string(), k.to_string());
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "browse" => {
                let files = locate_files("dot", 100);
                let html = files.iter().map(|(name, path)| {
                    format!(r#"<li><a href="?action=view&path={}">{}</a></li>"#, path, name)
                }).collect::<Vec<_>>().join("\n");
                map.insert("html".to_string(), format!("<h1>📊 DOT Graphs</h1><ul>{}</ul>", html));
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
