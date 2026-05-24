// Zombie Driver 2 tile — analyze Rust source with Monster-64 CFT pipeline
// Wraps the zombie_driver2 CFT plugin to produce conformal field analysis
// of pasted Rust code, with Monster-64 barrel hash visualization.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct ZombiePlugin;

impl ZombiePlugin {
    pub fn new() -> Self { Self }

    /// Run zombie-cft analysis on Rust source
    fn analyze(&self, source: &str) -> Result<String, String> {
        let tmp_dir = std::env::temp_dir();
        let rs_file = tmp_dir.join("zombie_analyze.rs");
        std::fs::write(&rs_file, source).map_err(|e| format!("write source: {}", e))?;

        let output = Command::new("zombie-cft")
            .args(["analyze", rs_file.to_str().unwrap()])
            .output()
            .map_err(|e| format!("zombie-cft not found: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if stderr.contains("not found") || output.status.code() == Some(127) {
                // Fallback: do a basic syn parse analysis inline
                self.analyze_basic(source)
            } else {
                Err(format!("zombie-cft error: {}", stderr))
            }
        }
    }

    /// Basic fallback analysis using simple heuristics (no zombie-cft binary needed)
    fn analyze_basic(&self, source: &str) -> Result<String, String> {
        let mut result = serde_json::Map::new();
        let lines: Vec<&str> = source.lines().collect();

        // Count structural elements
        result.insert("lines".into(), serde_json::json!(lines.len()));
        result.insert("chars".into(), serde_json::json!(source.len()));
        result.insert("fns".into(), serde_json::json!(source.matches("fn ").count()));
        result.insert("structs".into(), serde_json::json!(source.matches("struct ").count()));
        result.insert("enums".into(), serde_json::json!(source.matches("enum ").count()));
        result.insert("impls".into(), serde_json::json!(source.matches("impl ").count()));
        result.insert("traits".into(), serde_json::json!(source.matches("trait ").count()));
        result.insert("unsafe".into(), serde_json::json!(source.matches("unsafe ").count()));
        result.insert("unsafe_blocks".into(), serde_json::json!(count_balanced(source, "unsafe {", "}")));

        // N-gram analysis (character level, up to prime 71)
        let mut ngram_totals = serde_json::Map::new();
        for n in [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31] {
            let mut seen = std::collections::HashSet::new();
            for w in source.as_bytes().windows(n) {
                seen.insert(w.to_vec());
            }
            ngram_totals.insert(n.to_string().into(), serde_json::json!(seen.len()));
        }
        result.insert("ngram_types".into(), serde_json::Value::Object(ngram_totals));

        Ok(serde_json::to_string_pretty(&result).unwrap_or_default())
    }

    /// Generate a PlantUML diagram of the code structure
    fn generate_diagram(&self, source: &str) -> Result<String, String> {
        let analysis = self.analyze_basic(source)?;
        let data: HashMap<String, serde_json::Value> =
            serde_json::from_str(&analysis).unwrap_or_default();

        let fns = data.get("fns").and_then(|v| v.as_u64()).unwrap_or(0);
        let structs = data.get("structs").and_then(|v| v.as_u64()).unwrap_or(0);
        let enums = data.get("enums").and_then(|v| v.as_u64()).unwrap_or(0);
        let impls = data.get("impls").and_then(|v| v.as_u64()).unwrap_or(0);

        // Extract function names for a call graph
        let mut call_graph = String::new();
        for line in source.lines() {
            let trimmed = line.trim();
            if let Some(name) = trimmed.strip_prefix("fn ")
                .and_then(|s| s.split(|c: char| c == '(' || c == '<').next())
                .map(|s| s.trim())
            {
                // Find calls within this function
                let mut calls = Vec::new();
                for call_line in source.lines() {
                    if let Some(called) = call_line.trim().strip_prefix("fn ")
                        .and_then(|s| s.split(|c: char| c == '(' || c == '<').next())
                        .map(|s| s.trim())
                    {
                        if called != name && source.contains(&format!("{}(", called)) {
                            calls.push(called);
                        }
                    }
                }
                for c in &calls {
                    call_graph.push_str(&format!("  {} -> {}\n", name, c));
                }
            }
        }

        Ok(format!(
            "@startuml\n\
             title Rust Analysis: {} fns, {} structs, {} enums, {} impls\n\
             \n\
             ' Monster-64 CFT Analysis\n\
             \n\
             {}\n\
             @enduml",
            fns, structs, enums, impls, call_graph
        ))
    }
}

/// Count balanced occurrences of open/close pairs
fn count_balanced(source: &str, open: &str, close: &str) -> usize {
    let mut count = 0;
    let mut depth = 0;
    let mut i = 0;
    let bytes = source.as_bytes();
    while i < source.len() {
        if source[i..].starts_with(open) {
            depth += 1;
            i += open.len();
        } else if source[i..].starts_with(close) && depth > 0 {
            depth -= 1;
            if depth == 0 {
                count += 1;
            }
            i += close.len();
        } else {
            i += 1;
        }
    }
    count
}

impl Plugin for ZombiePlugin {
    fn name(&self) -> &str { "zombie" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Zombie Driver 2 — Rust source CFT analysis with Monster-64 barrel hash and n-gram visualization" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");
        let content = std::str::from_utf8(&input.content).unwrap_or("");

        match action {
            "analyze" => {
                match self.analyze(content) {
                    Ok(json) => {
                        map.insert("content".to_string(), json);
                        map.insert("content_type".to_string(), "application/json".to_string());
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "diagram" => {
                match self.generate_diagram(content) {
                    Ok(puml) => {
                        map.insert("content".to_string(), puml);
                        map.insert("content_type".to_string(), "text/vnd.plantuml".to_string());
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "browse" => {
                let files = locate_files("rs", 100);
                let html = files.iter().map(|(name, path)| {
                    format!(r#"<li><a href="?action=view&path={}">{}</a>"#, path, name)
                }).collect::<Vec<_>>().join("\n");

                map.insert("html".to_string(), format!(
                    "<h1>🧟 Zombie Driver 2</h1>
<p>Monster-64 Conformal Field Theory analysis for Rust source code.</p>
<p>Paste Rust code below or browse existing files:</p>
<form>
<textarea name='code' rows='12' cols='80' placeholder='fn main() {{\n  println!(\"Hello, Monster-64!\");\n}}'></textarea>
<br>
<button onclick=\"analyzeZombie(this,'analyze')\">🧪 Analyze CFT</button>
<button onclick=\"analyzeZombie(this,'diagram')\">📐 Generate Diagram</button>
</form>
<div id='zombie-output'></div>
<script>
function analyzeZombie(btn, action) {{
  btn.disabled=true; btn.textContent='⏳...';
  const code=btn.parentElement.querySelector('textarea').value;
  const out=document.getElementById('zombie-output');
  fetch('/plugin/zombie?action='+action,{{method:'POST',body:code}})
    .then(r=>r.text()).then(h=>{{out.innerHTML='<pre>'+h+'</pre>';btn.textContent='✅ Done';}})
    .catch(e=>{{out.textContent='Error: '+e;btn.textContent='❌ Failed';}});
}}
</script>
<h3>Existing files:</h3><ul>{}</ul>", html));
            }
            "view" => {
                let path = input.extra.get("path").cloned().unwrap_or_default();
                match std::fs::read_to_string(&path) {
                    Ok(code) => {
                        let analysis = self.analyze_basic(&code).unwrap_or_default();
                        map.insert("content".to_string(), format!(
                            "// File: {}\n// Analysis:\n{}\n\n// Source:\n{}", path, analysis, code));
                        map.insert("content_type".to_string(), "text/plain".to_string());
                    }
                    Err(e) => { map.insert("error".to_string(), format!("File not found: {}", e)); }
                }
            }
            _ => {
                map.insert("error".to_string(), format!("Unknown action: {}", action));
            }
        }
        Ok(map)
    }
}

fn locate_files(ext: &str, max: usize) -> Vec<(String, String)> {
    let output = Command::new("locate")
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
