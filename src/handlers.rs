// Handlers - Request handlers for kant-pastebin microservice
use actix_web::{web, HttpResponse, Result};
use crate::model::{Paste, Response, PasteIndex};
use crate::{view, storage};
use chrono::Utc;
use sha2::{Sha256, Digest};
use std::{fs, env, process::Command};
use utoipa::ToSchema;

fn slugify(s: &str) -> String {
    s.chars()
        .map(|c| if c.is_alphanumeric() { c.to_ascii_lowercase() } else { '_' })
        .collect::<String>()
        .split('_')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("_")
}

fn extract_ngrams(text: &str, n: usize, top: usize) -> Vec<(String, usize)> {
    use std::collections::HashMap;
    let words: Vec<&str> = text.split_whitespace().collect();
    let mut ngram_counts: HashMap<String, usize> = HashMap::new();
    
    for i in 0..words.len().saturating_sub(n - 1) {
        let ngram = words[i..i + n].join(" ").to_lowercase();
        *ngram_counts.entry(ngram).or_insert(0) += 1;
    }
    
    let mut ngrams: Vec<(String, usize)> = ngram_counts.into_iter().collect();
    ngrams.sort_by(|a, b| b.1.cmp(&a.1));
    ngrams.truncate(top);
    ngrams
}

fn ipfs_add(content: &str) -> Option<String> {
    use std::io::Write;
    
    let mut child = Command::new("ipfs")
        .args(&["add", "-Q", "--pin=false"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .ok()?;
    
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(content.as_bytes()).ok()?;
    }
    
    let output = child.wait_with_output().ok()?;
    String::from_utf8(output.stdout).ok().map(|s| s.trim().to_string())
}

/// GET / - Home page
pub async fn index(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    let reply_to = query.get("reply_to").map(|s| s.as_str()).unwrap_or("");
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    
    let html = format!(r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Kant Pastebin</title>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
textarea{{width:100%;height:300px;background:#111;color:#0f0;border:1px solid #0f0;padding:10px;font-family:monospace}}
input{{background:#111;color:#0f0;border:1px solid #0f0;padding:5px;width:100%}}
button{{background:#0f0;color:#000;border:none;padding:10px 20px;cursor:pointer;font-weight:bold}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
.nav a{{margin-right:15px}}
</style>
</head><body>
<div class="nav">
<a href="{}/">🏠 Home</a>
<a href="{}/browse">📚 Browse</a>
<a href="{}/openapi.json">📖 API</a>
</div>
<h1>📋 Kant Pastebin</h1>
<p>UUCP + zkTLS + IPFS</p>
<form id="form">
<input type="text" id="title" placeholder="Title" value=""><br><br>
<textarea id="content" placeholder="Paste content here..."></textarea><br><br>
<input type="text" id="keywords" placeholder="Keywords (comma separated)"><br><br>
<input type="hidden" id="reply_to" value="{}">
<button type="submit">📤 Share</button>
</form>
<div id="result"></div>
<br><a href="{}/browse">📚 Browse</a> | <a href="{}/openapi.json">📖 API</a> | <a href="{}/swagger-ui/">🔧 Swagger</a>
<script>
const basePath = '{}';
const form = document.getElementById('form');
const content = document.getElementById('content');

content.addEventListener('keydown', (e) => {{
  if (e.ctrlKey && e.key === 'Enter') {{
    form.dispatchEvent(new Event('submit'));
  }}
}});

form.onsubmit = async (e) => {{
  e.preventDefault();
  const btn = form.querySelector('button');
  btn.disabled = true;
  btn.textContent = '⏳ Posting...';
  
  try {{
    const data = {{
      content: content.value,
      title: document.getElementById('title').value || undefined,
      keywords: document.getElementById('keywords').value.split(',').map(s=>s.trim()).filter(s=>s),
      reply_to: document.getElementById('reply_to').value || undefined
    }};
    
    const res = await fetch(basePath + '/paste', {{
      method: 'POST',
      headers: {{'Content-Type': 'application/json'}},
      body: JSON.stringify(data)
    }});
    
    if (!res.ok) throw new Error('Failed: ' + res.status);
    
    const json = await res.json();
    
    // Show IPFS CID if available
    if (json.ipfs_cid) {{
      const msg = `✅ Posted to IPFS: ${{json.ipfs_cid}}\\n\\nAccess via: ipfs cat ${{json.ipfs_cid}}`;
      if (confirm(msg + '\\n\\nClick OK to view paste')) {{
        window.location = basePath + json.url;
      }}
    }} else {{
      window.location = basePath + json.url;
    }}
  }} catch(err) {{
    alert('Error: ' + err.message);
    btn.disabled = false;
    btn.textContent = '📤 Share';
  }}
}};
</script>
</body></html>"#, base_path, base_path, base_path, reply_to, base_path, base_path, base_path, base_path);
    
    Ok(HttpResponse::Ok().content_type("text/html; charset=utf-8").body(html))
}

/// POST /paste - Create paste
#[utoipa::path(
    post,
    path = "/paste",
    request_body = Paste,
    responses(
        (status = 200, description = "Paste created", body = Response)
    )
)]
pub async fn create_paste(data: web::Json<Paste>) -> Result<HttpResponse> {
    let paste = data.into_inner();
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let title = paste.title.as_deref().unwrap_or("untitled");
    let keywords = paste.keywords.clone().unwrap_or_default();
    
    let content = paste.content.as_deref().unwrap_or("");
    
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    
    if std::path::Path::new(&cid_file).exists() {
        let existing_id = fs::read_to_string(&cid_file).unwrap_or_else(|_| format!("paste_{}", ts));
        return Ok(HttpResponse::Ok().json(Response {
            id: existing_id.clone(),
            cid: local_cid.clone(),
            ipfs_cid: None,
            witness,
            url: format!("/paste/{}", existing_id),
            permalink: format!("/paste/{}", local_cid),
            uucp_path: "".to_string(),
            reply_to: paste.reply_to.clone(),
        }));
    }
    
    let slug_title = slugify(title);
    let slug_keywords = keywords.iter().map(|k| slugify(k)).collect::<Vec<_>>().join("_");
    let filename = if slug_keywords.is_empty() {
        format!("{}_{}.txt", ts, slug_title)
    } else {
        format!("{}_{}_{}.txt", ts, slug_title, slug_keywords)
    };
    
    let id = filename.trim_end_matches(".txt").to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);
    
    // Push to IPFS
    let ipfs_cid = ipfs_add(content);
    
    let paste_content = format!("--- {} ---\nTitle: {}\nKeywords: {}\nCID: {}\nWitness: {}\nIPFS: {}\n\n{}\n",
        id, title, keywords.join(", "), local_cid, witness, ipfs_cid.as_deref().unwrap_or(""), content);
    fs::write(&uucp, paste_content).ok();
    fs::write(&cid_file, &id).ok();
    
    let ngrams = extract_ngrams(content, 3, 10);
    
    let index_entry = PasteIndex {
        id: id.clone(),
        title: title.to_string(),
        keywords,
        cid: local_cid.clone(),
        witness: witness.clone(),
        timestamp: ts,
        filename: filename.clone(),
        ngrams,
        ipfs_cid: ipfs_cid.clone(),
        reply_to: paste.reply_to.clone(),
        size: content.len(),
        uucp_path: uucp.clone(),
    };
    
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let index_line = format!("{}\n", serde_json::to_string(&index_entry).unwrap());
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&index_file)
        .and_then(|mut f| std::io::Write::write_all(&mut f, index_line.as_bytes()))
        .ok();
    
    Ok(HttpResponse::Ok().json(Response {
        id: id.clone(),
        cid: local_cid,
        ipfs_cid,
        witness,
        url: format!("/paste/{}", id),
        permalink: format!("/paste/{}", id),
        uucp_path: uucp,
        reply_to: paste.reply_to,
    }))
}

/// GET /paste/{id} - View paste
#[utoipa::path(
    get,
    path = "/paste/{id}",
    params(
        ("id" = String, Path, description = "Paste ID")
    ),
    responses(
        (status = 200, description = "Paste HTML")
    )
)]
pub async fn get_paste(path: web::Path<String>, req: actix_web::HttpRequest) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let base_url = env::var("BASE_URL").unwrap_or_else(|_| "http://localhost:8090".to_string());
    
    // Load index for prev/next/related
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let entries: Vec<PasteIndex> = fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .collect();
    
    let current_idx = entries.iter().position(|e| e.id == id);
    let prev_id = current_idx.and_then(|i| if i > 0 { entries.get(i - 1).map(|e| &e.id) } else { None });
    let next_id = current_idx.and_then(|i| entries.get(i + 1).map(|e| &e.id));
    
    let content = if let Ok(dir_entries) = fs::read_dir(&uucp_dir) {
        dir_entries
            .filter_map(std::result::Result::ok)
            .find(|e| {
                let name = e.file_name();
                let name_str = name.to_string_lossy();
                name_str.contains(&id) && name_str.ends_with(".txt")
            })
            .and_then(|e| fs::read_to_string(e.path()).ok())
    } else {
        None
    };
    
    match content {
        Some(content) => {
            // Parse structured header
            let mut headers = std::collections::HashMap::new();
            let mut body_start = 0;
            
            for (i, line) in content.lines().enumerate() {
                if line.is_empty() && i > 0 {
                    body_start = content.lines().take(i + 1).map(|l| l.len() + 1).sum();
                    break;
                }
                if let Some((key, value)) = line.split_once(':') {
                    headers.insert(key.trim(), value.trim());
                }
            }
            
            let title = headers.get("Title").map(|s| *s).unwrap_or(&id);
            let cid = headers.get("CID").map(|s| *s).unwrap_or("");
            let ipfs_cid = headers.get("IPFS").or(headers.get("ipfs_cid")).map(|s| *s)
                .or_else(|| {
                    // Fallback to index if not in file header
                    entries.iter().find(|e| e.id == id).and_then(|e| e.ipfs_cid.as_deref())
                });
            let body = &content[body_start..];
            
            let ipfs_cmd = if let Some(ipfs) = ipfs_cid {
                format!("ipfs cat {}", ipfs)
            } else {
                "# No IPFS CID available".to_string()
            };
            
            let file_cmd = format!("cat {}/{}.txt", uucp_dir, id);
            let curl_cmd = format!("curl {}/raw/{}", base_url, id);
            let reply_cmd = format!("curl -X POST {}/paste -H 'Content-Type: application/json' -d '{{\"content\":\"...\",\"reply_to\":\"{}\"}}'", base_url, id);
            
            // Find related posts by keywords
            let current_entry = entries.iter().find(|e| e.id == id);
            let related: Vec<&PasteIndex> = if let Some(curr) = current_entry {
                entries.iter()
                    .filter(|e| e.id != id && e.keywords.iter().any(|k| curr.keywords.contains(k)))
                    .take(5)
                    .collect()
            } else {
                vec![]
            };
            
            let prev_link = prev_id.map(|pid| format!(r#"<a href="{}/paste/{}">← Prev</a>"#, base_path, pid)).unwrap_or_else(|| "".to_string());
            let next_link = next_id.map(|nid| format!(r#"<a href="{}/paste/{}">Next →</a>"#, base_path, nid)).unwrap_or_else(|| "".to_string());
            
            let related_html = if !related.is_empty() {
                let items: String = related.iter().map(|e| {
                    format!(r#"<div style="padding:5px"><a href="{}/paste/{}">{}</a></div>"#, base_path, e.id, e.title)
                }).collect();
                format!(r#"<h3>Related Posts:</h3><div style="background:#111;padding:10px;margin:10px 0">{}</div>"#, items)
            } else {
                "".to_string()
            };
            
            let html = format!(r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<title>{}</title>
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
.nav{{background:#111;padding:10px;margin:10px 0;border:1px solid #0f0}}
pre{{background:#111;padding:20px;border:1px solid #0f0;overflow-x:auto}}
.reply-btn{{background:#0f0;color:#000;border:none;padding:5px 10px;cursor:pointer;margin:5px;display:inline-block}}
.cmd{{background:#111;padding:10px;margin:5px 0;border-left:3px solid #ff0;cursor:pointer;font-size:12px}}
.cmd:hover{{background:#222}}
.qr-modal{{position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#fff;padding:20px;border:3px solid #0f0;z-index:1000;display:none}}
.qr-modal h3{{color:#000}}
</style>
</head><body>
<div class="nav"><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/raw/{}">📄 Raw</a> | {} {}</div>
<h1>{}</h1>
<a class="reply-btn" href="{}/?reply_to={}">💬 Reply</a>
<button class="reply-btn" onclick="navigator.clipboard.writeText(document.querySelector('pre').textContent);this.textContent='✅ Copied'">📋 Copy</button>
<button class="reply-btn" onclick="navigator.share({{title:'{}',text:document.querySelector('pre').textContent,url:window.location.href}})">🔗 Share</button>
<button class="reply-btn" onclick="showQR()">📱 QR Code</button>
<button class="reply-btn" onclick="shareRDFa()">🔗 RDFa URL</button>

<h3>Access Commands:</h3>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'">$ {}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'">$ {}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'">$ {}</div>

<h3>Content:</h3>
<pre>{}</pre>
{}
<div id="qrModal" class="qr-modal">
  <h3>{}</h3>
  <canvas id="qrcode"></canvas><br>
  <button onclick="document.getElementById('qrModal').style.display='none'">Close</button>
</div>
<script>
const ipfsCid = '{}';
const pasteUrl = window.location.href;
const title = '{}';

function showQR() {{
  const modal = document.getElementById('qrModal');
  modal.style.display = 'block';
  const qr = qrcode(0, 'M');
  qr.addData(pasteUrl);
  qr.make();
  const canvas = document.getElementById('qrcode');
  const ctx = canvas.getContext('2d');
  const cells = qr.getModuleCount();
  const cellSize = 256 / cells;
  canvas.width = 256;
  canvas.height = 256;
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, 256, 256);
  ctx.fillStyle = '#000';
  for (let row = 0; row < cells; row++) {{
    for (let col = 0; col < cells; col++) {{
      if (qr.isDark(row, col)) {{
        ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
      }}
    }}
  }}
}}

function shareRDFa() {{
  const rdfaUrl = pasteUrl + '#typeof=schema:CreativeWork&property=schema:name=' + encodeURIComponent(title) + (ipfsCid ? '&property=schema:identifier=' + encodeURIComponent(ipfsCid) : '');
  navigator.clipboard.writeText(rdfaUrl);
  alert('✅ RDFa URL copied:\\n\\n' + rdfaUrl);
}}
</script>
<script src="/static/a11y.js"></script>
</body></html>"#, 
                title, 
                base_path, base_path, base_path, id, prev_link, next_link,
                title, 
                base_path, id, title,
                ipfs_cmd, ipfs_cmd,
                file_cmd, file_cmd,
                curl_cmd, curl_cmd,
                body,
                related_html,
                title,
                ipfs_cid.unwrap_or(""),
                title
            );
            
            Ok(HttpResponse::Ok().content_type("text/html; charset=utf-8").body(html))
        }
        None => Ok(HttpResponse::NotFound().body("Paste not found")),
    }
}

/// GET /preview/{id} - Preview paste with rendering
pub async fn preview_paste(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let content = storage::load_content(&id).unwrap_or_else(|| "Paste not found".to_string());
    Ok(HttpResponse::Ok().content_type("text/html").body(view::render_preview(&id, &content)))
}

/// GET /raw/{id} - Raw text
pub async fn get_raw(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let content = storage::load_content(&id).unwrap_or_else(|| "Paste not found".to_string());
    Ok(HttpResponse::Ok().content_type("text/plain").body(content))
}

/// GET /browse - List pastes
#[utoipa::path(
    get,
    path = "/browse",
    params(
        ("q" = Option<String>, Query, description = "Search query")
    ),
    responses(
        (status = 200, description = "Browse HTML")
    )
)]
pub async fn browse(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let index_file = format!("{}/index.jsonl", uucp_dir);
    
    let search = query.get("q").map(|s| s.to_lowercase());
    
    let entries: Vec<PasteIndex> = fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .filter(|entry| {
            if let Some(ref q) = search {
                entry.title.to_lowercase().contains(q) || 
                entry.keywords.iter().any(|k| k.to_lowercase().contains(q))
            } else {
                true
            }
        })
        .collect();
    
    let search_box = if let Some(q) = search {
        format!(r#"<form method="get"><input type="text" name="q" value="{}" placeholder="Search..." style="padding:5px;width:300px"><button type="submit">🔍</button></form>"#, q)
    } else {
        r#"<form method="get"><input type="text" name="q" placeholder="Search..." style="padding:5px;width:300px"><button type="submit">🔍</button></form>"#.to_string()
    };
    
    let items: String = entries.iter().rev().take(50).map(|e| {
        format!(r#"<div style="border-bottom:1px solid #333;padding:10px"><a href="{}/paste/{}">{}</a> <span style="color:#666">{}</span></div>"#, 
            base_path, e.id, e.title, e.timestamp)
    }).collect();
    
    let html = format!(r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Browse Pastes</title>
<style>body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}</style>
</head><body>
<div><a href="{}/">🏠 Home</a></div>
<h1>Browse Pastes</h1>
{}
<div style="margin-top:20px">{}</div>
</body></html>"#, base_path, search_box, items);
    
    Ok(HttpResponse::Ok().content_type("text/html; charset=utf-8").body(html))
}
