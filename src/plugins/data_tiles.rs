// Data tiles — read and visualize Parquet, CSV, DAG-CBOR CAR, file lists, perf data
// Each row in any data source can be interpreted as a new tile (MASL row→tile transform).
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::path::Path;

pub struct DataTilesPlugin;

impl DataTilesPlugin {
    pub fn new() -> Self { Self }

    /// Discover data files by extension across the filesystem
    fn discover_files(extensions: &[&str], max: usize) -> Vec<(String, String, String)> {
        let mut files = Vec::new();
        for ext in extensions {
            let output = std::process::Command::new("locate")
                .args(["-r", &format!("\\.{}$", ext)])
                .output().ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .unwrap_or_default();

            for line in output.lines().filter(|l| !l.is_empty()).take(max / extensions.len().max(1)) {
                let path = line.to_string();
                let name = Path::new(&path).file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| "?".to_string());
                let size = std::fs::metadata(&path).map(|m| format_size(m.len())).unwrap_or_default();
                files.push((name, path, size));
            }
        }
        files
    }

    /// Read a CSV file and return rows
    fn read_csv(path: &str, max_rows: usize) -> Result<(Vec<String>, Vec<Vec<String>>), String> {
        let content = std::fs::read_to_string(path).map_err(|e| format!("read: {}", e))?;
        let mut lines = content.lines();

        let headers: Vec<String> = lines.next()
            .map(|l| l.split(',').map(|s| s.trim().to_string()).collect())
            .unwrap_or_default();

        let mut rows = Vec::new();
        for line in lines.take(max_rows) {
            let fields: Vec<String> = line.split(',').map(|s| s.trim().to_string()).collect();
            if fields.len() == headers.len() || headers.is_empty() {
                rows.push(fields);
            }
        }
        Ok((headers, rows))
    }

    /// Read a CAR file and list blocks
    fn read_car(path: &str, max_blocks: usize) -> Result<(Vec<u8>, Vec<HashMap<String, String>>), String> {
        let data = std::fs::read(path).map_err(|e| format!("read: {}", e))?;

        // Parse minimal CAR header
        let mut blocks = Vec::new();
        let mut pos = 0usize;

        // CARv1: [varint header_len] [header] [varint block_len] [CID] [data] ...
        while pos < data.len() && blocks.len() < max_blocks {
            let remaining = &data[pos..];
            if remaining.len() < 2 { break; }

            // Try to decode varint length
            let mut len = 0u64;
            let mut shift = 0;
            let mut bytes_read = 0;
            for &b in remaining {
                len |= ((b & 0x7f) as u64) << shift;
                shift += 7;
                bytes_read += 1;
                if b & 0x80 == 0 { break; }
            }

            if bytes_read == 0 || len as usize > remaining.len() {
                break;
            }

            pos += bytes_read;
            if pos + (len as usize) > data.len() { break; }

            if blocks.len() == 0 {
                // Skip header
                pos += len as usize;
                continue;
            }

            let block_data = &data[pos..pos + len as usize];
            // First bytes are CID, extract hash for display
            let cid_hex = block_data.iter().take(8).map(|b| format!("{:02x}", b)).collect::<Vec<_>>().join("");

            let mut info = HashMap::new();
            info.insert("cid_prefix".to_string(), cid_hex);
            info.insert("size".to_string(), (len as usize).to_string());
            info.insert("offset".to_string(), pos.to_string());
            blocks.push(info);
            pos += len as usize;
        }

        Ok((data, blocks))
    }

    /// Read perf data file and extract events
    fn read_perf_data(path: &str) -> Result<HashMap<String, serde_json::Value>, String> {
        let mut info = HashMap::new();
        let metadata = std::fs::metadata(path).map_err(|e| format!("stat: {}", e))?;
        info.insert("size".to_string(), serde_json::json!(metadata.len()));
        info.insert("path".to_string(), serde_json::json!(path));

        // Try to get perf report header info
        if let Ok(output) = std::process::Command::new("perf")
            .args(["report", "--header-only", "-i", path])
            .output()
        {
            let header = String::from_utf8_lossy(&output.stdout);
            info.insert("header".to_string(), serde_json::json!(header.len().min(1000)));
            // Extract event count
            for line in header.lines() {
                if line.contains("Event count") || line.contains("# samples") {
                    info.insert("samples".to_string(), serde_json::json!(line.trim().to_string()));
                }
            }
        }
        Ok(info)
    }

    /// Read a file list (from find output)
    fn read_file_list(path: &str, max_lines: usize) -> Result<Vec<String>, String> {
        let content = std::fs::read_to_string(path).map_err(|e| format!("read: {}", e))?;
        Ok(content.lines().take(max_lines).map(|l| l.to_string()).collect())
    }
}

impl Plugin for DataTilesPlugin {
    fn name(&self) -> &str { "data" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Data tiles — read and visualize Parquet, CSV, CAR, perf, file lists. Each row becomes a new tile." }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("browse");
        let path = input.extra.get("path").cloned().unwrap_or_default();
        let format = input.extra.get("format").cloned().or_else(|| {
            Path::new(&path).extension().map(|e| e.to_string_lossy().to_string())
        }).unwrap_or_default();

        match action {
            "browse" => {
                // Group by extension
                let all_files = Self::discover_files(&["csv", "car", "parquet", "perf.data", "perf"], 500);
                let mut by_ext: HashMap<String, Vec<(String, String, String)>> = HashMap::new();
                for (n, p, s) in &all_files {
                    let ext = Path::new(p).extension().map(|e| e.to_string_lossy().to_string())
                        .or_else(|| {
                            if p.contains("perf") { Some("perf".to_string()) } else { None }
                        })
                        .unwrap_or_else(|| "other".to_string());
                    by_ext.entry(ext).or_default().push((n.clone(), p.clone(), s.clone()));
                }

                let mut html = String::from("<h1>📊 Data Tiles</h1><p>Browse data files by format. Each file becomes an inspectable tile.</p>");

                for (ext, files) in by_ext.iter() {
                    let icon = match ext.as_str() {
                        "csv" => "📋", "car" => "📦", "parquet" => "🗄️",
                        "perf" => "📊", _ => "📄",
                    };
                    html.push_str(&format!("<h3>{} .{} — {} files</h3><div class='data-grid' style='display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:8px'>", icon, ext, files.len()));

                    for (name, fpath, size) in files.iter().take(50) {
                        html.push_str(&format!(
                            r#"<div class="data-card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:10px">
<div style="font-size:13px;color:#58a6ff">{}</div>
<div style="font-size:11px;color:#8b949e">{}</div>
<div style="font-size:10px;color:#484f58">{}</div>
<a href="?action=view&path={}&format={}" style="font-size:11px">🔍 View</a>
</div>"#, name, size, fpath, fpath, ext
                        ));
                    }
                    html.push_str("</div>");
                }
                map.insert("html".to_string(), html);
            }
            "view" => {
                match format.as_str() {
                    "csv" => {
                        let (headers, rows) = Self::read_csv(&path, 100)?;
                        let mut html = format!("<h1>📋 CSV: <code>{}</code></h1><p>{} rows, {} columns</p><table style='width:100%;border-collapse:collapse'><tr>", path, rows.len(), headers.len());
                        for h in &headers { html.push_str(&format!("<th style='border:1px solid #30363d;padding:4px;font-size:12px'>{}</th>", h)); }
                        html.push_str("</tr>");
                        for (ri, row) in rows.iter().enumerate() {
                            html.push_str("<tr>");
                            for (ci, val) in row.iter().enumerate() {
                                let col_name = headers.get(ci).map(|s| s.as_str()).unwrap_or("col");
                                html.push_str(&format!(
                                    r#"<td style="border:1px solid #30363d;padding:4px;font-size:11px">
<a href="?action=row-tile&path={}&format=csv&row={}&col={}&value={}" style="color:#58a6ff">{}</a>
</td>"#, path, ri, ci, urlencode(val), val
                                ));
                            }
                            html.push_str("</tr>");
                        }
                        html.push_str("</table>");
                        // MASL row→tile: each cell links to create a new tile from its value
                        map.insert("html".to_string(), html);
                    }
                    "car" => {
                        let (_data, blocks) = Self::read_car(&path, 200)?;
                        let mut html = format!("<h1>📦 CAR: <code>{}</code></h1><p>{} blocks</p><table style='width:100%'><tr><th>#</th><th>CID Prefix</th><th>Size</th><th>Offset</th><th>Action</th></tr>", path, blocks.len());
                        for (i, block) in blocks.iter().enumerate() {
                            let cid = block.get("cid_prefix").map(|s| s.as_str()).unwrap_or("?");
                            let size = block.get("size").map(|s| s.as_str()).unwrap_or("?");
                            let off = block.get("offset").map(|s| s.as_str()).unwrap_or("?");
                            html.push_str(&format!(
                                "<tr><td>{}</td><td><code>{}</code></td><td>{}</td><td>{}</td>\
                                <td><a href=\"?action=row-tile&path={}&format=car&row={}&value={}\">🔍 Tile</a></td></tr>",
                                i, cid, size, off, path, i, cid
                            ));
                        }
                        html.push_str("</table>");
                        map.insert("html".to_string(), html);
                    }
                    "perf" | "perf.data" => {
                        let info = Self::read_perf_data(&path)?;
                        let mut html = format!("<h1>📊 Perf: <code>{}</code></h1><table style='width:100%'>", path);
                        for (k, v) in &info {
                            html.push_str(&format!("<tr><td>{}</td><td><code>{}</code></td></tr>", k, serde_json::to_string(v).unwrap_or_default()));
                        }
                        // Try to interpret a row as a perf tile
                        html.push_str("</table><a href=\"?action=row-tile&path={}&format=perf&row=0\">🔍 Open as Tile</a>");
                        map.insert("html".to_string(), html);
                    }
                    "filelist" | "txt" => {
                        let lines = Self::read_file_list(&path, 500)?;
                        let mut html = format!("<h1>📄 File List: <code>{}</code></h1><p>{} files</p><div style='max-height:500px;overflow:auto'>", path, lines.len());
                        for (i, line) in lines.iter().enumerate() {
                            // Each file path can itself become a tile
                            html.push_str(&format!(
                                "<div style='font-size:11px;padding:2px 0'><a href=\"?action=row-tile&path={}&format=filelist&row={}&value={}\">{}</a></div>",
                                path, i, urlencode(line), line
                            ));
                        }
                        html.push_str("</div>");
                        map.insert("html".to_string(), html);
                    }
                    _ => {
                        // Unknown format — show raw content
                        let content = std::fs::read(&path).unwrap_or_default();
                        let preview = String::from_utf8_lossy(&content[..content.len().min(2000)]);
                        map.insert("html".to_string(), format!(
                            "<h1>📄 File: <code>{}</code></h1><pre style='max-height:500px;overflow:auto'>{}</pre>",
                            path, preview
                        ));
                    }
                }
            }
            "row-tile" => {
                // MASL row→tile transform: interpret a single row/block as a new tile
                let row: usize = input.extra.get("row").and_then(|r| r.parse().ok()).unwrap_or(0);
                let col: usize = input.extra.get("col").and_then(|c| c.parse().ok()).unwrap_or(0);
                let value = input.extra.get("value").cloned().unwrap_or_default();

                let mut html = format!(
                    r#"<h1>🧩 MASL Tile from Row {}</h1>
<div class="masl-tile" style="background:#1f2937;border:1px solid #58a6ff;border-radius:8px;padding:15px">
<h3>Source: <code>{}</code></h3>
<p>Format: {} | Row: {} | Col: {}</p>
<div style="margin:10px 0;padding:10px;background:#0d1117;border-radius:4px">
<pre>{}</pre>
</div>
<p>This value can be interpreted as:</p>
<ul>
<li><a href="/plugin/data?action=view&path={}" target="_blank">📄 Open as Data Tile</a></li>
<li><a href="/plugin/plantuml?action=render" target="_blank">📐 Render as PlantUML</a></li>
<li><a href="/plugin/lean?action=verify" target="_blank">🏛️ Verify as Lean</a></li>
<li><a href="/plugin/zombie?action=analyze" target="_blank">🧟 Analyze as Rust</a></li>
<li><a href="/plugin/git?action=repo&path={}" target="_blank">📦 Open as Git Repo</a></li>
</ul>
</div>
<a href="?action=view&path={}&format={}">← Back to file</a>"#,
                    row, path, format, row, col, value, value, value, path, format
                );
                map.insert("html".to_string(), html);
            }
            _ => {
                map.insert("error".to_string(), format!("Unknown action: {}", action));
            }
        }
        Ok(map)
    }
}

fn urlencode(s: &str) -> String {
    s.chars().map(|c| match c {
        'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' | '/' => c.to_string(),
        _ => format!("%{:02X}", c as u8),
    }).collect()
}

fn format_size(bytes: u64) -> String {
    if bytes < 1024 { format!("{} B", bytes) }
    else if bytes < 1024*1024 { format!("{:.1} KB", bytes as f64 / 1024.0) }
    else if bytes < 1024*1024*1024 { format!("{:.1} MB", bytes as f64 / (1024.0*1024.0)) }
    else { format!("{:.1} GB", bytes as f64 / (1024.0*1024.0*1024.0)) }
}
