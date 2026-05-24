// Git tile — browse git trees, submodules, branches, and status
// Each git repository becomes an interactive tile with introspection.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct GitTilePlugin;

impl GitTilePlugin {
    pub fn new() -> Self { Self }

    fn git_cmd(repo: &str, args: &[&str]) -> Result<String, String> {
        Command::new("git")
            .args(["-C", repo])
            .args(args)
            .output()
            .map(|o| {
                if o.status.success() {
                    String::from_utf8_lossy(&o.stdout).trim().to_string()
                } else {
                    String::from_utf8_lossy(&o.stderr).trim().to_string()
                }
            })
            .map_err(|e| format!("git error: {}", e))
    }

    fn get_repo_info(repo: &str) -> HashMap<String, String> {
        let mut info = HashMap::new();
        info.insert("path".to_string(), repo.to_string());
        info.insert("branch".to_string(), Self::git_cmd(repo, &["rev-parse", "--abbrev-ref", "HEAD"]).unwrap_or_default());
        info.insert("sha".to_string(), Self::git_cmd(repo, &["rev-parse", "HEAD"]).unwrap_or_default().chars().take(12).collect());
        info.insert("message".to_string(), Self::git_cmd(repo, &["log", "--oneline", "-1"]).unwrap_or_default());
        info.insert("status".to_string(), Self::git_cmd(repo, &["status", "--porcelain"]).unwrap_or_default());
        info.insert("commits_ahead".to_string(), Self::git_cmd(repo, &["rev-list", "--count", "@{upstream}..HEAD", "--"]).unwrap_or_else(|_| "0".to_string()));
        info.insert("commits_behind".to_string(), Self::git_cmd(repo, &["rev-list", "--count", "HEAD..@{upstream}", "--"]).unwrap_or_else(|_| "0".to_string()));
        info.insert("remote".to_string(), Self::git_cmd(repo, &["remote", "-v"]).unwrap_or_default());
        info.insert("submodules".to_string(), Self::git_cmd(repo, &["submodule", "status"]).unwrap_or_default());
        info
    }

    fn discover_repos(root: &str) -> Vec<(String, String)> {
        let mut repos = Vec::new();

        // Root repo
        if Path::new(root).join(".git").exists() {
            if let Ok(remote) = Self::git_cmd(root, &["remote", "get-url", "origin"]) {
                let name = Path::new(root).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                repos.push((name, root.to_string()));
            }
        }

        // Walk submodules from gitmodules
        let gitmodules = Path::new(root).join(".gitmodules");
        if let Ok(content) = std::fs::read_to_string(&gitmodules) {
            for line in content.lines() {
                if let Some(path) = line.trim().strip_prefix("path = ") {
                    let full_path = if root == "/home/mdupont/dasl" {
                        format!("{}/{}", root, path)
                    } else {
                        format!("{}/{}", root, path)
                    };
                    if Path::new(&full_path).join(".git").exists() || Path::new(&full_path).join(".git").is_file() {
                        let name = Path::new(path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                        repos.push((format!("{}/{}", Path::new(root).file_name().map(|n| n.to_string_lossy()).unwrap_or_default(), path), full_path));
                    }
                }
            }
        }

        repos
    }
}

impl Plugin for GitTilePlugin {
    fn name(&self) -> &str { "git" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Git tile — browse git trees, submodules, branches, and status across all repositories" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");
        let root = input.extra.get("root").cloned().unwrap_or_else(|| "/home/mdupont/dasl".to_string());

        match action {
            "browse" => {
                let repos = Self::discover_repos(&root);
                let mut html = String::from("<h1>📦 Git Trees</h1><div class='repo-grid' style='display:grid;grid-template-columns:repeat(auto-fill,minmax(350px,1fr));gap:10px'>");

                for (name, path) in &repos {
                    let info = Self::get_repo_info(path);
                    let branch = info.get("branch").map(|s| s.as_str()).unwrap_or("?");
                    let sha = info.get("sha").map(|s| s.as_str()).unwrap_or("?");
                    let msg = info.get("message").map(|s| s.as_str()).unwrap_or("");
                    let status = info.get("status").map(|s| s.as_str()).unwrap_or("");
                    let is_dirty = !status.is_empty();
                    let dirty_badge = if is_dirty { "🔴 dirty" } else { "🟢 clean" };
                    let ahead = info.get("commits_ahead").map(|s| s.as_str()).unwrap_or("0");
                    let behind = info.get("commits_behind").map(|s| s.as_str()).unwrap_or("0");

                    html.push_str(&format!(
                        r#"<div class="repo-card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:12px">
<h3 style="margin:0 0 4px 0">{}</h3>
<div style="font-size:12px;color:#8b949e">{}</div>
<div style="margin:6px 0">
<span class="badge" style="background:#0e4429;color:#3fb950;padding:2px 8px;border-radius:4px;font-size:11px">{}</span>
<span style="font-size:11px;color:#8b949e">{}</span>
</div>
<code style="font-size:11px">{}</code>
<div style="font-size:11px;margin:4px 0;color:#58a6ff">{}</div>
<div style="font-size:10px;color:#8b949e">↑{} ↓{}</div>
<a href="?action=repo&path={}" style="font-size:11px">🔍 Inspect</a>
</div>"#,
                        name, path, dirty_badge, branch, sha, msg, ahead, behind, path
                    ));
                }
                html.push_str("</div>");
                html.push_str(&format!("<p style='font-size:12px;color:#8b949e'>{} repositories found</p>", repos.len()));
                map.insert("html".to_string(), html);
            }
            "repo" => {
                let path = input.extra.get("path").cloned().unwrap_or_default();
                let info = Self::get_repo_info(&path);
                let log = Self::git_cmd(&path, &["log", "--oneline", "-10"]).unwrap_or_default();
                let diff = Self::git_cmd(&path, &["diff", "--stat"]).unwrap_or_default();

                let html = format!(
                    r#"<h1>📦 {}</h1>
<table>
<tr><td>Path</td><td><code>{}</code></td></tr>
<tr><td>Branch</td><td><code>{}</code></td></tr>
<tr><td>HEAD</td><td><code>{}</code></td></tr>
<tr><td>Status</td><td>{}</td></tr>
<tr><td>Ahead/Behind</td><td>↑{} ↓{}</td></tr>
<tr><td>Remote</td><td><pre>{}</pre></td></tr>
</table>
<h3>Recent Commits</h3>
<pre>{}</pre>
<h3>Uncommitted Changes</h3>
<pre>{}</pre>
<a href="?action=browse">← Back</a>"#,
                    info.get("branch").unwrap_or(&path),
                    path,
                    info.get("branch").unwrap_or(&"?".to_string()),
                    info.get("sha").unwrap_or(&"?".to_string()),
                    if info.get("status").map(|s| !s.is_empty()).unwrap_or(false) { "🔴 dirty" } else { "🟢 clean" },
                    info.get("commits_ahead").unwrap_or(&"0".to_string()),
                    info.get("commits_behind").unwrap_or(&"0".to_string()),
                    info.get("remote").unwrap_or(&"".to_string()),
                    log, diff
                );
                map.insert("html".to_string(), html);
            }
            _ => { map.insert("error".to_string(), format!("Unknown action: {}", action)); }
        }
        Ok(map)
    }
}

use std::path::Path;
