//! Nora tile — crate/package registry tile.
//! Surfaces Nora registry crates, versions, and metadata.

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct NoraPlugin;

impl NoraPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for NoraPlugin {
    fn name(&self) -> &str {
        "nora"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "Nora crate registry — browse, search, and pin crates"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let content = String::from_utf8_lossy(&input.content);
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("detect");
        let mut result = HashMap::new();

        match action {
            "detect" => {
                let is_nora = content.contains("registry = \"nora\"")
                    || content.contains("registry = \"nora\"")
                    || content.contains("nora");
                result.insert("is_nora".into(), is_nora.to_string());
                if is_nora {
                    result.insert(
                        "tile_html".into(),
                        render_nora_tile_html(&input.id, &input.extra.get("base_path").map(|s| s.as_str()).unwrap_or("")),
                    );
                }
            }
            "list" | "search" | "info" | "versions" => {
                result.insert("status".into(), "error".into());
                result.insert(
                    "output".into(),
                    "nora registry actions disabled: no shell-out allowed".to_string(),
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

pub fn render_nora_tile_html(paste_id: &str, base_path: &str) -> String {
    format!(
        r#"<div class="nora-tile" style="background:#1a1a2e;border:1px solid #0f0;border-radius:8px;padding:15px;margin:15px 0;font-family:monospace">
<h3 style="color:#0ff;margin:0 0 10px 0">📦 Nora Registry</h3>
<div style="display:flex;gap:10px;flex-wrap:wrap">
<button class="nora-btn" onclick="runNora('{0}','list')" style="background:#0f0;color:#000;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📋 List</button>
<button class="nora-btn" onclick="runNora('{0}','search')" style="background:#00aaff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">🔍 Search</button>
<button class="nora-btn" onclick="runNora('{0}','info')" style="background:#ff6600;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">ℹ️ Info</button>
<button class="nora-btn" onclick="runNora('{0}','versions')" style="background:#9933ff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📊 Versions</button>
</div>
<pre id="nora-output-{0}" style="background:#0d0d1a;padding:10px;border-radius:4px;margin-top:10px;max-height:300px;overflow:auto;font-size:12px;display:none;white-space:pre-wrap"></pre>
</div>
<script>
function runNora(id,action){{
  const prefix='{1}';
  const pre=document.getElementById('nora-output-'+id);
  if(!pre)return;
  pre.style.display='block';
  pre.innerHTML='⏳ Running...';
  fetch(prefix+'/plugin/nora/'+id,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{action:action}})}})
  .then(r=>r.json())
  .then(data=>{{pre.innerHTML=data.status==='ok'?'✅ OK\n'+data.output:'❌ Error\n'+data.output;}})
  .catch(err=>{{pre.innerHTML='❌ '+err;}});
}}
</script>"#,
        paste_id, base_path
    )
}