//! Task Attachments Tile — associates pastes/IPFS CIDs with tasks.
//!
//! This tile provides a UI for linking pastes and IPFS content to tasks.
//! It is served at `/tile/task-attachments`.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// A task attachment linking a paste/CID to a task.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskAttachment {
    pub task_id: String,
    pub paste_id: Option<String>,
    pub cid: Option<String>,
    pub ipfs_cid: Option<String>,
    pub title: String,
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub created_at: String,
}

/// In-memory store for task attachments (persisted to disk in production).
static TASK_ATTACHMENTS: once_cell::sync::Lazy<tokio::sync::Mutex<Vec<TaskAttachment>>> =
    once_cell::sync::Lazy::new(|| tokio::sync::Mutex::new(Vec::new()));

/// Add a task attachment.
pub async fn add_attachment(att: TaskAttachment) {
    let mut store = TASK_ATTACHMENTS.lock().await;
    store.push(att);
}

/// Get attachments for a task.
pub async fn get_task_attachments(task_id: &str) -> Vec<TaskAttachment> {
    let store = TASK_ATTACHMENTS.lock().await;
    store.iter().filter(|a| a.task_id == task_id).cloned().collect()
}

/// Get all attachments.
pub async fn get_all_attachments() -> Vec<TaskAttachment> {
    let store = TASK_ATTACHMENTS.lock().await;
    store.clone()
}

/// Find attachments by CID.
pub async fn find_by_cid(cid: &str) -> Vec<TaskAttachment> {
    let store = TASK_ATTACHMENTS.lock().await;
    store
        .iter()
        .filter(|a| a.cid.as_deref() == Some(cid) || a.ipfs_cid.as_deref() == Some(cid))
        .cloned()
        .collect()
}

/// Render the task attachments tile as HTML.
pub fn render_tile() -> String {
    let attachments = futures::executor::block_on(get_all_attachments());

    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Task Attachments</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; padding: 20px; background: #1a1a2e; color: #e0e0e0; }}
  h1 {{ color: #4cc9f0; border-bottom: 2px solid #4cc9f0; padding-bottom: 10px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(350px, 1fr)); gap: 15px; }}
  .card {{ background: #16213e; border-radius: 8px; padding: 15px; }}
  .card h3 {{ margin-top: 0; color: #4cc9f0; }}
  .cid {{ font-family: monospace; font-size: 0.9em; word-break: break-all; color: #a0a0a0; }}
  .tag {{ display: inline-block; padding: 2px 8px; margin: 2px; background: #0f3460; border-radius: 12px; font-size: 0.8em; }}
  .btn {{ display: inline-block; padding: 8px 16px; margin: 4px; background: #4cc9f0; color: #000; border-radius: 4px; text-decoration: none; font-size: 0.9em; }}
  .btn:hover {{ background: #3aa8d0; }}
  .btn.secondary {{ background: #6c757d; color: #fff; }}
  a {{ color: #4cc9f0; }}
  .empty {{ text-align: center; color: #6c757d; padding: 40px; }}
</style>
</head>
<body>
  <h1>📋 Task Attachments</h1>
  <div class="grid">
    {}
  </div>
</body>
</html>"#,
        if attachments.is_empty() {
            "<div class=\"empty\">No task attachments yet. Paste a CID and associate it with a task.</div>".to_string()
        } else {
            attachments.iter().map(|a| format!(
                "<div class=\"card\">
      <h3>Task: {}</h3>
      <div><strong>{}</strong></div>
      {}
      {}
      {}
      <a class=\"btn\" href=\"/paste/{}\" target=\"_blank\">View Paste</a>
    </div>",
                a.task_id,
                a.title,
                a.cid.as_deref().map(|c| format!("<div class=\"cid\">CID: {}</div>", c)).unwrap_or_default(),
                a.ipfs_cid.as_deref().map(|c| format!("<div class=\"cid\">IPFS: <a href=\"/ipfs/{}\" target=\"_blank\">{}</a></div>", c, &c[..c.len().min(20)])).unwrap_or_default(),
                a.tags.iter().map(|t| format!("<span class=\"tag\">{}</span>", t)).collect::<Vec<_>>().join(""),
                a.paste_id.as_deref().unwrap_or(""),
            )).collect::<Vec<_>>().join("")
        }
    )
}

/// Render JSON for API.
pub fn attachments_json() -> Value {
    json!({
        "tile": "task-attachments",
        "attachments": futures::executor::block_on(get_all_attachments()),
    })
}