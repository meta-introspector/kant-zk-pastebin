// MIDI plugin — index and serve MIDI files via CAR
use crate::plugin::{Plugin, PluginInput, PluginResult};
use crate::car_index::CarIndex;
use std::collections::HashMap;
use std::sync::Arc;

pub struct MidiPlugin {
    index: Arc<CarIndex>,
}

impl MidiPlugin {
    pub fn new(index: Arc<CarIndex>) -> Self {
        Self { index }
    }
}

impl Plugin for MidiPlugin {
    fn name(&self) -> &str { "midi" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "MIDI file browser — index and serve .mid files via CAR content addressing" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");

        match action {
            "browse" => {
                // List indexed MIDI files with pagination
                let files = self.index.get_by_type("mid");
                let page = input.extra.get("page").and_then(|p| p.parse::<usize>().ok()).unwrap_or(0);
                let per_page = 100;
                let total_pages = (files.len() + per_page - 1) / per_page;
                let start = page * per_page;
                let end = (start + per_page).min(files.len());

                let mut html = format!(
                    r#"<h1>🎵 MIDI Files</h1>
<p>{} total files | Page {}/{} | <a href="?action=stats">Stats</a> | <a href="?action=search">Search</a></p>
<table><tr><th>Name</th><th>Size</th><th>Path</th><th>Actions</th></tr>"#,
                    files.len(), page + 1, total_pages.max(1)
                );

                for f in &files[start..end] {
                    let name = html_escape(&f.name);
                    let rel_path = f.path.to_string_lossy();
                    html.push_str(&format!(
                        r#"<tr><td>{}</td><td>{} B</td><td><small>{}</small></td>
                        <td><a href="?action=download&path={}">⬇️</a></td></tr>"#,
                        name, f.size, html_escape(&rel_path), urlencode(&rel_path)
                    ));
                }
                html.push_str("</table>\n");

                // Pagination
                if total_pages > 1 {
                    html.push_str("<div class='pagination'>");
                    for p in 0..total_pages.min(20) {
                        let active = if p == page { "style='font-weight:bold'" } else { "" };
                        html.push_str(&format!(
                            r#"<a href="?action=browse&page={}" {}>{}</a> "#, p, active, p + 1
                        ));
                    }
                    html.push_str("</div>");
                }

                map.insert("html".to_string(), html);
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            }
            "download" => {
                let path = input.extra.get("path").cloned().unwrap_or_default();
                match std::fs::read(&path) {
                    Ok(bytes) => {
                        use base64::Engine;
                        let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
                        map.insert("content".to_string(), b64);
                        map.insert("content_type".to_string(), "audio/midi".to_string());
                        map.insert("encoding".to_string(), "base64".to_string());
                        map.insert("filename".to_string(),
                            std::path::Path::new(&path)
                                .file_name().map(|n| n.to_string_lossy().to_string())
                                .unwrap_or_else(|| "unknown.mid".to_string()));
                    }
                    Err(e) => {
                        map.insert("error".to_string(), format!("File not found: {}", e));
                    }
                }
            }
            "stats" => {
                let files = self.index.get_by_type("mid");
                let total_size: u64 = files.iter().map(|f| f.size).sum();
                map.insert("total".to_string(), files.len().to_string());
                map.insert("total_size_mb".to_string(), format!("{:.1}", total_size as f64 / 1_000_000.0));
                map.insert("avg_size_kb".to_string(), format!("{:.1}",
                    if files.is_empty() { 0.0 } else { total_size as f64 / files.len() as f64 / 1000.0 }));
            }
            "search" => {
                let q = input.extra.get("q").cloned().unwrap_or_default();
                if q.is_empty() {
                    map.insert("html".to_string(),
                        r#"<h1>🔍 Search MIDI</h1><form><input name="q" placeholder="Search..."><button>Search</button></form>"#.to_string());
                } else {
                    let results = self.index.search("mid", &q);
                    let html = results.iter().map(|f| {
                        format!(r#"<li><a href="?action=download&path={}">{} ({})</a></li>"#,
                            urlencode(&f.path.to_string_lossy()), html_escape(&f.name), f.size)
                    }).collect::<Vec<_>>().join("\n");
                    map.insert("html".to_string(), format!("<h3>{} results for '{}'</h3><ul>{}</ul>", results.len(), html_escape(&q), html));
                }
            }
            _ => {
                map.insert("error".to_string(), format!("Unknown action: {}", action));
            }
        }

        Ok(map)
    }
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

fn urlencode(s: &str) -> String {
    s.chars().map(|c| match c {
        'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' | '/' => c.to_string(),
        _ => format!("%{:02X}", c as u8),
    }).collect()
}
