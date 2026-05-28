// Pipelight plugin — interactive pipeline tile for the pastebin.
//
// When pasted content looks like a pipelight config (TOML/TS/YAML/HCL with
// pipeline definitions) the paste view renders an interactive tile with
// Run / Status / Logs / List buttons that invoke `pipelight` CLI commands.
//
// Environment:
//   PIPELIGHT_CMD — path to the pipelight binary (default: pipelight)

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/// Returns true if `content` looks like a pipelight pipeline definition.
pub fn is_pipelight_config(content: &str) -> bool {
    let trimmed = content.trim();
    // TOML: [[pipelines]] header
    if trimmed.contains("[[pipelines]]") {
        return true;
    }
    // TOML: [pipelines.] section (alternate single-section style)
    if trimmed.contains("[pipelines]") {
        return true;
    }
    // YAML: pipelines: at root
    if trimmed.starts_with("pipelines:") {
        return true;
    }
    // HCL: pipelines { block
    if trimmed.contains("pipelines {") {
        return true;
    }
    // TypeScript: import/export with pipeline references
    if trimmed.contains("pipelight")
        && (trimmed.contains("export default") || trimmed.contains("pipeline"))
    {
        return true;
    }
    false
}

// ---------------------------------------------------------------------------
// Tile HTML generation
// ---------------------------------------------------------------------------

/// Render the interactive tile HTML snippet for a pipelight pipeline config.
/// `paste_id` is used for the plugin API endpoint URL.
pub fn render_tile_html(paste_id: &str, base_path: &str) -> String {
    let escaped_id = paste_id.replace('"', "&quot;");
    let escaped_base = base_path.trim_end_matches('/');
    format!(
        r#"<div class="pipelight-tile" style="background:#1a1a2e;border:1px solid #0f0;border-radius:8px;padding:15px;margin:15px 0;font-family:monospace">
<h3 style="color:#0ff;margin:0 0 10px 0">🔷 Pipelight Pipeline</h3>
<div style="display:flex;gap:10px;flex-wrap:wrap">
<button class="pipelight-btn" onclick="runPipelight('{0}','list')" style="background:#0f0;color:#000;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📋 List</button>
<button class="pipelight-btn" onclick="runPipelight('{0}','status')" style="background:#00aaff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📊 Status</button>
<button class="pipelight-btn" onclick="runPipelight('{0}','run')" style="background:#ff6600;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">▶ Run</button>
<button class="pipelight-btn" onclick="runPipelight('{0}','logs')" style="background:#9933ff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📜 Logs</button>
</div>
<pre id="pipelight-output-{0}" style="background:#0d0d1a;padding:10px;border-radius:4px;margin-top:10px;max-height:300px;overflow:auto;font-size:12px;display:none;white-space:pre-wrap"></pre>
</div>
<script>
function runPipelight(id,action){{
  const prefix='{1}';
  const pre=document.getElementById('pipelight-output-'+id);
  if(!pre)return;
  pre.style.display='block';
  pre.innerHTML='⏳ Running...';
  fetch(prefix+'/plugin/pipelight/'+id,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{action:action}})}})
  .then(r=>r.json())
  .then(data=>{{pre.innerHTML=data.status==='ok'?'✅ OK\n'+data.output:'❌ Error\n'+data.output;}})
  .catch(err=>{{pre.innerHTML='❌ '+err;}});
}}
</script>"#,
        escaped_id, escaped_base
    )
}

// ---------------------------------------------------------------------------
// Pipelight CLI wrapper
// ---------------------------------------------------------------------------

fn pipelight_bin() -> String {
    std::env::var("PIPELIGHT_CMD").unwrap_or_else(|_| "pipelight".to_string())
}

fn run_pipelight(args: &[&str]) -> Result<String, String> {
    let bin = pipelight_bin();
    let output = Command::new(&bin)
        .args(args)
        .output()
        .map_err(|e| {
            format!(
                "cannot execute `{}`: {}. Is pipelight installed?",
                bin, e
            )
        })?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if output.status.success() {
        Ok(stdout)
    } else {
        Err(format!("exit {}:\n{}", output.status, stderr))
    }
}

// ---------------------------------------------------------------------------
// Plugin implementation
// ---------------------------------------------------------------------------

pub struct PipelightPlugin;

impl PipelightPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for PipelightPlugin {
    fn name(&self) -> &str {
        "pipelight"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "Interactive pipelight pipeline tile — list, status, logs, run"
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
                let is_pipelight = is_pipelight_config(&content);
                result.insert("is_pipelight".into(), is_pipelight.to_string());
                if is_pipelight {
                    let bp = input.extra.get("base_path").map(|s| s.as_str()).unwrap_or("");
                    result.insert("tile_html".into(), render_tile_html(&input.id, bp));
                }
            }
            "list" => match run_pipelight(&["ls"]) {
                Ok(output) => {
                    result.insert("output".into(), output);
                    result.insert("status".into(), "ok".into());
                }
                Err(e) => {
                    result.insert("output".into(), e);
                    result.insert("status".into(), "error".into());
                }
            },
            "status" => match run_pipelight(&["status"]) {
                Ok(output) => {
                    result.insert("output".into(), output);
                    result.insert("status".into(), "ok".into());
                }
                Err(e) => {
                    result.insert("output".into(), e);
                    result.insert("status".into(), "error".into());
                }
            },
            "logs" => {
                let mut args = vec!["logs"];
                if let Some(pipe) = input.extra.get("pipe") {
                    args.push(pipe);
                }
                match run_pipelight(&args) {
                    Ok(output) => {
                        result.insert("output".into(), output);
                        result.insert("status".into(), "ok".into());
                    }
                    Err(e) => {
                        result.insert("output".into(), e);
                        result.insert("status".into(), "error".into());
                    }
                }
            }
            "run" => {
                let pipe = input.extra.get("pipe").cloned().unwrap_or_default();
                let mut args = vec!["run"];
                if !pipe.is_empty() {
                    args.push(&pipe);
                }
                match run_pipelight(&args) {
                    Ok(output) => {
                        result.insert("output".into(), output);
                        result.insert("status".into(), "ok".into());
                    }
                    Err(e) => {
                        result.insert("output".into(), e);
                        result.insert("status".into(), "error".into());
                    }
                }
            }
            other => {
                result.insert(
                    "error".into(),
                    format!("unknown action: {}", other),
                );
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
    fn test_detect_toml_pipelines() {
        let content = "[[pipelines]]\nname = \"test\"\n";
        assert!(is_pipelight_config(content));
    }

    #[test]
    fn test_detect_yaml_pipelines() {
        let content = "pipelines:\n  - name: test\n    steps: []\n";
        assert!(is_pipelight_config(content));
    }

    #[test]
    fn test_detect_hcl_pipelines() {
        let content = "pipelines {\n  name = \"test\"\n}";
        assert!(is_pipelight_config(content));
    }

    #[test]
    fn test_detect_ts_pipelight() {
        let content = r#"import type { Config } from "https://deno.land/x/pipelight/mod.ts";
const config: Config = { pipelines: [ { name: "test", steps: [] } ] };
export default config;"#;
        assert!(is_pipelight_config(content));
    }

    #[test]
    fn test_detect_plain_text() {
        let content = "hello world\nthis is not a pipeline";
        assert!(!is_pipelight_config(content));
    }

    #[test]
    fn test_render_tile_html() {
        let html = render_tile_html("test-123", "/pastebin");
        assert!(html.contains("pipelight-tile"));
        assert!(html.contains("test-123"));
        assert!(html.contains("prefix+'/plugin/pipelight/'+id"));
        assert!(html.contains("▶ Run"));
        assert!(html.contains("📋 List"));
        assert!(html.contains("📊 Status"));
        assert!(html.contains("📜 Logs"));
    }
}
