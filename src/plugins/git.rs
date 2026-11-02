//! Git tile — repository/commit/branch tile.
//! Surfaces Git repos, commits, branches, and diffs.

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct GitPlugin;

impl GitPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for GitPlugin {
    fn name(&self) -> &str {
        "git"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "Git repository — browse commits, branches, diffs"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let content = String::from_utf8_lossy(&input.content);
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("detect");
        let mut result = HashMap::new();

        match action {
            "detect" => {
                let is_git = content.contains("git@") 
                    || content.contains("github.com/")
                    || content.contains("gitlab.com/")
                    || content.contains(".git")
                    || content.starts_with("commit ")
                    || content.contains("diff --git");
                result.insert("is_git".into(), is_git.to_string());
                if is_git {
                    result.insert(
                        "tile_html".into(),
                        render_git_tile_html(&input.id, &input.extra.get("base_path").map(|s| s.as_str()).unwrap_or("")),
                    );
                }
            }
            "log" | "branches" | "diff" | "status" | "show" => {
                result.insert("status".into(), "error".into());
                result.insert(
                    "output".into(),
                    "git actions disabled: no shell-out allowed".to_string(),
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

pub fn render_git_tile_html(paste_id: &str, base_path: &str) -> String {
    format!(
        r#"<div class="git-tile" style="background:#1a1a2e;border:1px solid #f05033;border-radius:8px;padding:15px;margin:15px 0;font-family:monospace">
<h3 style="color:#f05033;margin:0 0 10px 0">🔀 Git Repository</h3>
<div style="display:flex;gap:10px;flex-wrap:wrap">
<button class="git-btn" onclick="runGit('{0}','log')" style="background:#f05033;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📜 Log</button>
<button class="git-btn" onclick="runGit('{0}','branches')" style="background:#00aaff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">🌿 Branches</button>
<button class="git-btn" onclick="runGit('{0}','diff')" style="background:#ff6600;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📝 Diff</button>
<button class="git-btn" onclick="runGit('{0}','status')" style="background:#9933ff;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📊 Status</button>
</div>
<pre id="git-output-{0}" style="background:#0d0d1a;padding:10px;border-radius:4px;margin-top:10px;max-height:300px;overflow:auto;font-size:12px;display:none;white-space:pre-wrap"></pre>
</div>
<script>
function runGit(id,action){{
  const prefix='{1}';
  const pre=document.getElementById('git-output-'+id);
  if(!pre)return;
  pre.style.display='block';
  pre.innerHTML='⏳ Running...';
  fetch(prefix+'/plugin/git/'+id,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{action:action}})}})
  .then(r=>r.json())
  .then(data=>{{pre.innerHTML=data.status==='ok'?'✅ OK\n'+data.output:'❌ Error\n'+data.output;}})
  .catch(err=>{{pre.innerHTML='❌ '+err;}});
}}
</script>"#,
        paste_id, base_path
    )
}