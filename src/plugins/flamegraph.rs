// Flamegraph plugin — generate interactive SVG flamegraphs from folded stack data
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::io::{Cursor, BufReader};

pub struct FlamegraphPlugin;

impl FlamegraphPlugin {
    pub fn new() -> Self { Self }
}

impl Plugin for FlamegraphPlugin {
    fn name(&self) -> &str { "flamegraph" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Interactive flamegraph generator — POST folded stack data to get SVG call trees" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("generate");

        match action {
            "generate" => {
                let content = std::str::from_utf8(&input.content).unwrap_or("").to_string();
                if content.trim().is_empty() {
                    map.insert("error".to_string(), "No data provided. Send folded stack data as POST body.".to_string());
                    return Ok(map);
                }
                match generate_flamegraph_svg(&content) {
                    Ok(svg) => {
                        let html = wrap_flamegraph_html(&input.id, &svg);
                        map.insert("html".to_string(), html);
                        map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
                        map.insert("svg".to_string(), svg);
                    }
                    Err(e) => {
                        map.insert("error".to_string(), format!("Flamegraph generation failed: {}", e));
                    }
                }
            }
            "help" | _ => {
                map.insert("html".to_string(), r#"<h1>🔥 Flamegraph Generator</h1>
<p>Generates interactive SVG flamegraphs from folded stack trace data.</p>
<form id="fg-form">
  <label>Folded stack data (one line per stack with sample count):</label><br>
  <textarea name="data" rows="12" cols="80" placeholder="main;loop 10&#10;main;loop;work 5&#10;main;init 3"></textarea><br>
  <button onclick="submitFlamegraph()">Generate Flamegraph</button>
</form>
<div id="fg-output"></div>
<script>
function submitFlamegraph() {
  const data = document.querySelector('#fg-form textarea').value;
  fetch('/plugin/flamegraph/test', {
    method: 'POST',
    headers: {'Content-Type': 'text/plain'},
    body: data
  }).then(r => r.text()).then(html => {
    document.querySelector('#fg-output').innerHTML = html;
  });
}
</script>"#.to_string());
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            }
        }
        Ok(map)
    }
}

fn generate_flamegraph_svg(folded: &str) -> Result<String, String> {
    let data = folded.to_string();
    let reader = BufReader::new(Cursor::new(data));
    let mut options = inferno::flamegraph::Options::default();
    options.title = "Flamegraph".to_string();
    options.colors = inferno::flamegraph::color::Palette::default();
    options.count_name = "samples".to_string();
    options.factor = 1.0;
    options.font_type = "Liberation Sans".to_string();
    options.font_size = 12;
    options.image_width = Some(1200);
    options.frame_height = 16;
    options.min_width = 0.1;
    options.reverse_stack_order = true;
    let mut output = Vec::new();
    inferno::flamegraph::from_reader(&mut options, reader, &mut output)
        .map_err(|e| format!("inferno error: {}", e))?;
    let svg = String::from_utf8(output).map_err(|e| format!("UTF-8 error: {}", e))?;
    Ok(svg)
}

fn wrap_flamegraph_html(id: &str, svg: &str) -> String {
    format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Flamegraph: {id}</title>
<style>
body {{ font-family: sans-serif; margin: 20px; background: #fff; }}
.fg-toolbar {{ margin-bottom: 10px; padding: 8px; background: #f5f5f5; border-radius: 4px; }}
.fg-toolbar input {{ padding: 4px 8px; margin-right: 8px; width: 200px; }}
.fg-toolbar button {{ padding: 4px 12px; margin-right: 4px; cursor: pointer; }}
.fg-container {{ overflow: auto; border: 1px solid #ddd; border-radius: 4px; }}
.fg-svg {{ min-width: 100%; }}
.fg-svg svg {{ width: 100%; height: auto; }}
</style></head><body>
<h2>🔥 Flamegraph: {id}</h2>
<div class="fg-toolbar">
  <label>Search: <input type="text" id="fg-search" oninput="searchFlamegraph(this.value)" placeholder="Filter frames..."></label>
  <button onclick="resetView()">↺ Reset Zoom</button>
  <button onclick="flipDirection()">↕ Flip</button>
  <label><input type="checkbox" id="fg-topdown" checked onchange="toggleDirection()"> Top-down</label>
</div>
<div class="fg-container" id="fg-container">
  <div class="fg-svg">{svg}</div>
</div>
<script>
let direction = 'flame';
function searchFlamegraph(q) {{
  document.querySelectorAll('.fg-svg text').forEach(el => {{
    el.style.opacity = (!q || el.textContent.includes(q)) ? '1' : '0.1';
  }});
}}
function resetView() {{
  document.querySelectorAll('.fg-svg svg').forEach(s => s.style.transform = '');
}}
function flipDirection() {{
  direction = direction === 'flame' ? 'icicle' : 'flame';
  toggleDirection();
}}
function toggleDirection() {{
  const topdown = document.getElementById('fg-topdown').checked;
  document.querySelectorAll('.fg-svg svg').forEach(s => {{
    s.style.transform = topdown ? 'scaleY(-1)' : '';
  }});
}}
</script>
</body></html>"#, id = id, svg = svg)
}
