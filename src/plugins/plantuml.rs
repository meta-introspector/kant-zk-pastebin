// PlantUML plugin — index and serve PlantUML diagrams via CAR
use crate::plugin::{Plugin, PluginInput, PluginResult};
use crate::car_index::CarIndex;
use std::collections::HashMap;
use std::sync::Arc;

pub struct PlantUmlPlugin {
    index: Arc<CarIndex>,
}

impl PlantUmlPlugin {
    pub fn new(index: Arc<CarIndex>) -> Self {
        Self { index }
    }

    fn render_diagram(&self, content: &str, format: &str) -> Result<Vec<u8>, String> {
        let output = std::process::Command::new("plantuml")
            .args(["-t", format, "-pipe"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("plantuml not found: {}", e))?;

        use std::io::Write;
        let mut child = output;
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(content.as_bytes()).map_err(|e| format!("write stdin: {}", e))?;
        }
        let output = child.wait_with_output().map_err(|e| format!("wait: {}", e))?;
        if !output.status.success() {
            return Err(format!("plantuml error: {}", String::from_utf8_lossy(&output.stderr)));
        }
        Ok(output.stdout)
    }
}

impl Plugin for PlantUmlPlugin {
    fn name(&self) -> &str { "plantuml" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "PlantUML diagram viewer — index and render .puml files via CAR" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();

        // Action dispatch based on extra param
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");

        match action {
            "browse" => {
                // List all indexed PlantUML files
                let files = self.index.get_by_type("puml");
                let mut html = String::from("<h1>📐 PlantUML Diagrams</h1>\n<ul>\n");
                for f in files.iter().take(200) {
                    let name = html_escape(&f.name);
                    let rel_path = f.path.to_string_lossy();
                    html.push_str(&format!(
                        r#"<li><a href="?action=view&path={}">{}</a> <small>({} bytes)</small></li>"#,
                        urlencode(&rel_path), name, f.size
                    ));
                }
                html.push_str("</ul>\n");
                if files.len() > 200 {
                    html.push_str(&format!("<p>... and {} more</p>", files.len() - 200));
                }
                map.insert("html".to_string(), html);
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            }
            "view" | "render" => {
                let path = input.extra.get("path").unwrap_or(&String::new());
                match std::fs::read_to_string(path) {
                    Ok(content) => {
                        if action == "render" {
                            let fmt = input.extra.get("format").map(|s| s.as_str()).unwrap_or("svg");
                            match self.render_diagram(&content, fmt) {
                                Ok(bytes) => {
                                    map.insert("content".to_string(), format!("{:?}", bytes));
                                    map.insert("content_type".to_string(),
                                        if fmt == "svg" { "image/svg+xml".to_string() }
                                        else { "image/png".to_string() });
                                }
                                Err(e) => {
                                    map.insert("error".to_string(), e);
                                }
                            }
                        } else {
                            map.insert("content".to_string(), content);
                            map.insert("content_type".to_string(), "text/plain; charset=utf-8".to_string());
                        }
                    }
                    Err(e) => {
                        map.insert("error".to_string(), format!("File not found: {}", e));
                    }
                }
            }
            "stats" => {
                let files = self.index.get_by_type("puml");
                map.insert("total".to_string(), files.len().to_string());
                map.insert("total_size".to_string(),
                    files.iter().map(|f| f.size).sum::<u64>().to_string());
            }
            "search" => {
                let q = input.extra.get("q").unwrap_or(&String::new());
                let results = self.index.search("puml", q);
                let html = results.iter().map(|f| {
                    format!("<li><a href=\"?action=view&path={}\">{}</a></li>",
                        urlencode(&f.path.to_string_lossy()), html_escape(&f.name))
                }).collect::<Vec<_>>().join("\n");
                map.insert("html".to_string(), format!("<ul>{}</ul>", html));
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
