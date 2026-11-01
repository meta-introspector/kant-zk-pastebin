//! Forgejo tile — issues/PRs/repos tile.
//! Surfaces Forgejo repository issues, pull requests, and metadata.

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct ForgejoPlugin;

impl ForgejoPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for ForgejoPlugin {
    fn name(&self) -> &str {
        "forgejo"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "Forgejo Git forge — issues, pull requests, repositories"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let content = String::from_utf8_lossy(&input.content);
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("detect");
        let mut result = HashMap::new();

        match action {
            "detect" => {
                let is_forgejo = content.contains("forgejo")
                    || content.contains("gitea")
                    || content.contains("forgejo.org")
                    || content.contains("/issues/")
                    || content.contains("/pulls/")
                    || content.contains("/pull/");
                result.insert("is_forgejo".into(), is_forgejo.to_string());
                if is_forgejo {
                    result.insert(
                        "tile_html".into(),
                        render_forgejo_tile_html(&input.id, &input.extra.get("base_path").map(|s| s.as_str()).unwrap_or("")),
                    );
                }
            }
            "issues" | "prs" | "repos" | "issue" | "pull" => {
                result.insert("status".into(), "error".into());
                result.insert(
                    "output".into(),
                    "forgejo actions disabled: no shell-out allowed".to_string(),
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

pub fn render_forgejo_tile_html(paste_id: &str, base_path: &str) -> String {
    format!(
        r#"<div class="forgejo-tile" style="background:#1a1a2e;border:1px solid #e84b3d;border-radius:8px;padding:15px;margin:15px 0;font-family:monospace">
<h3 style="color:#e84b3d;margin:0 0 10px 0">🔧 Forgejo</h3>
<div style="display:flex;gap:10px;flex-wrap:wrap">
<button class="forgejo-btn" onclick="runForgejo('{0}','issues')" style="background:#e84b3d;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">🐛 Issues</button>
<button class="forgejo-btn" onclick="runForgejo('{0}','prs')" style="background:#00aaff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">🔀 PRs</button>
<button class="forgejo-btn" onclick="runForgejo('{0}','repos')" style="background:#ff6600;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📂 Repos</button>
<button class="forgejo-btn" onclick="runForgejo('{0}','issue')" style="background:#9933ff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📋 Issue</button>
</div>
<pre id="forgejo-output-{0}" style="background:#0d0d1a;padding:10px;border-radius:4px;margin-top:10px;max-height:300px;overflow:auto;font-size:12px;display:none;white-space:pre-wrap"></pre>
</div>
<script>
function runForgejo(id,action){{
  const prefix='{1}';
  const pre=document.getElementById('forgejo-output-'+id);
  if(!pre)return;
  pre.style.display='block';
  pre.innerHTML='⏳ Running...';
  fetch(prefix+'/plugin/forgejo/'+id,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{action:action}})}})
  .then(r=>r.json())
  .then(data=>{{pre.innerHTML=data.status==='ok'?'✅ OK\n'+data.output:'❌ Error\n'+data.output;}})
  .catch(err=>{{pre.innerHTML='❌ '+err;}});
}}
</script>"#,
        paste_id, base_path
    )
}