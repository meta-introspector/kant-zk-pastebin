//! Pipelite tile — CI/CD pipeline tile.
//! Surfaces CI/CD pipelines, stages, jobs, and status.

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct PipelitePlugin;

impl PipelitePlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for PipelitePlugin {
    fn name(&self) -> &str {
        "pipelite"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "CI/CD pipeline — stages, jobs, and status display"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let content = String::from_utf8_lossy(&input.content);
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("detect");
        let mut result = HashMap::new();

        match action {
            "detect" => {
                let is_pipelite = content.contains("[[pipelines]]")
                    || content.contains("[pipelines]")
                    || content.contains("pipelite")
                    || content.contains("pipeline:");
                result.insert("is_pipelite".into(), is_pipelite.to_string());
                if is_pipelite {
                    result.insert(
                        "tile_html".into(),
                        render_pipelite_tile_html(&input.id, &input.extra.get("base_path").map(|s| s.as_str()).unwrap_or("")),
                    );
                }
            }
            "list" | "status" | "jobs" | "stages" => {
                result.insert("status".into(), "error".into());
                result.insert(
                    "output".into(),
                    "pipelite CLI actions disabled: no shell-out allowed".to_string(),
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

pub fn render_pipelite_tile_html(paste_id: &str, base_path: &str) -> String {
    format!(
        r#"<div class="pipelite-tile" style="background:#1a1a2e;border:1px solid #9944ff;border-radius:8px;padding:15px;margin:15px 0;font-family:monospace">
<h3 style="color:#9944ff;margin:0 0 10px 0">📡 Pipelite Pipeline</h3>
<div style="display:flex;gap:10px;flex-wrap:wrap">
<button class="pipelite-btn" onclick="runPipelite('{0}','list')" style="background:#9944ff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📋 List</button>
<button class="pipelite-btn" onclick="runPipelite('{0}','status')" style="background:#6c757d;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📊 Status</button>
<button class="pipelite-btn" onclick="runPipelite('{0}','jobs')" style="background:#00aaff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📦 Jobs</button>
<button class="pipelite-btn" onclick="runPipelite('{0}','stages')" style="background:#6633ff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">🏁 Stages</button>
</div>
<pre id="pipelite-output-{0}" style="background:#0d0d1a;padding:10px;border-radius:4px;margin-top:10px;max-height:300px;overflow:auto;font-size:12px;display:none;white-space:pre-wrap"></pre>
</div>
<script>
function runPipelite(id,action){{
  const prefix='{1}';
  const pre=document.getElementById('pipelite-output-'+id);
  if(!pre)return;
  pre.style.display='block';
  pre.innerHTML='⏳ Running...';
  fetch(prefix+'/plugin/pipelite/'+id,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{action:action}})}})
  .then(r=>r.json())
  .then(data=>{{pre.innerHTML=data.status==='ok'?'✅ OK\n'+data.output:'❌ Error\n'+data.output;}})
  .catch(err=>{{pre.innerHTML='❌ '+err;}});
}}
</script>"#,
        paste_id, base_path
    )
}