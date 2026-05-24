// Perf Annotations tile — annotate source code with performance profiling data
//
// Input formats:
//   - Folded stacks:  "func;subfunc N" (same as flamegraph)
//   - Perf report:    "{percent}  {func}" or "      N {func}"
//   - Source code:    Plain text source to annotate
//
// Output: Interactive HTML with color-coded source annotations

use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::{HashMap, BTreeMap};

pub struct PerfAnnotationsPlugin;

impl PerfAnnotationsPlugin {
    pub fn new() -> Self { Self }
}

impl Plugin for PerfAnnotationsPlugin {
    fn name(&self) -> &str { "perf_annotations" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str {
        "Annotate source code with performance profiling data — paste perf output and source to see hot lines"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("help");
        let body = std::str::from_utf8(&input.content).unwrap_or("");

        match action {
            "annotate" => self.handle_annotate(body, &mut map),
            "functions" => self.handle_functions(body, &mut map),
            "compare" => self.handle_compare(body, &mut map),
            "help" | _ => self.handle_help(&mut map),
        }
        Ok(map)
    }
}

impl PerfAnnotationsPlugin {
    fn handle_help(&self, map: &mut HashMap<String, String>) {
        map.insert("html".to_string(), HELP_HTML.to_string());
        map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
    }

    fn handle_annotate(&self, body: &str, map: &mut HashMap<String, String>) {
        // Parse the request: first line formats
        // Format 1: JSON {"data": "...", "source": "...", "source_lang": "rust"}
        // Format 2: Pasted data where ---SOURCE--- separates perf data from source
        let (perf_data, source_code, source_lang) = parse_annotate_input(body);

        if perf_data.is_empty() {
            map.insert("error".to_string(),
                "No perf data found. Send folded stacks or perf report output.".to_string());
            return;
        }

        // Parse perf data into function hotness map
        let functions = parse_perf_data(&perf_data);
        if functions.is_empty() {
            map.insert("error".to_string(),
                "Could not parse any functions from perf data. Try folded format: func;sub;sub2 N".to_string());
            return;
        }

        // Sort by samples descending
        let mut sorted: Vec<_> = functions.into_iter().collect();
        sorted.sort_by(|a, b| b.1.samples.cmp(&a.1.samples));
        let total: f64 = sorted.iter().map(|(_, i)| i.samples).sum();
        let total = if total == 0.0 { 1.0 } else { total };

        if source_code.is_empty() {
            // No source — just render function table
            let html = render_function_table(&sorted, total);
            map.insert("html".to_string(), html);
            map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            map.insert("function_count".to_string(), sorted.len().to_string());
            map.insert("total_samples".to_string(), total.to_string());
        } else {
            // Annotate source with perf data
            let annotation_map = match_functions_to_source(&sorted, &source_code);
            let html = render_annotated_source(&source_code, &annotation_map, source_lang);
            map.insert("html".to_string(), html);
            map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            let hot_count = annotation_map.values().filter(|a| a.percentage > 5.0).count();
            map.insert("hot_functions".to_string(), hot_count.to_string());
            map.insert("total_functions".to_string(), sorted.len().to_string());
        }
    }

    fn handle_functions(&self, body: &str, map: &mut HashMap<String, String>) {
        let (perf_data, _, _) = parse_annotate_input(body);
        let functions = parse_perf_data(&perf_data);
        let mut sorted: Vec<_> = functions.into_iter().collect();
        sorted.sort_by(|a, b| b.1.samples.cmp(&a.1.samples));
        let total: f64 = sorted.iter().map(|(_, i)| i.samples).sum();
        let total = if total == 0.0 { 1.0 } else { total };

        let html = render_function_table(&sorted, total);
        map.insert("html".to_string(), html);
        map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());

        // Also include JSON for programmatic use
        let json_items: Vec<serde_json::Value> = sorted.iter().map(|(name, info)| {
            serde_json::json!({
                "function": name,
                "samples": info.samples,
                "percentage": format!("{:.1}", info.samples / total * 100.0),
                "count": info.count,
            })
        }).collect();
        map.insert("json".to_string(), serde_json::to_string(&json_items).unwrap_or_default());
    }

    fn handle_compare(&self, body: &str, map: &mut HashMap<String, String>) {
        // Compare two perf data sets. Format:
        // ---BEFORE---
        // <perf data 1>
        // ---AFTER---
        // <perf data 2>
        let parts: Vec<&str> = body.splitn(3, "---AFTER---\n").collect();
        if parts.len() < 2 {
            map.insert("error".to_string(),
                "Compare requires two datasets separated by `---AFTER---`".to_string());
            return;
        }

        let (before_body, after_body) = {
            let before_part = parts[0];
            let before_clean = before_part.trim_start_matches("---BEFORE---\n").trim();
            let after_clean = parts[1].trim();
            (before_clean, after_clean)
        };

        let before_fns = parse_perf_data(before_body);
        let after_fns = parse_perf_data(after_body);

        let html = render_comparison(&before_fns, &after_fns);
        map.insert("html".to_string(), html);
        map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
    }
}

// ---- Data structures ----

#[derive(Debug, Clone)]
struct FuncInfo {
    samples: f64,
    count: u64,
}

#[derive(Debug, Clone)]
struct SourceAnnotation {
    function: String,
    percentage: f64,
    samples: f64,
    line: usize,
}

// ---- Parsing ----

fn parse_annotate_input(body: &str) -> (String, String, String) {
    // Try JSON first
    if let Ok(val) = serde_json::from_str::<serde_json::Value>(body) {
        let data = val.get("data").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let source = val.get("source").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let lang = val.get("source_lang").and_then(|v| v.as_str()).unwrap_or("auto").to_string();
        return (data, source, lang);
    }

    // Try ---SOURCE--- separator format
    let parts: Vec<&str> = body.splitn(2, "---SOURCE---\n").collect();
    if parts.len() == 2 {
        let data = parts[0].trim();
        let source = parts[1].trim();
        return (data.to_string(), source.to_string(), "auto".to_string());
    }

    // Otherwise treat entire body as perf data
    (body.to_string(), String::new(), "auto".to_string())
}

fn parse_perf_data(data: &str) -> HashMap<String, FuncInfo> {
    let mut functions: HashMap<String, (f64, u64)> = HashMap::new();

    for line in data.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        // Try folded format first: "func;subfunc;sub2 N"
        if let Some((stacks, count)) = line.rsplit_once(char::is_whitespace) {
            if let Ok(n) = count.parse::<f64>() {
                // Split the stack into individual functions
                for func in stacks.split(';') {
                    let f = func.trim();
                    if !f.is_empty() {
                        let entry = functions.entry(f.to_string()).or_insert((0.0, 0));
                        entry.0 += n / (stacks.split(';').count() as f64);
                        entry.1 += 1;
                    }
                }
                continue;
            }
        }

        // Try perf report format: "  N%  function" or "  N  function"
        // Also handle: "      N  function_name"
        let trimmed = line.trim_start();
        let parts: Vec<&str> = trimmed.splitn(2, char::is_whitespace).collect();
        if parts.len() == 2 {
            // First token could be a percentage or number
            let first = parts[0].trim_end_matches('%');
            if let Ok(n) = first.parse::<f64>() {
                let func = parts[1].trim().to_string();
                if !func.is_empty() && !func.contains(' ') {
                    let entry = functions.entry(func).or_insert((0.0, 0));
                    entry.0 += n;
                    entry.1 += 1;
                    continue;
                }
            }
        }
    }

    functions.into_iter()
        .map(|(k, (s, c))| (k, FuncInfo { samples: s, count: c }))
        .collect()
}

fn match_functions_to_source(
    functions: &[(String, FuncInfo)],
    source: &str,
) -> BTreeMap<usize, SourceAnnotation> {
    let mut line_map: BTreeMap<usize, SourceAnnotation> = BTreeMap::new();

    for (func_name, info) in functions {
        let search = func_name.to_lowercase();
        // Try to find the function name in source lines
        for (i, line) in source.lines().enumerate() {
            let line_lower = line.to_lowercase();
            if line_lower.contains(&search) {
                // Check it looks like a function definition
                let trimmed = line.trim();
                if trimmed.starts_with("pub ")
                    || trimmed.starts_with("fn ")
                    || trimmed.starts_with("def ")
                    || trimmed.starts_with("func ")
                    || trimmed.starts_with("function ")
                    || trimmed.starts_with("async fn ")
                    || trimmed.starts_with("pub(crate) fn ")
                    || trimmed.starts_with("impl ")
                    || trimmed.starts_with("struct ")
                    || trimmed.starts_with("enum ")
                    || trimmed.starts_with("trait ")
                {
                    let existing = line_map.get(&(i + 1));
                    let prev_pct = existing.map(|a| a.percentage).unwrap_or(0.0);
                    let this_pct = info.samples; // relative, will be normalized later
                    if this_pct > prev_pct {
                        line_map.insert(i + 1, SourceAnnotation {
                            function: func_name.clone(),
                            percentage: info.samples,
                            samples: info.samples,
                            line: i + 1,
                        });
                    }
                }
            }
        }
    }

    line_map
}

// ---- Rendering ----

fn render_function_table(functions: &[(String, FuncInfo)], total: f64) -> String {
    let mut rows = String::new();
    for (i, (name, info)) in functions.iter().enumerate() {
        let pct = info.samples / total * 100.0;
        let bar_width = (pct * 2.0).min(100.0) as usize;
        let heat = if pct > 20.0 { "#e74c3c" }
            else if pct > 10.0 { "#e67e22" }
            else if pct > 5.0 { "#f1c40f" }
            else if pct > 1.0 { "#2ecc71" }
            else { "#95a5a6" };

        rows.push_str(&format!(
            r#"<tr>
              <td class="num">{}</td>
              <td><span class="heat-bar" style="width:{}px;background:{}"></span></td>
              <td class="pct">{:.1}%</td>
              <td class="num">{:.0}</td>
              <td class="func-name">{}</td>
              <td class="num">{}</td>
            </tr>"#,
            i + 1, bar_width, heat, pct, info.samples, name, info.count,
        ));
    }

    format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Perf Functions</title>
<style>
body {{ font-family: 'Fira Code', 'Consolas', monospace; margin: 20px; background: #1e1e2e; color: #cdd6f4; }}
h2 {{ color: #f5c2e7; }}
table {{ border-collapse: collapse; width: 100%; font-size: 13px; }}
th {{ text-align: left; padding: 8px 12px; border-bottom: 2px solid #45475a; color: #a6adc8; }}
td {{ padding: 6px 12px; border-bottom: 1px solid #313244; }}
tr:hover {{ background: #313244; }}
.num {{ text-align: right; color: #fab387; font-variant-numeric: tabular-nums; }}
.pct {{ text-align: right; color: #a6e3a1; font-weight: bold; }}
.func-name {{ color: #89b4fa; }}
.heat-bar {{ display: inline-block; height: 12px; border-radius: 2px; vertical-align: middle; }}
.total {{ text-align: right; padding: 12px; color: #a6adc8; font-size: 12px; }}
caption {{ caption-side: bottom; padding: 8px; color: #6c7086; font-size: 11px; }}
</style></head><body>
<h2> Perf Function Summary</h2>
<table>
<tr><th>#</th><th>Hotness</th><th>%</th><th>Samples</th><th>Function</th><th>Calls</th></tr>
{rows}</table>
<p class="total">Total samples: {total:.0} | {} unique functions</p>
</body></html>"#, rows = rows, total = total, functions.len())
}

fn render_annotated_source(
    source: &str,
    annotations: &BTreeMap<usize, SourceAnnotation>,
    _lang: &str,
) -> String {
    let max_pct = annotations.values().map(|a| a.percentage).fold(0.0, f64::max);
    let max_pct = if max_pct == 0.0 { 1.0 } else { max_pct };

    let mut line_display = String::new();
    let max_line = source.lines().count();
    let line_width = max_line.to_string().len();

    for (i, line) in source.lines().enumerate() {
        let line_num = i + 1;
        let annotation = annotations.get(&line_num);

        let (bg_color, badge) = if let Some(a) = annotation {
            let intensity = a.percentage / max_pct;
            let r = (intensity * 231.0 + 24.0) as u8;
            let g = (intensity * 60.0 + 24.0) as u8;
            let b = (intensity * 60.0 + 24.0) as u8;
            let pct = a.percentage / max_pct * 100.0;
            let badge_text = format!("<span class=\"perf-badge\" style=\"{}\">{:.0}%</span>",
                if pct > 15.0 {
                    "background:#e74c3c;color:#fff"
                } else if pct > 8.0 {
                    "background:#e67e22;color:#fff"
                } else if pct > 3.0 {
                    "background:#f1c40f;color:#000"
                } else {
                    "background:#2ecc71;color:#fff"
                },
                pct
            );
            (format!("background-color:rgba({},{},{},0.3)", r, g, b), badge_text)
        } else {
            ("".to_string(), String::new())
        };

        let escaped = line
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;");

        line_display.push_str(&format!(
            r#"<div class="line {}" style="{}">
  <span class="line-num">{:0width$}</span>
  <span class="line-code">{}</span>
  {}
</div>"#,
            if annotation.is_some() { "hot" } else { "" },
            bg_color,
            line_num,
            escaped,
            badge,
            width = line_width,
        ));
    }

    format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Perf Annotations</title>
<style>
body {{ font-family: 'Fira Code', 'Consolas', monospace; margin: 0; background: #1e1e2e; color: #cdd6f4; font-size: 13px; }}
.toolbar {{ position: sticky; top: 0; background: #181825; padding: 8px 16px; border-bottom: 1px solid #45475a; z-index: 10; }}
.toolbar input {{ background: #313244; border: 1px solid #45475a; color: #cdd6f4; padding: 4px 8px; border-radius: 4px; width: 200px; }}
.toolbar input:focus {{ outline: none; border-color: #89b4fa; }}
.toolbar button {{ background: #45475a; border: none; color: #cdd6f4; padding: 4px 12px; border-radius: 4px; cursor: pointer; margin-left: 4px; }}
.toolbar button:hover {{ background: #585b70; }}
.toolbar .hot-toggle {{ margin-left: 16px; }}
.line {{ display: flex; padding: 2px 0; min-height: 20px; align-items: center; }}
.line:hover {{ background: #313244; }}
.line-num {{ min-width: 40px; text-align: right; padding-right: 16px; color: #6c7086; user-select: none; font-size: 12px; }}
.line-code {{ flex: 1; white-space: pre-wrap; }}
.perf-badge {{ display: inline-block; font-size: 10px; padding: 1px 6px; border-radius: 8px; font-weight: bold; margin-left: 8px; white-space: nowrap; min-width: 40px; text-align: center; }}
.hot-summary {{ padding: 12px 16px; background: #181825; border-bottom: 1px solid #45475a; font-size: 12px; color: #a6adc8; }}
.hot-summary span {{ margin-right: 16px; }}
</style></head><body>
<div class="toolbar">
  <input type="text" id="line-search" oninput="filterLines(this.value)" placeholder="Search code...">
  <button onclick="resetHot()">Show All</button>
  <button onclick="showHotOnly()">Hot Only</button>
  <label class="hot-toggle"><input type="checkbox" id="toggle-hot" onchange="toggleHotOnly()"> Highlighted only</label>
</div>
<div class="hot-summary">
  <span>🔥 Hot functions: <strong>{}</strong></span>
  <span>📝 Lines: <strong>{}</strong></span>
  <span>🎯 Max hotness: <strong>{:.1}%</strong></span>
</div>
<div id="source-container">{}</div>
<script>
function filterLines(q) {{
  document.querySelectorAll('.line').forEach(el => {{
    const code = el.querySelector('.line-code').textContent.toLowerCase();
    el.style.display = (!q || code.includes(q.toLowerCase())) ? 'flex' : 'none';
  }});
}}
let hotOnly = false;
function showHotOnly() {{ hotOnly = true; applyFilter(); }}
function resetHot() {{ hotOnly = false; applyFilter(); }}
function toggleHotOnly() {{ hotOnly = document.getElementById('toggle-hot').checked; applyFilter(); }}
function applyFilter() {{
  document.querySelectorAll('.line').forEach(el => {{
    if (hotOnly && !el.classList.contains('hot')) {{
      el.style.display = 'none';
    }} else {{
      el.style.display = 'flex';
    }}
  }});
}}
</script>
</body></html>"#,
        annotations.len(),
        source.lines().count(),
        max_pct / max_pct * 100.0,
        line_display,
    )
}

fn render_comparison(
    before: &HashMap<String, FuncInfo>,
    after: &HashMap<String, FuncInfo>,
) -> String {
    let mut all_fns: Vec<&String> = before.keys().chain(after.keys()).collect();
    all_fns.sort();
    all_fns.dedup();

    let mut rows = String::new();
    for func in all_fns {
        let b = before.get(func).map(|i| i.samples).unwrap_or(0.0);
        let a = after.get(func).map(|i| i.samples).unwrap_or(0.0);
        let diff = a - b;
        let change_pct = if b > 0.0 { (diff / b) * 100.0 } else { 0.0 };

        let (diff_class, diff_icon) = if diff > 1.0 { ("regression", "🔴")
            } else if diff < -1.0 { ("improvement", "🟢")
            } else { ("neutral", "⚪") };

        rows.push_str(&format!(
            r#"<tr class="{}">
              <td>{}</td>
              <td class="func-name">{}</td>
              <td class="num">{:.0}</td>
              <td class="num">{:.0}</td>
              <td class="{}-val">{:+.1}%</td>
            </tr>"#,
            diff_class, diff_icon, func, b, a, diff_class, change_pct,
        ));
    }

    format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Perf Comparison</title>
<style>
body {{ font-family: 'Fira Code', 'Consolas', monospace; margin: 20px; background: #1e1e2e; color: #cdd6f4; }}
h2 {{ color: #f5c2e7; }}
table {{ border-collapse: collapse; width: 100%; font-size: 13px; }}
th {{ text-align: left; padding: 8px 12px; border-bottom: 2px solid #45475a; color: #a6adc8; }}
td {{ padding: 6px 12px; border-bottom: 1px solid #313244; }}
tr:hover {{ background: #313244; }}
.num {{ text-align: right; color: #fab387; font-variant-numeric: tabular-nums; }}
.func-name {{ color: #89b4fa; }}
.regression {{ background: rgba(231,76,60,0.1); }}
.improvement {{ background: rgba(46,204,113,0.1); }}
.neutral {{ background: transparent; }}
.regression-val {{ color: #e74c3c; text-align: right; font-weight: bold; }}
.improvement-val {{ color: #2ecc71; text-align: right; font-weight: bold; }}
.neutral-val {{ color: #6c7086; text-align: right; }}
caption {{ caption-side: bottom; padding: 8px; color: #6c7086; font-size: 11px; }}
</style></head><body>
<h2> Perf Comparison: Before vs After</h2>
<table>
<tr><th>Δ</th><th>Function</th><th>Before</th><th>After</th><th>Change</th></tr>
{rows}</table>
</body></html>"#, rows = rows)
}

// ---- Help page ----

const HELP_HTML: &str = r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Perf Annotations</title>
<style>
body { font-family: sans-serif; margin: 20px; background: #1e1e2e; color: #cdd6f4; max-width: 800px; }
h1 { color: #f5c2e7; }
h2 { color: #89b4fa; }
code { background: #313244; padding: 2px 6px; border-radius: 4px; font-size: 13px; }
pre { background: #181825; padding: 12px; border-radius: 6px; overflow-x: auto; }
.section { background: #313244; padding: 12px 16px; border-radius: 8px; margin: 12px 0; }
.section h3 { margin-top: 0; color: #a6e3a1; }
form { margin: 16px 0; }
textarea { background: #181825; border: 1px solid #45475a; color: #cdd6f4; padding: 8px; border-radius: 4px; width: 100%; font-family: 'Fira Code', monospace; font-size: 13px; }
button { background: #89b4fa; border: none; padding: 8px 20px; border-radius: 6px; cursor: pointer; font-weight: bold; margin-top: 8px; }
button:hover { background: #b4d0fb; }
label { display: block; margin: 8px 0; color: #a6adc8; }
input[type="text"] { background: #181825; border: 1px solid #45475a; color: #cdd6f4; padding: 4px 8px; border-radius: 4px; }
</style></head><body>
<h1>📊 Perf Annotations</h1>
<p>Annotate source code with profiler data. Paste performance output alongside source code to see hot lines highlighted.</p>

<div class="section">
<h3>🔍 Input Formats</h3>
<p><strong>Folded stacks</strong> (from flamegraph/inferno):</p>
<pre>main;loop 10
main;loop;work 5
main;init 3</pre>
<p><strong>Perf report</strong> (from <code>perf report</code> or <code>perf annotate</code>):</p>
<pre>45.2%  compute_hot_path
22.1%  parse_input
12.0%  render_frame</pre>
</div>

<div class="section">
<h3>📝 Usage</h3>
<form action="/plugin/perf_annotations/test" method="POST">
  <input type="hidden" name="action" value="annotate">
  <label>Perf data (folded stacks or perf report):</label>
  <textarea name="data" rows="6" placeholder="main;loop 10&#10;main;loop;work 5">main;loop 10
main;loop;work 5
main;init 3
core;parse 12
core;parse;tokenize 8
render;draw 7</textarea>
  <label>Source code (optional — paste below for line annotations):</label>
  <textarea name="source" rows="8" placeholder="fn main() {&#10;    loop {&#10;        work();&#10;    }&#10;    init();&#10;}">fn main() {
    loop {
        work();
    }
    init();
}

fn parse(input: &str) {
    tokenize(input);
}</textarea>
  <label>Source language: <input type="text" name="source_lang" value="rust" style="width:80px"></label>
  <button type="submit">Annotate</button>
</form>
</div>

<div class="section">
<h3>🎯 Actions</h3>
<table>
<tr><td><code>action=annotate</code></td><td>Annotate source with perf data</td></tr>
<tr><td><code>action=functions</code></td><td>List hot functions only</td></tr>
<tr><td><code>action=compare</code></td><td>Compare two perf datasets (use <code>---BEFORE---</code> / <code>---AFTER---</code> separator)</td></tr>
</table>
</div>

<div class="section">
<h3>⚡ Quick test</h3>
<pre>curl -X POST http://localhost:8090/plugin/perf_annotations/test \
  -H 'Content-Type: application/json' \
  -d '{"action":"functions","data":"main;loop 10\nmain;loop;work 5\nmain;init 3"}'</pre>
</div>
</body></html>"#;
