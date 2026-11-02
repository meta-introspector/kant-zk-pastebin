//! Task tile — task management tile.
//! Surfaces tasks, status, assignments, and tracking.

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct TaskPlugin;

impl TaskPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for TaskPlugin {
    fn name(&self) -> &str {
        "task"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "Task management — track assignments, status, and progress"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let content = String::from_utf8_lossy(&input.content);
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("detect");
        let mut result = HashMap::new();

        match action {
            "detect" => {
                let is_task = content.contains("task")
                    || content.contains("todo")
                    || content.contains("TODO")
                    || content.contains("@")
                    || content.contains("#");
                result.insert("is_task".into(), is_task.to_string());
                if is_task {
                    result.insert(
                        "tile_html".into(),
                        render_task_tile_html(&input.id, &input.extra.get("base_path").map(|s| s.as_str()).unwrap_or("")),
                    );
                }
            }
            "list" | "status" | "assign" | "progress" => {
                result.insert("status".into(), "error".into());
                result.insert(
                    "output".into(),
                    "task actions disabled: no shell-out allowed".to_string(),
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

pub fn render_task_tile_html(paste_id: &str, base_path: &str) -> String {
    format!(
        r#"<div class="task-tile" style="background:#1a1a2e;border:1solid #4cc9f0;border-radius:8px;padding:15px;margin:15px 0;font-family:monospace">
<h3 style="color:#4cc9f0;margin:0 0 10px 0">📋 Task</h3>
<div style="display:flex;gap:10px;flex-wrap:wrap">
<button class="task-btn" onclick="runTask('{0}','list')" style="background:#4cc9f0;color:#000;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📋 List</button>
<button class="task-btn" onclick="runTask('{0}','status')" style="background:#28a745;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📊 Status</button>
<button class="task-btn" onclick="runTask('{0}','assign')" style="background:#ffc107;color:#000;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">✏️ Assign</button>
<button class="task-btn" onclick="runTask('{0}','progress')" style="background:#6c757d;color:#fff;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">📈 Progress</button>
</div>
<pre id="task-output-{0}" style="background:#0d0d1a;padding:10px;border-radius:4px;margin-top:10px;max-height:300px;overflow:auto;font-size:12px;display:none;white-space:pre-wrap"></pre>
</div>
<script>
function runTask(id,action){{
  const prefix='{1}';
  const pre=document.getElementById('task-output-'+id);
  if(!pre)return;
  pre.style.display='block';
  pre.innerHTML='⏳ Running...';
  fetch(prefix+'/plugin/task/'+id,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{action:action}})}})
  .then(r=>r.json())
  .then(data=>{{pre.innerHTML=data.status==='ok'?'✅ OK\n'+data.output:'❌ Error\n'+data.output;}})
  .catch(err=>{{pre.innerHTML='❌ '+err;}});
}}
</script>"#,
        paste_id, base_path
    )
}