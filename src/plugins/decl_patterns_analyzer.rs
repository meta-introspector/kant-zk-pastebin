//! Decl Patterns Analyzer plugin — cross-project AST pattern matching
//! Runs `decl-patterns` binary across projects and renders isomorphic code analysis tiles.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct DeclPatternsAnalyzerPlugin;

impl DeclPatternsAnalyzerPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for DeclPatternsAnalyzerPlugin {
    fn name(&self) -> &str {
        "decl_patterns_analyzer"
    }

    fn version(&self) -> &str {
        "0.1.0"
    }

    fn description(&self) -> &str {
        "Cross-project AST pattern matcher: compares projects by their split decls to find isomorphic crate usage patterns and structural group theory equivalences"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input
            .extra
            .get("action")
            .map(|s| s.as_str())
            .unwrap_or("help");

        match action {
            "analyze" => {
                let content = String::from_utf8_lossy(&input.content).to_string();
                match run_analysis(&content) {
                    Ok(result) => {
                        let html = format!(
                            r#"<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Decl Patterns Analysis</title>
<link rel="stylesheet" href="https://unpkg.com/@blueprintjs/core@5/lib/css/blueprint.css">
<style>
body {{ background: #1c2127; color: #f6f7f9; font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }}
.card {{ background: #252a31; border-radius: 8px; padding: 16px; margin: 12px 0; }}
h2 {{ color: #8abbff; margin-bottom: 16px; }}
.isomorphic {{ border-left: 4px solid #238551; padding-left: 12px; margin: 8px 0; }}
.unique {{ border-left: 4px solid #8a9ba8; padding-left: 12px; margin: 8px 0; }}
.badge {{ display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 12px; margin-right: 4px; }}
.badge-purple {{ background: #634dbf; color: #fff; }}
.badge-green {{ background: #238551; color: #fff; }}
.badge-blue {{ background: #2d72d2; color: #fff; }}
pre {{ background: #1c2127; padding: 8px; border-radius: 4px; overflow-x: auto; font-size: 12px; }}
table {{ width: 100%; border-collapse: collapse; margin: 8px 0; }}
th, td {{ padding: 8px 12px; text-align: left; border-bottom: 1px solid #3b4252; }}
th {{ color: #abb3bf; }}
</style></head><body>
<h2>🧬 Cross-Project Pattern Analysis</h2>
{}
<p><a href="/plugin/decl_patterns_analyzer">&larr; Back to analyzer</a></p>
</body></html>"#,
                            result
                        );
                        map.insert("html".to_string(), html);
                        map.insert(
                            "content_type".to_string(),
                            "text/html; charset=utf-8".to_string(),
                        );
                        map.insert("json".to_string(), serde_json::to_string(&result).unwrap_or_default());
                    }
                    Err(e) => {
                        map.insert(
                    "error".to_string(),
                    format!("Analysis failed: {}", e),
                );
                    }
                }
            }
            "help" | _ => {
                map.insert("html".to_string(), HELP_HTML.to_string());
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            }
        }
        Ok(map)
    }
}

fn run_analysis(content: &str) -> Result<String, String> {
    let lines: Vec<&str> = content.lines().collect();
    if lines.is_empty() || (lines.len() == 1 && lines[0].trim().is_empty()) {
        // Return demo analysis
        return Ok(demo_analysis_html());
    }

    // Parse the form: "project1=/path/to/decls1\nproject2=/path/to/decls2"
    let mut args = Vec::new();
    for line in lines {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some((name, path)) = trimmed.split_once('=') {
            args.push("--decls-dir".to_string());
            args.push(format!("{}={}", name.trim(), path.trim()));
        }
    }

    if args.len() < 2 {
        return Err("Need at least 2 projects (format: name=/path/to/decls)".to_string());
    }

    // Build the decl-patterns command
    let mut cmd = std::process::Command::new("cargo");
    cmd.arg("run")
        .arg("--package")
        .arg("decl-splitter")
        .arg("--bin")
        .arg("decl-patterns")
        .arg("--");
    for arg in &args {
        cmd.arg(arg);
    }

    let output = cmd.output().map_err(|e| format!("Failed to run decl-patterns: {}", e))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("decl-patterns failed: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let result = if stdout.trim().starts_with('{') || stdout.trim().starts_with('[') {
        serde_json::from_str::<serde_json::Value>(&stdout)
            .map(|v| format!("<pre>{}</pre>", serde_json::to_string_pretty(&v).unwrap_or(v.to_string())))
            .unwrap_or_else(|_| format!("<pre>{}</pre>", html_escape(&stdout)))
    } else {
        format!("<pre>{}</pre>", html_escape(&stdout))
    };

    Ok(result)
}

fn demo_analysis_html() -> String {
    r#"<div class="card">
  <h3>📊 Isomorphic Crate Usage — 4 Projects</h3>
  <p>Grouped by structural equivalence classes. Projects in the same group share identical crate usage patterns.</p>
</div>

<div class="card">
  <h3>🔬 Equivalence Class 1: serde + tokio + anyhow pattern</h3>
  <div class="isomorphic">forge_domain ← → forge_main  <span class="badge badge-green">isomorphic</span></div>
  <div class="isomorphic">forge_domain ← → forge_app  <span class="badge badge-green">isomorphic</span></div>
  <div class="unique">pi_agent  <span class="badge badge-blue">structurally unique</span></div>
  <p>both forge projects use <code>serde = { features = ["derive"] }</code> + <code>tokio = { features = ["full"] }</code> + <code>anyhow</code> with identical feature flags.
     pi_agent uses <code>serde</code> but without derive, and <code>tokio</code> is optional.</p>
</div>

<div class="card">
  <h3>📊 Crates Used By All Projects</h3>
  <table>
    <tr><th>Crate</th><th>Forge Domain</th><th>Forge Main</th><th>Forge App</th><th>Pi Agent</th><th>Can Unify?</th></tr>
    <tr><td>serde</td><td>✅ derive</td><td>✅ derive</td><td>✅ derive</td><td>✅</td><td>🔀 yes</td></tr>
    <tr><td>anyhow</td><td>✅</td><td>✅</td><td>✅</td><td>✅</td><td>🔀 yes</td></tr>
    <tr><td>tokio</td><td>✅ full</td><td>✅ full</td><td>✅ full</td><td>❌ optional</td><td>⚠️ partial</td></tr>
    <tr><td>chrono</td><td>✅</td><td>✅</td><td>❌</td><td>✅ serde</td><td>⚠️ partial</td></tr>
    <tr><td>reqwest</td><td>❌</td><td>✅</td><td>✅</td><td>❌</td><td>🔀 forge only</td></tr>
  </table>
</div>

<div class="card">
  <h3>🔗 Group Theory: Crate Usage as Permutation Groups</h3>
  <p>Each project's crate set forms a <b>signature vector</b> in ℤ₂ⁿ. The intersection (AND) of all signaures
     gives <b>Group Orbit A</b> = {serde, anyhow} — crate usages constant across all agents.
     <b>Group Orbit B</b> = {tokio, chrono} — usages that vary but share common subgroups.</p>
  <table>
    <tr><th>Orbit</th><th>Crates</th><th>Coset (forge)</th><th>Coset (pi)</th><th>Fixator</th></tr>
    <tr><td>A</td><td>serde, anyhow</td><td>⟦I⟧</td><td>⟦I⟧</td><td>all</td></tr>
    <tr><td>B</td><td>tokio, chrono</td><td>⟦full, serde⟧</td><td>⟦optional, none⟧</td><td>𝟙</td></tr>
  </table>
</div>"#.to_string()
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

const HELP_HTML: &str = r#"<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Decl Patterns Analyzer</title>
<link rel="stylesheet" href="https://unpkg.com/@blueprintjs/core@5/lib/css/blueprint.css">
<style>
body { background: #1c2127; color: #f6f7f9; font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; margin: 0 auto; max-width: 900px; }
.card { background: #252a31; border-radius: 8px; padding: 20px; margin: 16px 0; }
h2 { color: #8abbff; }
textarea { width: 100%; font-family: monospace; font-size: 13px; background: #1c2127; color: #f6f7f9; border: 1px solid #3b4252; border-radius: 4px; padding: 8px; }
input, button { font-family: inherit; }
label { display: block; margin: 12px 0 4px; color: #abb3bf; }
code { background: #1c2127; padding: 1px 4px; border-radius: 3px; }
</style></head><body>
<h2>🧬 Decl Patterns Analyzer</h2>
<div class="card">
  <p>Compare multiple Rust projects by their split declaration ASTs to find isomorphic patterns,
     overlapping crate usage, and structural group theory equivalences.</p>
</div>

<div class="card">
  <h3>Example — Compare 4 agent frameworks</h3>
  <pre style="background:#1c2127;padding:12px;border-radius:4px;font-size:13px">forge_domain=/mnt/data1/time-2026/05-may/15/forgecode/crates/forge_domain/src/decls
forge_main=/mnt/data1/time-2026/05-may/15/forgecode/crates/forge_main/src/decls
forge_app=/mnt/data1/time-2026/05-may/15/forgecode/crates/forge_app/src/decls
pi_agent=/mnt/data1/time-2026/04-april/03/pi_agent_rust/pi/src/decls</pre>
  <form method="POST" action="/plugin/decl_patterns_analyzer">
    <input type="hidden" name="action" value="analyze">
    <label>Enter project=path lines:</label>
    <textarea name="body" rows="6" placeholder="project1=/path/to/decls1&#10;project2=/path/to/decls2"></textarea>
    <button type="submit" style="margin-top:12px;background:#2d72d2;color:#fff;border:none;padding:8px 20px;border-radius:4px;cursor:pointer;">Run Analysis</button>
  </form>
</div>

<div class="card">
  <h3>How It Works</h3>
  <ol>
    <li>Each project's <code>decls/</code> directory is scanned for split declaration files</li>
    <li>Each decl file is parsed by <code>syn</code> to extract use statements, type references, and defines</li>
    <li>Crate usage patterns are grouped by <b>structural equivalence</b> (same crate + same feature flags)</li>
    <li>Group orbits computed as subspaces of the crate-signature vector space</li>
    <li>Isomorphic groups are highlighted — these are candidates for crate unification</li>
  </ol>
</div>
</body></html>"#;
