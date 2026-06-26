// Handlers - Request handlers for kant-pastebin microservice
use crate::model::{
    Paste, PasteIndex, Response, SplitMode, SplitProfile, SplitProfileRequest, SplitUnit,
    ThreadPost,
};
use crate::plugins;
use crate::plugins::pipelight;
use crate::{ipfs, plugin, storage, tagging, view};
use actix_web::{web, HttpRequest, HttpResponse, Result};
use chrono::Utc;
use ciborium;
use log::{debug, error, warn};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::Path;
use std::{collections::HashMap, env, fs};

// ─── Full error capture — saves replayable test case ───────────────
/// Captures the full request details on failure and writes a replayable
/// test case document to /var/log/nginx/error-docs/cases/.
fn capture_error_case(
    handler: &str,
    req: &HttpRequest,
    body_preview: &str,
    status: u16,
    resp_body: &str,
    err_detail: &str,
) {
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp/pastebin".to_string());
    let cases_dir = format!("{}/../error-cases", uucp_dir);
    let _ = fs::create_dir_all(&cases_dir);

    let client = req.peer_addr().map(|a| a.to_string()).unwrap_or_else(|| "unknown".to_string());
    let method = req.method().to_string();
    let uri = req.uri().to_string();

    // Build replayable curl command
    let mut curl = format!("curl -sk -X {method}\
", method = method);
    for (k, v) in req.headers().iter() {
        if k.as_str().to_lowercase() == "host" { continue; }
        if k.as_str().to_lowercase() == "content-length" { continue; }
        let val = v.to_str().unwrap_or("<binary>");
        curl.push_str(&format!("  -H '{k}: {val}'\
", k = k, val = val));
    }
    if status >= 400 && !body_preview.is_empty() {
        // Include body as --data-binary for replay
        curl.push_str(&format!("  --data-binary '{}'", body_preview.chars().take(200).collect::<String>()));
    }
    curl.push_str(&format!(" https://solana.solfunmeme.com{uri}", uri = uri));

    let headers_dump = req.headers().iter()
        .map(|(k, v)| format!("  {}: {}", k, v.to_str().unwrap_or("<binary>")))
        .collect::<Vec<_>>()
        .join("\n");

    let doc = format!(
        "---\ncase_id: case_{ts}_{handler}\ntimestamp: {ts}\nhandler: {handler}\nstatus: {status}\n---\n\n# Error Case: {handler}\n\n**Timestamp**: {ts}\n**Client**: {client}\n**Method**: {method}\n**URI**: {uri}\n**Status**: {status}\n**Detail**: {err_detail}\n\n## Replay Command\n\n```bash\n{curl}\n```\n\n## Request Headers\n\n```\n{headers_dump}\n```\n\n## Request Body Preview\n\n```\n{body_preview}\n```\n\n## Response Body\n\n```\n{resp_body}\n```\n\n---\n*Auto-captured by kant-pastebin error case logger*\n",
        ts = ts,
        handler = handler,
        status = status,
        client = client,
        method = method,
        uri = uri,
        err_detail = err_detail,
        curl = curl,
        headers_dump = headers_dump,
        body_preview = if body_preview.is_empty() { "(empty)".to_string() } else { body_preview.chars().take(500).collect() },
        resp_body = if resp_body.is_empty() { "(empty)".to_string() } else { resp_body.chars().take(1000).collect() },
    );

    let filename = format!("{}/case_{}_{}.md", cases_dir, ts, handler.replace(" ", "_").to_lowercase());
    match fs::write(&filename, &doc) {
        Ok(_) => warn!("[error-case] Saved replayable case: {}", filename),
        Err(e) => error!("[error-case] Failed to write {}: {}", filename, e),
    }
}

// ─── Helper: basic HTML lint ──────────────────────────────────────────
fn lint_html(html: &str) -> Vec<String> {
    let mut issues = Vec::new();
    let lower = html.to_lowercase();
    if !lower.contains("<html") || !lower.contains("</html>") {
        issues.push("missing <html> root".to_string());
    }
    if !lower.contains("<head>") || !lower.contains("</head>") {
        issues.push("missing <head>".to_string());
    }
    if !lower.contains("<body>") || !lower.contains("</body>") {
        issues.push("missing <body>".to_string());
    }
    if !lower.contains("<title>") || !lower.contains("</title>") {
        issues.push("missing <title>".to_string());
    }
    if !lower.contains("<meta charset") {
        issues.push("missing charset meta".to_string());
    }
    if !lower.contains("<pre") && !lower.contains("<pre>") {
        issues.push("missing <pre> content container".to_string());
    }
    let open_tags = html.matches("<select").count()
        + html.matches("<div").count()
        + html.matches("<script").count()
        + html.matches("<style").count();
    let close_tags = html.matches("</select>").count()
        + html.matches("</div>").count()
        + html.matches("</script>").count()
        + html.matches("</style>").count();
    if open_tags != close_tags {
        issues.push(format!("unbalanced tags: open={} close={}", open_tags, close_tags));
    }
    issues
}

// ─── Helper: append an entry to index.jsonl ──────────────────────────
/// Log an error case as an individual research document in /var/log/nginx/error-docs/
fn log_error_case(handler: &str, req: &Option<HttpRequest>, field_names: &[&str], err_msg: &str) {
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let slug = handler.replace(" ", "_").to_lowercase();
    let case_file = format!("/var/log/nginx/error-docs/case_{}_{}.md", ts, slug);

    let client = req.as_ref().map(|r| {
        r.peer_addr().map(|a| a.to_string()).unwrap_or_else(|| "unknown".to_string())
    }).unwrap_or_else(|| "unknown".to_string());

    let method = req.as_ref().map(|r| r.method().to_string()).unwrap_or_else(|| "?".to_string());
    let uri = req.as_ref().map(|r| r.uri().to_string()).unwrap_or_else(|| "?".to_string());
    let headers = req.as_ref().map(|r| {
        r.headers().iter()
            .map(|(k, v)| format!("  {}: {}", k, v.to_str().unwrap_or("<binary>")))
            .collect::<Vec<_>>()
            .join("\n")
    }).unwrap_or_else(|| "  (none)".to_string());

    let fields = field_names.iter().map(|f| format!("  - {}", f)).collect::<Vec<_>>().join("\n");

    let doc = format!(
        "---\ncase_id: {ts}\nhandler: {handler}\nseverity: error\n---\n\n# Error Case: {handler}\n\n**Timestamp**: {ts}\n**Client**: {client}\n**Method**: {method}\n**URI**: {uri}\n**Error**: {err_msg}\n\n## Request Headers\n\n```\n{headers}\n```\n\n## Fields Received\n\n{fields}\n\n## Resolution\n\n- [ ] Investigate root cause\n- [ ] Apply fix\n- [ ] Verify\n",
        ts = ts,
        handler = handler,
        client = client,
        method = method,
        uri = uri,
        err_msg = err_msg,
        headers = headers,
        fields = fields,
    );

    match std::fs::write(&case_file, &doc) {
        Ok(_) => warn!("[error-case] Created: {}", case_file),
        Err(e) => error!("[error-case] Failed to write {}: {}", case_file, e),
    }
}

fn write_index_entry(
    uucp_dir: &str,
    id: &str,
    title: &str,
    description: Option<&str>,
    keywords: Vec<String>,
    cid: &str,
    witness: &str,
    filename: &str,
    size: usize,
    ipfs_cid: Option<String>,
    reply_to: Option<String>,
    root: Option<String>,
) {
    let ngrams = tagging::extract_ngrams(&format!("{} {}", title, keywords.join(" ")), 3, 10);
    let entry = PasteIndex {
        id: id.to_string(),
        title: title.to_string(),
        description: description.map(|s| s.to_string()),
        keywords,
        cid: cid.to_string(),
        witness: witness.to_string(),
        timestamp: Utc::now().format("%Y%m%d_%H%M%S").to_string(),
        filename: filename.to_string(),
        ngrams,
        ipfs_cid,
        reply_to,
        size,
        uucp_path: format!("{}/{}", uucp_dir, filename),
        root,
    };
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let line = format!("{}\n", serde_json::to_string(&entry).unwrap());
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&index_file)
        .and_then(|mut f| std::io::Write::write_all(&mut f, line.as_bytes()))
        .ok();
}

fn clean_field(value: &str) -> String {
    value.trim().to_string()
}

fn archive_name_title(name: &str) -> String {
    Path::new(name)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(name)
        .trim_end_matches(".tar.gz")
        .trim_end_matches(".tgz")
        .trim_end_matches(".tar.bz2")
        .trim_end_matches(".tbz2")
        .trim_end_matches(".tbz")
        .trim_end_matches(".tar.xz")
        .trim_end_matches(".txz")
        .trim_end_matches(".tar")
        .trim_end_matches(".zip")
        .trim_end_matches(".gz")
        .trim_end_matches(".bz2")
        .trim_end_matches(".xz")
        .trim_end_matches('.')
        .to_string()
}

fn archive_name_description(title: &str, name: &str, entries: usize, bytes: usize) -> String {
    if title.is_empty() {
        format!(
            "Uploaded archive {} with {} entries and {} bytes",
            name, entries, bytes
        )
    } else {
        format!("{}: {} entries, {} bytes", title, entries, bytes)
    }
}

fn file_description(name: &str, mime: &str, size: usize, data: &[u8]) -> String {
    if mime.starts_with("text/")
        || name.to_lowercase().ends_with(".html")
        || name.to_lowercase().ends_with(".json")
    {
        let text = String::from_utf8_lossy(data);
        tagging::extract_html_title(&text)
            .or_else(|| {
                let desc = tagging::auto_describe(&text);
                if desc.is_empty() {
                    None
                } else {
                    Some(desc)
                }
            })
            .unwrap_or_else(|| format!("Uploaded file: {} ({} bytes)", name, size))
    } else {
        format!("Uploaded file: {} ({} bytes, {})", name, size, mime)
    }
}

/// GET / - Home page
pub async fn index(
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let reply_to = query.get("reply_to").map(|s| s.as_str()).unwrap_or("");
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let version = option_env!("CARGO_PKG_VERSION").unwrap_or("0.1.0");
    let git_commit = option_env!("GIT_COMMIT").unwrap_or("unknown");
    let build_time = option_env!("BUILD_TIME").unwrap_or("unknown");

    let html = format!(
        r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Kant Pastebin</title>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
textarea{{width:100%;height:300px;background:#111;color:#0f0;border:1px solid #0f0;padding:10px;font-family:monospace}}
input{{background:#111;color:#0f0;border:1px solid #0f0;padding:5px;width:100%}}
button{{background:#0f0;color:#000;border:none;padding:10px 20px;cursor:pointer;font-weight:bold;margin-right:10px}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
.nav a{{margin-right:15px}}
</style>
</head><body>
<div class="nav">
<a href="{base_path}/">🏠 Home</a>
<a href="{base_path}/browse">📚 Browse</a>
<a href="{base_path}/threads">🧵 Threads</a>
<a href="{base_path}/gallery">🖼️ Gallery</a>
<a href="{base_path}/git-browse">📁 Git</a>
<a href="{base_path}/splitter/">✂️ Splitter</a>
<a href="{base_path}/openapi.json">📖 API</a>
</div>
<h1>📋 Kant Pastebin</h1>
<p>UUCP + zkTLS + IPFS</p>
<form id="form">
<input type="text" id="title" placeholder="Title" value=""><br><br>
<input type="text" id="description" placeholder="Description" value=""><br><br>
<textarea id="content" placeholder="Paste content here..."></textarea><br><br>
<input type="file" id="file" accept="image/*,.html,.json,.svg,.mth,.tar.gz,.tar.bz2,.tar.xz,.zip,.gz,.bz2,.xz"><br><br>
<input type="text" id="keywords" placeholder="Keywords (comma separated)"><br><br>
<input type="hidden" id="reply_to" value="{reply_to}">
<button type="submit">📤 Share</button>
<button type="button" onclick="preview()">👁️ Preview</button>
<button type="button" onclick="sendToSplitter()">✂️ Split</button>
</form>
<div id="result"></div>
<br><a href="{base_path}/browse">📚 Browse</a> | <a href="{base_path}/openapi.json">📖 API</a> | <a href="{base_path}/swagger-ui/">🔧 Swagger</a>
<div style="margin-top:20px;padding-top:10px;border-top:1px solid #0f0;font-size:0.8em;color:#080">kant-pastebin v{version} git:{git_commit} built:{build_time}</div>
<script>
const basePath = '{base_path}';
const form = document.getElementById('form');
const content = document.getElementById('content');

content.addEventListener('keydown', (e) => {{
  if (e.ctrlKey && e.key === 'Enter') {{
    form.dispatchEvent(new Event('submit'));
  }}
}});

function preview() {{
  const div = document.createElement('div');
  div.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:#0a0a0a;z-index:1000;overflow:auto;padding:20px;box-sizing:border-box';
  div.innerHTML = '<button onclick=\"this.parentElement.remove()\" style=\"position:sticky;top:10px;float:right\">✕ Close</button><pre style=\"white-space:pre-wrap;word-wrap:break-word\">' + content.value + '</pre>';
  document.body.appendChild(div);
}}

function sendToSplitter() {{
  localStorage.setItem('splitter-text', content.value);
  window.open('{base_path}/splitter/', '_blank');
}}

form.onsubmit = async (e) => {{
  e.preventDefault();
  const btn = form.querySelector('button');
  btn.disabled = true;
  btn.textContent = '⏳ Posting...';
  
  try {{
    const fileInput = document.getElementById('file');
    let res;
    
    if (fileInput.files.length > 0) {{
      const fd = new FormData();
      const fn = fileInput.files[0].name;
      fd.append('file', fileInput.files[0]);
      fd.append('title', document.getElementById('title').value || '');
      fd.append('description', document.getElementById('description').value || '');
      const isArchive = fn.endsWith('.tar.gz') || fn.endsWith('.tar.bz2') || fn.endsWith('.tar.xz') || fn.endsWith('.zip') || fn.endsWith('.gz') || fn.endsWith('.bz2') || fn.endsWith('.xz');
      res = await fetch(basePath + (isArchive ? '/upload-archive' : '/upload'), {{ method: 'POST', body: fd }});
    }} else {{
      const data = {{
        content: content.value,
        title: document.getElementById('title').value || undefined,
        description: document.getElementById('description').value || undefined,
        keywords: document.getElementById('keywords').value.split(',').map(s=>s.trim()).filter(s=>s),
        reply_to: document.getElementById('reply_to').value || undefined
      }};
      res = await fetch(basePath + '/paste', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify(data)
      }});
    }}
    
    if (!res.ok) throw new Error('Failed: ' + res.status);
    const json = await res.json();
    window.location = basePath + json.url;
  }} catch(err) {{
    alert('Error: ' + err.message);
    btn.disabled = false;
    btn.textContent = '📤 Share';
  }}
}};
</script>
</body></html>"#
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// POST /paste - Create paste (JSON body)
#[utoipa::path(
    post,
    path = concat!(env!("BASE_PATH"), "/paste"),
    request_body = Paste,
    responses(
        (status = 200, description = "Paste created", body = Response)
    )
)]
pub async fn create_paste(data: web::Json<Paste>) -> Result<HttpResponse> {
    create_paste_inner(data.into_inner()).await
}

/// POST /paste - Create paste (URL-encoded form body)
pub async fn create_paste_form(form: web::Form<Paste>) -> Result<HttpResponse> {
    create_paste_inner(form.into_inner()).await
}

/// POST /paste - Create paste (multipart form body — e.g. curl -F)
pub async fn create_paste_multipart(mut payload: actix_multipart::Multipart) -> Result<HttpResponse> {
    use actix_web::web::BytesMut;
    use futures_util::StreamExt as _;

    let mut content = String::new();
    let mut title = None;
    let mut description = None;
    let mut reply_to = None;

    while let Some(item) = payload.next().await {
        let mut field = item.map_err(|e| actix_web::error::ErrorBadRequest(e))?;
        let field_name = field.name().unwrap_or("").to_string();
        let mut buf: Vec<u8> = Vec::new();
        while let Some(chunk) = field.next().await {
            let data = chunk.map_err(|e| actix_web::error::ErrorBadRequest(e))?;
            buf.extend_from_slice(&data);
        }
        let val = String::from_utf8_lossy(&buf).to_string();
        match field_name.as_str() {
            "content" => content = val,
            "title" => title = Some(val),
            "description" => description = Some(val),
            "reply_to" => reply_to = Some(val),
            _ => {}
        }
    }

    if content.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "no content"})));
    }

    let paste = Paste {
        content: Some(content),
        cid: None,
        title,
        description,
        keywords: None,
        reply_to,
    };
    create_paste_inner(paste).await
}

async fn create_paste_inner(paste: Paste) -> Result<HttpResponse> {
    let content = paste.content.as_deref().unwrap_or("");

    // Detect Wikidata QID — trigger enrichment pipeline
    let trimmed = content.trim();
    if trimmed.starts_with('Q')
        && trimmed[1..].chars().all(|c| c.is_ascii_digit())
        && trimmed.len() >= 2
    {
        return enrich_qid(trimmed).await;
    }

    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();

    // Auto-generate title and tags
    let auto_tags = tagging::auto_tag(content);
    let html_title = tagging::extract_html_title(content);
    let auto_desc = tagging::auto_describe(content);
    let title_owned = paste
        .title
        .clone()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| {
            html_title.unwrap_or_else(|| {
                if !auto_tags.is_empty() {
                    auto_desc.clone()
                } else {
                    "untitled".to_string()
                }
            })
        });
    let title = title_owned.as_str();
    let description = paste
        .description
        .clone()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| auto_desc.clone());
    let keywords = paste.keywords.clone().unwrap_or_else(|| auto_tags);

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

    let slug_title = tagging::slugify(title);
    let slug_keywords = keywords
        .iter()
        .map(|k| tagging::slugify(k))
        .collect::<Vec<_>>()
        .join("_");
    let filename = if slug_keywords.is_empty() {
        format!("{}_{}.txt", ts, slug_title)
    } else {
        format!("{}_{}_{}.txt", ts, slug_title, slug_keywords)
    };

    let id = filename.trim_end_matches(".txt").to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);

    // Push to IPFS
    let ipfs_cid = ipfs::ipfs_add(content);
    let dasl_cid = crate::dasl::dasl_cid(content.as_bytes());

    let reply_to_str = paste.reply_to.as_deref().unwrap_or("");
    let section =
        erdfa_publish::sheaf::Section::new(content.as_bytes(), erdfa_publish::sheaf::Encoding::Raw);
    let paste_content = format!("--- {} ---\nTitle: {}\nDescription: {}\nKeywords: {}\nCID: {}\nWitness: {}\nIPFS: {}\nDASL: {}\nReply-To: {}\n{}\n\n{}\n\n{}\n",
        id, title, description, keywords.join(", "), local_cid, witness, ipfs_cid.as_deref().unwrap_or(""), dasl_cid, reply_to_str,
        erdfa_publish::sheaf::sheaf_header(&section),
        content, section.to_rdfa());
    fs::write(&uucp, paste_content).ok();
    fs::write(&cid_file, &id).ok();

    let ngrams = tagging::extract_ngrams(content, 3, 10);

    let index_entry = PasteIndex {
        id: id.clone(),
        title: if title == "untitled" {
            tagging::auto_describe(content)
        } else {
            title.to_string()
        },
        description: Some(description),
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
        root: None,
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

/// POST /upload - Upload file (multipart)
/// Save-first: write file to disk immediately, then return.
/// No NLP, no HTML extraction, no blocking calls in this handler.
pub async fn upload_file(req: HttpRequest, mut payload: actix_multipart::Multipart) -> Result<HttpResponse> {
    use actix_web::web::BytesMut;
    use futures_util::StreamExt as _;

    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let mut file_data: Vec<u8> = Vec::new();
    let mut orig_name = String::new();
    let mut user_title = String::new();
    let mut user_description = String::new();
    let mut content_text = String::new();

    while let Some(item) = payload.next().await {
        let mut field = item.map_err(|e| actix_web::error::ErrorBadRequest(e))?;
        let field_name = field.name().unwrap_or("").to_string();
        let mut buf: Vec<u8> = Vec::new();
        while let Some(chunk) = field.next().await {
            let data = chunk.map_err(|e| actix_web::error::ErrorBadRequest(e))?;
            buf.extend_from_slice(&data);
        }
        match field_name.as_str() {
            "file" => {
                orig_name = field
                    .content_disposition()
                    .and_then(|cd| cd.get_filename().map(|s| s.to_string()))
                    .unwrap_or_else(|| "upload".to_string());
                file_data = buf;
            }
            "content" => {
                content_text = String::from_utf8_lossy(&buf).to_string();
            }
            "title" => {
                user_title = clean_field(&String::from_utf8_lossy(&buf));
            }
            "description" => {
                user_description = clean_field(&String::from_utf8_lossy(&buf));
            }
            _ => {}
        }
    }

    // Accept either `file` field (binary upload) or `content` field (text paste)
    if file_data.is_empty() && content_text.is_empty() {
        let resp = serde_json::json!({"error": "no file"});
        let resp_body = serde_json::to_string(&resp).unwrap_or_default();
        capture_error_case("upload_file", &req, &format!("title={}", user_title), 400, &resp_body, "no file or content field in multipart upload");
        return Ok(HttpResponse::BadRequest().json(resp));
    }

    if file_data.is_empty() && !content_text.is_empty() {
        // Treat `content` field as a text file upload
        file_data = content_text.clone().into_bytes();
        orig_name = if user_title.is_empty() { "content.txt".to_string() } else { user_title.clone() };
    }

    let ext = orig_name.rsplit('.').next().unwrap_or("bin");
    let mime = if orig_name.to_lowercase().ends_with(".mth") || orig_name.to_lowercase().ends_with(".mht") || orig_name.to_lowercase().ends_with(".html") {
        "text/html".parse::<mime_guess::Mime>().unwrap_or_else(|_| mime_guess::from_ext(ext).first_or_octet_stream())
    } else {
        mime_guess::from_ext(ext).first_or_octet_stream()
    };
    let mime_str = mime.to_string();

    let save_title = if user_title.is_empty() {
        archive_name_title(&orig_name)
    } else {
        user_title.clone()
    };

    let save_slug = tagging::slugify(&save_title);
    let filename = format!("{}_{}.{}", ts, save_slug, ext);
    let id = filename
        .rsplit_once('.')
        .map(|(s, _)| s)
        .unwrap_or(&filename)
        .to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);

    fs::write(&uucp, &file_data).ok();
    log::info!("[upload] saved file: {} ({} bytes)", uucp, file_data.len());

    let mut hasher = Sha256::new();
    hasher.update(&file_data);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    let ipfs_cid = ipfs::ipfs_add_bytes(&file_data);

    let final_title = save_title.clone();
    let final_description = if user_description.is_empty() {
        file_description(&orig_name, &mime_str, file_data.len(), &file_data)
    } else {
        user_description.clone()
    };

    // CID dedup file
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    fs::write(&cid_file, &id).ok();

    write_index_entry(
        &uucp_dir,
        &id,
        &final_title,
        Some(&final_description),
        vec!["upload".to_string(), ext.to_string()],
        &local_cid,
        &witness,
        &filename,
        file_data.len(),
        ipfs_cid.clone(),
        None,
        None,
    );

    log::info!("[upload] completed: id={} title='{}'", id, final_title);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id,
        "filename": filename,
        "title": final_title,
        "description": final_description,
        "cid": local_cid,
        "ipfs_cid": ipfs_cid,
        "witness": witness,
        "mime": mime.to_string(),
        "size": file_data.len(),
        "url": format!("/paste/{}", id),
    })))
}

/// GET /file/{id} - Serve raw file
pub async fn get_file(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());

    // Find file with any extension matching the id
    let file = fs::read_dir(&uucp_dir).ok().and_then(|entries| {
        entries.filter_map(|e| e.ok()).find(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            let stem = name.rsplit_once('.').map(|(s, _)| s).unwrap_or(&name);
            stem == id && !name.ends_with(".cid") && !name.ends_with(".meta")
        })
    });

    match file {
        Some(entry) => {
            let data = fs::read(entry.path())
                .map_err(|_| actix_web::error::ErrorNotFound("read error"))?;
            let ext = entry
                .path()
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("bin")
                .to_string();
            let mime = if ext == "mht" || ext == "mhtml" || ext == "mth" {
                // MHT/MTH is message/rfc822 but browsers render it better as text/html
                mime_guess::mime::TEXT_HTML
            } else {
                mime_guess::from_ext(&ext).first_or_octet_stream()
            };
            Ok(HttpResponse::Ok().content_type(mime.to_string()).body(data))
        }
        None => Ok(HttpResponse::NotFound().body("File not found")),
    }
}

/// GET /paste/{id} - View paste
#[utoipa::path(
    get,
    path = concat!(env!("BASE_PATH"), "/paste/{id}"),
    params(
        ("id" = String, Path, description = "Paste ID")
    ),
    responses(
        (status = 200, description = "Paste HTML")
    )
)]
pub async fn get_paste(
    path: web::Path<String>,
    req: actix_web::HttpRequest,
) -> Result<HttpResponse> {
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
    let prev_id = current_idx.and_then(|i| {
        if i > 0 {
            entries.get(i - 1).map(|e| &e.id)
        } else {
            None
        }
    });
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

    // Check for uploaded file with .meta sidecar
    let is_file = content.is_none();
    let meta_content = if is_file {
        fs::read_dir(&uucp_dir).ok().and_then(|entries| {
            entries
                .filter_map(|e| e.ok())
                .find(|e| {
                    let name = e.file_name().to_string_lossy().to_string();
                    let stem = name.rsplit_once('.').and_then(|(s, ext)| {
                        if ext == "meta" {
                            s.rsplit_once('.').map(|(s2, _)| s2)
                        } else {
                            None
                        }
                    });
                    stem == Some(id.as_str())
                })
                .and_then(|e| fs::read_to_string(e.path()).ok())
        })
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
            let ipfs_cid = headers
                .get("IPFS")
                .or(headers.get("ipfs_cid"))
                .map(|s| *s)
                .or_else(|| {
                    // Fallback to index if not in file header
                    entries
                        .iter()
                        .find(|e| e.id == id)
                        .and_then(|e| e.ipfs_cid.as_deref())
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
                entries
                    .iter()
                    .filter(|e| e.id != id && e.keywords.iter().any(|k| curr.keywords.contains(k)))
                    .take(5)
                    .collect()
            } else {
                vec![]
            };

            let prev_link = prev_id
                .map(|pid| format!(r#"<a href="{}/paste/{}">← Prev</a>"#, base_path, pid))
                .unwrap_or_else(|| "".to_string());
            let next_link = next_id
                .map(|nid| format!(r#"<a href="{}/paste/{}">Next →</a>"#, base_path, nid))
                .unwrap_or_else(|| "".to_string());

            let related_html = if !related.is_empty() {
                let items: String = related
                    .iter()
                    .map(|e| {
                        format!(
                            r#"<div style="padding:5px"><a href="{}/paste/{}">{}</a></div>"#,
                            base_path, e.id, e.title
                        )
                    })
                    .collect();
                format!(
                    r#"<h3>Related Posts:</h3><div style="background:#111;padding:10px;margin:10px 0">{}</div>"#,
                    items
                )
            } else {
                "".to_string()
            };

            let pipelight_tile = if pipelight::is_pipelight_config(body) {
                pipelight::render_tile_html(&id, &base_path)
            } else {
                String::new()
            };

            let git2nora_tile = if plugins::git2nora::is_publishable_crate(body) {
                plugins::git2nora::render_git2nora_tile_html(&id, &base_path)
            } else {
                String::new()
            };

            struct Page {
                bp: String,
                id: String,
                title: String,
                prev_link: String,
                next_link: String,
                ipfs_cmd: String,
                file_cmd: String,
                curl_cmd: String,
                body: String,
                pipelight_tile: String,
                git2nora_tile: String,
                related_html: String,
                ipfs_cid: String,
                share_menu: String,
                share_script: String,
            }

            let page = Page {
                bp: base_path,
                id: id.to_string(),
                title: title.to_string(),
                prev_link: prev_link.clone(),
                next_link: next_link.clone(),
                ipfs_cmd: ipfs_cmd.to_string(),
                file_cmd: file_cmd.to_string(),
                curl_cmd: curl_cmd.to_string(),
                body: body.to_string(),
                pipelight_tile: pipelight_tile.to_string(),
                git2nora_tile: git2nora_tile.to_string(),
                related_html: related_html.to_string(),
                ipfs_cid: ipfs_cid.unwrap_or_default().to_string(),
                share_menu: crate::share::render_share_menu(),
                share_script: crate::share::render_share_script().to_string(),
            };

            let html = format!(
                r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<title>{title}</title>
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
.nav{{background:#111;padding:10px;margin:10px 0;border:1px solid #0f0}}
pre{{background:#111;padding:20px;border:1px solid #0f0;overflow:auto;max-height:600px;word-wrap:break-word;white-space:pre-wrap}}
.reply-btn{{background:#0f0;color:#000;border:none;padding:5px 10px;cursor:pointer;margin:5px;display:inline-block}}
.share-wrap{{position:relative;display:inline-block;margin:5px}}
.share-menu{{position:absolute;left:0;top:100%;z-index:1000;background:#111;border:1px solid #0f0;padding:8px;min-width:230px;display:none}}
.share-menu.open{{display:block}}
.share-menu button{{display:block;width:100%;text-align:left;background:#0a0a0a;color:#0f0;border:1px solid #0f0;padding:6px 8px;margin:4px 0;cursor:pointer}}
.share-menu button:hover{{background:#0f0;color:#000}}
.cmd{{background:#111;padding:10px;margin:5px 0;border-left:3px solid #ff0;cursor:pointer;font-size:12px}}
.cmd:hover{{background:#222}}
.qr-modal{{position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#fff;padding:20px;border:3px solid #0f0;z-index:1000;display:none}}
.qr-modal h3{{color:#000}}
.preview-modal{{position:fixed;top:0;left:0;width:100%;height:100%;background:#fff;z-index:2000;overflow:auto;display:none}}
.preview-modal iframe{{width:100%;height:100%;border:none}}
.pipelight-tile{{background:#1a1a2e;border:1px solid #0f0;border-radius:8px;padding:15px;margin:15px 0}}
.pipelight-btn{{padding:8px 16px;border-radius:4px;border:none;cursor:pointer;font-size:14px}}
</style>
</head><body>
<div class="nav"><a href="{bp}/">🏠 Home</a> <a href="{bp}/browse">📚 Browse</a> <a href="{bp}/threads">🧵 Threads</a> <a href="{bp}/thread/{id}">Thread</a> <a href="{bp}/raw/{id}">📄 Raw</a> | {prev_link} {next_link}</div>
<h1>{title}</h1>
<a class="reply-btn" href="{bp}/?reply_to={id}">Reply</a>
<button class="reply-btn" onclick="navigator.clipboard.writeText(document.querySelector('pre').textContent);this.textContent='Copied'">Copy</button>
{share_menu}
<button class="reply-btn" onclick="showQR()">QR Code</button>
<button class="reply-btn" onclick="shareRDFa()">RDFa URL</button>
<button class="reply-btn" onclick="showPreview()">Preview</button>
<a class="reply-btn" href="{bp}/paste/{id}/split">Split</a>

<h3>Access Commands:</h3>
<div class="cmd" onclick="navigator.clipboard.writeText('{ipfs_cmd}');this.style.borderColor='#0f0'">$ {ipfs_cmd}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{file_cmd}');this.style.borderColor='#0f0'">$ {file_cmd}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{curl_cmd}');this.style.borderColor='#0f0'">$ {curl_cmd}</div>

<h3>Content:</h3>
<pre onclick="navigator.clipboard.writeText(this.textContent);this.style.borderColor='#0ff';setTimeout(()=>this.style.borderColor='#0f0',1500)" style="cursor:pointer">{body}</pre>
{pipelight_tile}
{git2nora_tile}
{related_html}
<div id="sidebar" class="sidebar">
  <h3>🔍 Similar Posts</h3>
  <div id="similarResults" class="sidebar-results"></div>
  <div class="sidebar-actions">
    <button class="reply-btn" onclick="bundleSelected()" style="width:100%">📦 Bundle Selected</button>
    <button class="reply-btn" onclick="toggleSidebar()" style="width:100%;margin-top:5px;background:#333;color:#0f0">✕ Close</button>
  </div>
</div>
<div id="qrModal" class="qr-modal">
  <h3>{title}</h3>
  <canvas id="qrcode"></canvas><br>
  <button onclick="document.getElementById('qrModal').style.display='none'">Close</button>
</div>
<script>
const ipfsCid = '{ipfs_cid}';
const pasteUrl = window.location.href;
const currentPasteId = '{id}';
const title = '{title}';
console.log('[pastebin][debug] page id=' + currentPasteId + ' title=' + title + ' base_path={bp}');
console.log('[pastebin][debug] pre present=', !!document.querySelector('pre'));
console.log('[pastebin][debug] pre count=', document.querySelectorAll('pre').length);
if (!document.querySelector('pre')) console.error('[pastebin][lint] missing <pre> content container');
if (!document.title) console.warn('[pastebin][lint] missing <title>');
if (!document.querySelector('meta[charset]')) console.warn('[pastebin][lint] missing charset meta');

{share_script}
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

function showPreview() {{
  const content = document.querySelector('pre').innerHTML;
  const modal = document.createElement('div');
  modal.className = 'preview-modal';
  modal.style.display = 'block';
  
  // Decode HTML entities
  const decoded = document.createElement('textarea');
  decoded.innerHTML = content;
  const actualContent = decoded.value;
  
  // Add base styles for non-HTML content
  const styledContent = actualContent.includes('<html') || actualContent.includes('<!DOCTYPE') 
    ? actualContent 
    : '<html><head><style>body{{font-family:sans-serif;padding:20px;line-height:1.6}}</style></head><body><pre style=\"white-space:pre-wrap;word-wrap:break-word\">' + actualContent + '</pre></body></html>';
  
  modal.innerHTML = '<button onclick=\"this.parentElement.remove()\" style=\"position:fixed;top:10px;right:10px;z-index:3000;padding:10px 20px;background:#f00;color:#fff;border:none;cursor:pointer\">✕ Close</button><iframe srcdoc=\"' + styledContent.replace(/"/g, '&quot;') + '\"></iframe>';
  document.body.appendChild(modal);
}}

function toggleSidebar() {{
  const s = document.getElementById('sidebar');
  if (s.classList.contains('open')) {{
    s.classList.remove('open');
    return;
  }}
  s.classList.add('open');
  fetch('{bp}/api/similar/' + currentPasteId)
    .then(r => r.json())
    .then(d => {{
      const div = document.getElementById('similarResults');
      div.innerHTML = '';
      if (!d.results || d.results.length === 0) {{
        div.innerHTML = '<div style="color:#666;padding:10px">No similar posts found.</div>';
        return;
      }}
      d.results.forEach((r, i) => {{
        const item = document.createElement('div');
        item.className = 'sidebar-item';
        item.innerHTML = '<input type="checkbox" id="sim-' + i + '" value="' + r.id + '">' +
          '<label for="sim-' + i + '"><a href="' + r.url + '" onclick="event.stopPropagation()" style="color:#0ff;font-size:13px">' +
          r.title.slice(0, 40) + '</a><br><span class="ts">' + r.timestamp + '</span></label>';
        div.appendChild(item);
      }});
    }})
    .catch(e => {{
      document.getElementById('similarResults').innerHTML = '<div style="color:#f00">Error: ' + e + '</div>';
    }});
}}

function bundleSelected() {{
  const checks = document.querySelectorAll('#similarResults input:checked');
  if (checks.length === 0) {{ alert('Select at least one post.'); return; }}
  const pastes = [currentPasteId];
  checks.forEach(c => pastes.push(c.value));
  fetch('{bp}/api/bundle', {{
    method: 'POST',
    headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify({{pastes: pastes}})
  }})
    .then(r => r.json())
    .then(d => {{
      window.open(d.url, '_blank');
      toggleSidebar();
    }})
    .catch(e => alert('Bundle error: ' + e));
}}
</script>
<script src="{share_menu}/static/a11y.js"></script>
</body></html>"#,
                title = page.title,
                bp = page.bp,
                id = page.id,
                prev_link = page.prev_link,
                next_link = page.next_link,
                ipfs_cmd = page.ipfs_cmd,
                file_cmd = page.file_cmd,
                curl_cmd = page.curl_cmd,
                body = page.body,
                pipelight_tile = page.pipelight_tile,
                git2nora_tile = page.git2nora_tile,
                related_html = page.related_html,
                ipfs_cid = page.ipfs_cid,
                share_menu = page.share_menu,
                share_script = page.share_script
            );

            let lint_issues = lint_html(&html);
            debug!(
                "paste={} title={} html_bytes={} lint={:?}",
                id, title, html.len(), lint_issues
            );

            Ok(HttpResponse::Ok()
                .content_type("text/html; charset=utf-8")
                .body(html))
        }
        None if meta_content.is_some() => {
            // File upload - parse meta and show image/file view
            let meta = meta_content.unwrap();
            let mut headers = std::collections::HashMap::new();
            for line in meta.lines() {
                if let Some((key, value)) = line.split_once(':') {
                    headers.insert(key.trim().to_string(), value.trim().to_string());
                }
            }
            let title = headers.get("Title").cloned().unwrap_or_else(|| id.clone());
            let mime = headers
                .get("Mime")
                .cloned()
                .unwrap_or_else(|| "application/octet-stream".to_string());
            let ipfs_cid = headers.get("IPFS").cloned().unwrap_or_default();
            let cid = headers.get("CID").cloned().unwrap_or_default();
            let size = headers.get("Size").cloned().unwrap_or_default();

            let content_html = if mime.starts_with("image/") {
                format!(
                    r#"<img src="{}/file/{}" style="max-width:100%;border:1px solid #0f0" alt="{}">"#,
                    base_path, id, title
                )
            } else {
                format!(
                    r#"<p>📎 <a href="{}/file/{}">{}</a> ({}, {} bytes)</p>"#,
                    base_path, id, title, mime, size
                )
            };

            let html = format!(
                r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>{}</title>
<style>body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}a{{color:#0ff}}</style>
</head><body>
<div><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/file/{}">📄 Raw</a></div>
<h1>{}</h1>
<p>CID: {} | IPFS: {}</p>
{}
</body></html>"#,
                title, base_path, base_path, base_path, id, title, cid, ipfs_cid, content_html
            );

            Ok(HttpResponse::Ok()
                .content_type("text/html; charset=utf-8")
                .body(html))
        }
        None => {
            // Last resort: find any file in spool matching this id
            let file = fs::read_dir(&uucp_dir).ok().and_then(|entries| {
                entries.filter_map(|e| e.ok()).find(|e| {
                    let name = e.file_name().to_string_lossy().to_string();
                    let stem = name.rsplit_once('.').map(|(s, _)| s).unwrap_or(&name);
                    stem == id && !name.ends_with(".cid") && !name.ends_with(".meta") && !name.ends_with(".jsonl") && !name.ends_with(".txt")
                })
            });

            match file {
                Some(entry) => {
                    let data = fs::read(entry.path())
                        .map_err(|_| actix_web::error::ErrorNotFound("read error"))?;
                    let ext = entry.path().extension()
                        .and_then(|e| e.to_str())
                        .unwrap_or("bin")
                        .to_string();
                    let mime = mime_guess::from_ext(&ext).first_or_octet_stream();
                    let title = entries.iter()
                        .find(|e| e.id == id)
                        .map(|e| &e.title)
                        .cloned()
                        .unwrap_or_else(|| id.clone());
                    let display_mime = if ext == "mht" || ext == "mhtml" || ext == "mth" {
                        "text/html".to_string()
                    } else {
                        mime.to_string()
                    };

                    let content_html = if display_mime.starts_with("image/") {
                        format!(
                            r##"<img src="{}/file/{}" style="max-width:100%;border:1px solid #0f0" alt="{}">"##,
                            base_path, id, title
                        )
                    } else if ext == "mht" || ext == "mhtml" || ext == "mth" {
                        // Render MHT/MTH as inline HTML with download link
                        format!(
                            r##"<p>📎 <a href="{}/file/{}">{}</a> (MHT web archive, {} bytes)</p>
<iframe src="{}/file/{}" style="width:100%;height:600px;border:1px solid #0f0;background:#fff"></iframe>"##,
                            base_path, id, title, data.len(), base_path, id
                        )
                    } else if display_mime.starts_with("text/") {
                        // Escape for safe display
                        let escaped = data.iter().map(|&b| match b {
                            b'&' => "&amp;".to_string(),
                            b'<' => "&lt;".to_string(),
                            b'>' => "&gt;".to_string(),
                            _ => (b as char).to_string(),
                        }).collect::<String>();
                        format!(
                            r##"<pre style="white-space:pre-wrap;word-wrap:break-word">{}</pre>"##,
                            escaped
                        )
                    } else {
                        format!(
                            r##"<p>📎 <a href="{}/file/{}">{}</a> ({}, {} bytes)</p>"##,
                            base_path, id, title, display_mime, data.len()
                        )
                    };

                    let html = format!(
                        r##"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>{}</title>
<style>body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}a{{color:#0ff}}</style>
</head><body>
<div><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/file/{}">📄 Raw</a></div>
<h1>{}</h1>
<p>MIME: {} | {} bytes</p>
{}
</body></html>"##,
                        title, base_path, base_path, base_path, id, title, display_mime, data.len(), content_html
                    );

                    Ok(HttpResponse::Ok()
                        .content_type("text/html; charset=utf-8")
                        .body(html))
                }
                None => Ok(HttpResponse::NotFound().body("Paste not found")),
            }
        }
    }
}

/// GET /health - Health check with version info
pub async fn health_check() -> Result<HttpResponse> {
    let version = option_env!("GIT_COMMIT").unwrap_or("unknown");
    let build_time = option_env!("BUILD_TIME").unwrap_or("unknown");
    let exe = std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        .unwrap_or_default();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "service": "kant-pastebin",
        "git_commit": version,
        "build_time": build_time,
        "binary": exe,
    })))
}

/// GET /api/version - Detailed version info
pub async fn api_version() -> Result<HttpResponse> {
    let version = option_env!("GIT_COMMIT").unwrap_or("unknown");
    let build_time = option_env!("BUILD_TIME").unwrap_or("unknown");
    let exe = std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        .unwrap_or_default();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "name": "kant-pastebin",
        "version": "0.1.0",
        "git_commit": version,
        "build_time": build_time,
        "binary": exe,
        "rustc": option_env!("CARGO_PKG_RUST_VERSION").unwrap_or("unknown"),
        "nix_build": exe.contains("/nix/store/"),
    })))
}

/// GET /api/diagnostics - Diagnostic info (open files, memory, etc.)
pub async fn api_diagnostics() -> Result<HttpResponse> {
    let exe = std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        .unwrap_or_default();

    let mut open_fds = 0;
    let mut open_files: Vec<String> = Vec::new();
    if let Ok(entries) = std::fs::read_dir("/proc/self/fd") {
        for entry in entries.flatten() {
            open_fds += 1;
            if let Ok(target) = std::fs::read_link(entry.path()) {
                if let Some(path) = target.to_str() {
                    open_files.push(path.to_string());
                }
            }
        }
    }

    let mut file_counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for path in &open_files {
        let ext = std::path::Path::new(path)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("(none)");
        *file_counts.entry(ext.to_string()).or_default() += 1;
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "binary": exe,
        "open_fds": open_fds,
        "file_counts": file_counts,
        "service": "kant-pastebin",
    })))
}

/// GET /paste/{id}/split - Split paste content
pub async fn get_paste_split(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let entries: Vec<PasteIndex> = fs::read_to_string(format!("{}/index.jsonl", uucp_dir))
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .collect();

    let content = fs::read_dir(&uucp_dir).ok().and_then(|dir_entries| {
        dir_entries
            .filter_map(std::result::Result::ok)
            .find(|e| {
                let name = e.file_name();
                let name_str = name.to_string_lossy();
                name_str.contains(&id) && name_str.ends_with(".txt")
            })
            .and_then(|e| fs::read_to_string(e.path()).ok())
    });

    let Some(content) = content else {
        return Ok(HttpResponse::NotFound().body("Paste not found"));
    };

    let mut headers = std::collections::HashMap::new();
    let mut body_start = 0;
    for (i, line) in content.lines().enumerate() {
        if line.is_empty() && i > 0 {
            body_start = content.lines().take(i + 1).map(|l| l.len() + 1).sum();
            break;
        }
        if let Some((key, value)) = line.split_once(':') {
            headers.insert(key.trim().to_string(), value.trim().to_string());
        }
    }

    let title = headers
        .get("Title")
        .cloned()
        .or_else(|| entries.iter().find(|e| e.id == id).map(|e| e.title.clone()))
        .unwrap_or_else(|| id.clone());
    let timestamp = entries
        .iter()
        .find(|e| e.id == id)
        .map(|e| e.timestamp.clone())
        .unwrap_or_default();
    let paste = PasteIndex {
        id,
        title,
        timestamp,
        ..PasteIndex::default()
    };

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(view::render_split_paste(
            &paste,
            &content[body_start..],
            &base_path,
        )))
}

/// GET /preview/{id} - Preview paste with rendering
pub async fn preview_paste(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let content = storage::load_content(&id).unwrap_or_else(|| "Paste not found".to_string());
    Ok(HttpResponse::Ok()
        .content_type("text/html")
        .body(view::render_preview(&id, &content)))
}

/// GET /raw/{id} - Raw text
pub async fn get_raw(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let content = read_paste_content_by_id(&id).unwrap_or_else(|| "Paste not found".to_string());
    Ok(HttpResponse::Ok().content_type("text/plain").body(content))
}

/// POST /upgrade - Upgrade all pastes with auto-tags
pub async fn upgrade_pastes() -> Result<HttpResponse> {
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let index_file = format!("{}/index.jsonl", uucp_dir);

    let entries: Vec<PasteIndex> = fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .collect();

    let mut upgraded = 0;
    let mut new_entries = Vec::new();

    for entry in entries {
        let file_path = format!("{}/{}", uucp_dir, entry.filename);
        if let Ok(content) = fs::read_to_string(&file_path) {
            let body = content
                .lines()
                .skip_while(|line| !line.is_empty())
                .skip(1)
                .collect::<Vec<_>>()
                .join("\n");

            let auto_tags = tagging::auto_tag(&body);
            let description = tagging::auto_describe(&body);

            // Extract HTML title if present
            let new_title = if body.to_lowercase().contains("<html")
                || body.to_lowercase().contains("<!doctype")
            {
                tagging::extract_html_title(&body).unwrap_or_else(|| entry.title.clone())
            } else if entry.title == "untitled" || entry.title.is_empty() {
                description.clone()
            } else {
                entry.title.clone()
            };

            // Add IPFS CID if missing
            let ipfs_cid = if entry.ipfs_cid.is_none() || entry.ipfs_cid.as_deref() == Some("") {
                ipfs::ipfs_add(&body)
            } else {
                entry.ipfs_cid.clone()
            };

            let mut new_entry = entry.clone();
            new_entry.title = new_title;
            new_entry.ipfs_cid = ipfs_cid;
            new_entry.keywords.extend(auto_tags);
            new_entry.keywords.sort();
            new_entry.keywords.dedup();
            new_entry.description = Some(description);

            new_entries.push(new_entry);
            upgraded += 1;
        } else {
            new_entries.push(entry);
        }
    }

    let new_index: String = new_entries
        .iter()
        .map(|e| serde_json::to_string(e).unwrap())
        .collect::<Vec<_>>()
        .join("\n")
        + "\n";

    fs::write(&index_file, new_index).ok();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "upgraded": upgraded,
        "total": new_entries.len()
    })))
}

/// GET /thread/{id} - Show a paginated threaded view of a paste and its replies
pub async fn get_thread(
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let parent_id = path.into_inner();
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let page = query
        .get("page")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1);
    let limit = query
        .get("limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(10);

    let posts = build_thread_posts(&uucp_dir, &parent_id);
    if posts.is_empty() {
        return Ok(HttpResponse::NotFound().body("Thread not found"));
    }
    let (page_posts, total_pages, page) = paged_thread_posts(&posts, page, limit);

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(view::render_thread_page(
            &base_path,
            &parent_id,
            page,
            total_pages,
            posts.len(),
            page_posts,
        )))
}

/// GET /thread/{id}/export - Download a thread as text, or zip-split it if too large
pub async fn export_thread(
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let parent_id = path.into_inner();
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let max_bytes = query
        .get("max_bytes")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(5_000_000)
        .clamp(1, 50_000_000);
    let Some((_posts, content)) = build_thread_export(&uucp_dir, &parent_id) else {
        return Ok(HttpResponse::NotFound().body("Thread not found"));
    };
    let parts = split_export_text(&parent_id, &content, max_bytes);
    let base = safe_thread_export_filename(&parent_id);

    if parts.len() == 1 {
        let filename = format!("thread-{}.txt", base);
        return Ok(HttpResponse::Ok()
            .insert_header((
                "Content-Disposition",
                format!("attachment; filename=\"{}\"", filename),
            ))
            .content_type("text/plain; charset=utf-8")
            .body(parts[0].1.clone()));
    }

    let mut buf = Vec::new();
    {
        let mut cursor = std::io::Cursor::new(&mut buf);
        let mut zip = zip::ZipWriter::new(&mut cursor);
        let options: zip::write::FileOptions<'_, ()> =
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        for (name, content) in parts {
            zip.start_file(name, options)
                .map_err(actix_web::error::ErrorInternalServerError)?;
            zip.write_all(content.as_bytes())
                .map_err(actix_web::error::ErrorInternalServerError)?;
        }
        zip.finish()
            .map_err(actix_web::error::ErrorInternalServerError)?;
    }

    let filename = format!("thread-{}.zip", base);
    Ok(HttpResponse::Ok()
        .insert_header((
            "Content-Disposition",
            format!("attachment; filename=\"{}\"", filename),
        ))
        .content_type("application/zip")
        .body(buf))
}

/// GET /api/thread/{id} - JSON paginated thread data
pub async fn api_thread(
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let parent_id = path.into_inner();
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let page = query
        .get("page")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1);
    let limit = query
        .get("limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(10);
    let posts = build_thread_posts(&uucp_dir, &parent_id);
    let (page_posts, total_pages, page) = paged_thread_posts(&posts, page, limit);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "thread_id": &parent_id,
        "page": page,
        "limit": limit.clamp(1, 50),
        "total_pages": total_pages,
        "total": posts.len(),
        "posts": page_posts,
    })))
}

/// GET /threads - List thread roots with pagination
pub async fn threads(
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let page = query
        .get("page")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1);
    let limit = query
        .get("limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(20);
    let entries = read_index_entries(&uucp_dir);
    let index_len = entries.len();
    let mut roots: Vec<PasteIndex> = if let Some((cached_entries, cached_len)) = read_threads_cache(&uucp_dir) {
        if cached_len == index_len {
            cached_entries
                .into_iter()
                .map(|entry| PasteIndex::from(&entry))
                .collect()
        } else {
            compute_and_save_thread_roots(&entries, &uucp_dir, index_len)
        }
    } else {
        compute_and_save_thread_roots(&entries, &uucp_dir, index_len)
    };

    roots.sort_by(|a, b| b.timestamp.cmp(&a.timestamp).then_with(|| b.id.cmp(&a.id)));

    let page = page.max(1);
    let limit = limit.clamp(1, 50);
    let total_pages = roots.len().div_ceil(limit).max(1);
    let page = page.min(total_pages);
    let start = (page - 1) * limit;
    let end = (start + limit).min(roots.len());
    let page_roots = &roots[start..end];

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(view::render_threads_page(
            &base_path,
            page,
            total_pages,
            roots.len(),
            page_roots,
        )))
}

/// GET /browse - List pastes
#[utoipa::path(
    get,
    path = concat!(env!("BASE_PATH"), "/browse"),
    params(
        ("q" = Option<String>, Query, description = "Search query")
    ),
    responses(
        (status = 200, description = "Browse HTML")
    )
)]
pub async fn browse(
    req: HttpRequest,
    _query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());

    let items = match paste_search_results(&req, 200, true)? {
        Some((_search_q, _mode, _scope, _limit, results)) => {
            let items: String = results
                .iter()
                .map(|r| render_search_result_entry(r, &base_path))
                .collect();
            render_browse_page(&base_path, &_search_q, &items, "Full-text search", true)
        }
        None => {
            let uucp_dir = env::var("UUCP_SPOOL")
                .unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
            let entries = read_index_entries(&uucp_dir);
            let items: String = entries
                .iter()
                .rev()
                .take(50)
                .map(|e| render_paste_entry(e, &base_path))
                .collect();
            render_browse_page(&base_path, "", &items, "", false)
        }
    };

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(items))
}

fn read_index_entries(uucp_dir: &str) -> Vec<PasteIndex> {
    let index_file = format!("{}/index.jsonl", uucp_dir);
    fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .collect()
}

fn read_paste_header_fields(content: &str) -> HashMap<String, String> {
    let mut headers = HashMap::new();
    for line in content.lines() {
        if line.trim().is_empty() {
            break;
        }
        if let Some((key, value)) = line.split_once(':') {
            headers.insert(key.trim().to_string(), value.trim().to_string());
        }
    }
    headers
}

fn entry_reply_to(entry: &PasteIndex, uucp_dir: &str) -> Option<String> {
    entry
        .reply_to
        .clone()
        .filter(|v| !v.trim().is_empty())
        .or_else(|| entry.root.clone().filter(|v| !v.trim().is_empty()))
        .or_else(|| {
            read_paste_content(&entry.uucp_path)
                .map(|content| read_paste_header_fields(&content))
                .and_then(|headers| {
                    headers
                        .get("Reply-To")
                        .cloned()
                        .filter(|v| !v.trim().is_empty())
                })
                .or_else(|| {
                    fs::read_to_string(format!("{}/{}.txt", uucp_dir, entry.id))
                        .ok()
                        .map(|content| read_paste_header_fields(&content))
                        .and_then(|headers| {
                            headers
                                .get("Reply-To")
                                .cloned()
                                .filter(|v| !v.trim().is_empty())
                        })
                })
        })
}

fn paste_excerpt(uucp_path: &str, max_chars: usize) -> String {
    read_paste_content(uucp_path)
        .unwrap_or_default()
        .chars()
        .take(max_chars)
        .collect()
}

fn collect_thread_ids(
    parent_id: &str,
    children_by_parent: &HashMap<String, Vec<String>>,
    entries_by_id: &HashMap<String, PasteIndex>,
    visited: &mut std::collections::HashSet<String>,
) -> Vec<String> {
    let mut ids = Vec::new();
    if !entries_by_id.contains_key(parent_id) {
        return ids;
    }
    if !visited.insert(parent_id.to_string()) {
        return ids;
    }
    ids.push(parent_id.to_string());
    let mut children = children_by_parent
        .get(parent_id)
        .cloned()
        .unwrap_or_default();
    children.sort();
    for child_id in children {
        ids.extend(collect_thread_ids(
            &child_id,
            children_by_parent,
            entries_by_id,
            visited,
        ));
    }
    ids
}

fn thread_depths(
    parent_id: &str,
    children_by_parent: &HashMap<String, Vec<String>>,
    depths: &mut HashMap<String, usize>,
) {
    depths.insert(parent_id.to_string(), 0);
    let mut children = children_by_parent
        .get(parent_id)
        .cloned()
        .unwrap_or_default();
    children.sort();
    for child_id in children {
        if !depths.contains_key(&child_id) {
            depths.insert(child_id.clone(), depths[parent_id] + 1);
            thread_depths(&child_id, children_by_parent, depths);
        }
    }
}

fn build_thread_posts(uucp_dir: &str, parent_id: &str) -> Vec<ThreadPost> {
    let entries = read_index_entries(uucp_dir);
    let index_len = entries.len();

    if let Some((cached_posts, cached_len)) = read_thread_posts_cache_with_meta(uucp_dir, parent_id) {
        if cached_len == index_len {
            let mut posts: Vec<ThreadPost> = cached_posts.into_iter().map(|p| ThreadPost::from(&p)).collect();
            for post in &mut posts {
                post.content_excerpt =
                    paste_excerpt(&format!("{}/{}.txt", uucp_dir, post.id), 240);
            }
            return posts;
        }
    }

    let posts = build_thread_posts_inner(&entries, uucp_dir, parent_id);
    let cache_entries: Vec<ThreadCachePostEntry> = posts.iter().map(|p| p.into()).collect();
    write_thread_posts_cache_with_meta(uucp_dir, parent_id, &cache_entries, index_len);
    posts
}

fn build_thread_posts_inner(
    entries: &[PasteIndex],
    uucp_dir: &str,
    parent_id: &str,
) -> Vec<ThreadPost> {
    let entries_by_id: HashMap<String, PasteIndex> = entries
        .iter()
        .map(|entry| (entry.id.clone(), entry.clone()))
        .collect();
    let mut children_by_parent: HashMap<String, Vec<String>> = HashMap::new();

    for entry in entries {
        if entry.id == parent_id {
            continue;
        }
        if let Some(parent) = entry_reply_to(entry, uucp_dir) {
            children_by_parent
                .entry(parent)
                .or_default()
                .push(entry.id.clone());
        }
    }

    let mut visited = std::collections::HashSet::new();
    let ids = collect_thread_ids(
        parent_id,
        &children_by_parent,
        &entries_by_id,
        &mut visited,
    );
    let mut depths = HashMap::new();
    thread_depths(parent_id, &children_by_parent, &mut depths);

    ids.into_iter()
        .filter_map(|id| {
            let entry = entries_by_id.get(&id)?;
            let reply_to = entry_reply_to(entry, uucp_dir);
            let title = if entry.title.is_empty() || entry.title == "untitled" {
                entry.description.clone().unwrap_or_else(|| id.clone())
            } else {
                entry.title.clone()
            };
            Some(ThreadPost {
                id: entry.id.clone(),
                title,
                description: entry.description.clone(),
                reply_to,
                timestamp: entry.timestamp.clone(),
                size: entry.size,
                url: format!("/paste/{}", entry.id),
                depth: depths.get(&id).copied().unwrap_or(0),
                content_excerpt: paste_excerpt(&entry.uucp_path, 240),
            })
        })
        .collect()
}

fn paged_thread_posts(
    posts: &[ThreadPost],
    page: usize,
    limit: usize,
) -> (&[ThreadPost], usize, usize) {
    let page = page.max(1);
    let limit = limit.clamp(1, 50);
    let total_pages = posts.len().div_ceil(limit).max(1);
    let page = page.min(total_pages);
    let start = (page - 1) * limit;
    let end = (start + limit).min(posts.len());
    (&posts[start..end], total_pages, page)
}

fn safe_thread_export_filename(id: &str) -> String {
    let slug: String = id
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect();
    slug.trim_matches('-').to_string()
}

fn build_thread_export(uucp_dir: &str, parent_id: &str) -> Option<(Vec<ThreadPost>, String)> {
    let posts = build_thread_posts(uucp_dir, parent_id);
    if posts.is_empty() {
        return None;
    }

    let mut exported = String::new();
    exported.push_str(&format!(
        "Thread: {}\nGenerated: {}\nPosts: {}\n\n",
        parent_id,
        Utc::now().to_rfc3339(),
        posts.len()
    ));

    for post in &posts {
        exported.push_str(&format!(
            "--- Paste: {} ---\nTitle: {}\nTimestamp: {}\nReply-To: {}\nURL: /paste/{}\nSize: {} bytes\nDepth: {}\n\n",
            post.id,
            post.title,
            post.timestamp,
            post.reply_to.as_deref().unwrap_or(""),
            post.id,
            post.size,
            post.depth
        ));
        if let Some(description) = &post.description {
            exported.push_str(&format!("Description: {}\n\n", description));
        }
        let content = read_paste_content(&format!("{}/{}.txt", uucp_dir, post.id))
            .or_else(|| {
                read_paste_content(&format!(
                    "{}/{}.txt",
                    uucp_dir,
                    post.url.trim_start_matches("/paste/")
                ))
            })
            .unwrap_or_default();
        exported.push_str(&content);
        if !exported.ends_with('\n') {
            exported.push('\n');
        }
        exported.push_str("\n\n");
    }

    Some((posts, exported))
}

fn split_export_text(thread_id: &str, content: &str, max_bytes: usize) -> Vec<(String, String)> {
    let base = safe_thread_export_filename(thread_id);
    let max_bytes = max_bytes.max(1);
    let mut parts = Vec::new();
    let mut current = String::new();

    for line in content.split_inclusive('\n') {
        if !current.is_empty() && current.len() + line.len() > max_bytes {
            parts.push((
                format!("thread-{}-part-{:03}.txt", base, parts.len() + 1),
                std::mem::take(&mut current),
            ));
            current.clear();
        }
        current.push_str(line);
    }

    if !current.is_empty() {
        parts.push((
            format!("thread-{}-part-{:03}.txt", base, parts.len() + 1),
            current,
        ));
    }

    parts
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[allow(dead_code)]
pub(crate) struct ThreadCacheMeta {
    #[serde(rename = "indexLen")]
    pub index_len: usize,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[allow(dead_code)]
pub(crate) struct ThreadCacheRootEntry {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub timestamp: String,
    pub size: usize,
    #[serde(rename = "replyCount")]
    pub reply_count: usize,
    #[serde(rename = "lastTimestamp")]
    pub last_timestamp: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[allow(dead_code)]
pub(crate) struct ThreadCachePostEntry {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    #[serde(rename = "replyTo")]
    pub reply_to: Option<String>,
    pub timestamp: String,
    pub size: usize,
    pub depth: usize,
}

impl From<&ThreadPost> for ThreadCachePostEntry {
    fn from(v: &ThreadPost) -> Self {
        ThreadCachePostEntry {
            id: v.id.clone(),
            title: v.title.clone(),
            description: v.description.clone(),
            reply_to: v.reply_to.clone(),
            timestamp: v.timestamp.clone(),
            size: v.size,
            depth: v.depth,
        }
    }
}

impl From<&ThreadCachePostEntry> for ThreadPost {
    fn from(v: &ThreadCachePostEntry) -> Self {
        ThreadPost {
            id: v.id.clone(),
            title: v.title.clone(),
            description: v.description.clone(),
            reply_to: v.reply_to.clone(),
            timestamp: v.timestamp.clone(),
            size: v.size,
            url: format!("/paste/{}", v.id),
            depth: v.depth,
            content_excerpt: String::new(),
        }
    }
}

impl From<&ThreadCacheRootEntry> for PasteIndex {
    fn from(v: &ThreadCacheRootEntry) -> Self {
        PasteIndex {
            id: v.id.clone(),
            title: v.title.clone(),
            description: v.description.clone(),
            timestamp: v.last_timestamp.clone(),
            size: v.size,
            ..Default::default()
        }
    }
}

#[allow(dead_code)]
fn thread_cache_dir(uucp_dir: &str) -> String {
    format!("{}/.thread-cache", uucp_dir)
}

#[allow(dead_code)]
fn threads_cache_path(uucp_dir: &str) -> String {
    format!("{}/threads.jsonl", thread_cache_dir(uucp_dir))
}

#[allow(dead_code)]
fn thread_posts_cache_path(uucp_dir: &str, thread_id: &str) -> String {
    format!("{}/thread-{}.jsonl", thread_cache_dir(uucp_dir), thread_id)
}

#[allow(dead_code)]
fn write_threads_cache(
    entries: &[ThreadCacheRootEntry],
    uucp_dir: &str,
    index_len: usize,
) {
    let path = threads_cache_path(uucp_dir);
    let _ = fs::create_dir_all(thread_cache_dir(uucp_dir));
    let mut file = match fs::File::create(&path) {
        Ok(f) => f,
        Err(_) => return,
    };
    let _ = writeln!(
        file,
        "{}",
        serde_json::to_string(&ThreadCacheMeta { index_len }).unwrap()
    );
    for entry in entries {
        let _ = writeln!(file, "{}", serde_json::to_string(entry).unwrap());
    }
}

#[allow(dead_code)]
fn read_threads_cache(
    uucp_dir: &str,
) -> Option<(Vec<ThreadCacheRootEntry>, usize)> {
    let path = threads_cache_path(uucp_dir);
    let content = fs::read_to_string(&path).ok()?;
    let mut lines = content.lines();
    let meta: ThreadCacheMeta = serde_json::from_str(lines.next()?).ok()?;
    let mut entries = Vec::new();
    for line in lines {
        if let Ok(entry) = serde_json::from_str::<ThreadCacheRootEntry>(line) {
            entries.push(entry);
        }
    }
    Some((entries, meta.index_len))
}

#[allow(dead_code)]
fn read_thread_posts_cache(
    uucp_dir: &str,
    thread_id: &str,
) -> Option<Vec<ThreadCachePostEntry>> {
    let path = thread_posts_cache_path(uucp_dir, thread_id);
    let content = fs::read_to_string(&path).ok()?;
    content
        .lines()
        .filter_map(|line| serde_json::from_str::<ThreadCachePostEntry>(line).ok())
        .collect::<Vec<_>>()
        .into()
}

#[allow(dead_code)]
fn write_thread_posts_cache(
    uucp_dir: &str,
    thread_id: &str,
    posts: &[ThreadCachePostEntry],
) {
    let path = thread_posts_cache_path(uucp_dir, thread_id);
    let _ = fs::create_dir_all(thread_cache_dir(uucp_dir));
    let mut file = match fs::File::create(&path) {
        Ok(f) => f,
        Err(_) => return,
    };
    for entry in posts {
        let _ = writeln!(file, "{}", serde_json::to_string(entry).unwrap());
    }
}

#[allow(dead_code)]
fn append_thread_posts_cache(
    uucp_dir: &str,
    thread_id: &str,
    posts: &[ThreadCachePostEntry],
) {
    let path = thread_posts_cache_path(uucp_dir, thread_id);
    let _ = fs::create_dir_all(thread_cache_dir(uucp_dir));
    let mut file = match fs::OpenOptions::new().create(true).append(true).open(&path) {
        Ok(f) => f,
        Err(_) => return,
    };
    for entry in posts {
        let _ = writeln!(file, "{}", serde_json::to_string(entry).unwrap());
    }
}

#[allow(dead_code)]
fn read_thread_posts_cache_with_meta(
    uucp_dir: &str,
    thread_id: &str,
) -> Option<(Vec<ThreadCachePostEntry>, usize)> {
    let path = thread_posts_cache_path(uucp_dir, thread_id);
    let content = fs::read_to_string(&path).ok()?;
    let mut lines = content.lines();
    let meta_line = lines.next()?;
    let meta: ThreadCacheMeta = serde_json::from_str(meta_line).ok()?;
    let posts = lines
        .filter_map(|line| serde_json::from_str::<ThreadCachePostEntry>(line).ok())
        .collect();
    Some((posts, meta.index_len))
}

#[allow(dead_code)]
fn write_thread_posts_cache_with_meta(
    uucp_dir: &str,
    thread_id: &str,
    posts: &[ThreadCachePostEntry],
    index_len: usize,
) {
    let path = thread_posts_cache_path(uucp_dir, thread_id);
    let _ = fs::create_dir_all(thread_cache_dir(uucp_dir));
    let mut file = match fs::File::create(&path) {
        Ok(f) => f,
        Err(_) => return,
    };
    let _ = writeln!(
        file,
        "{}",
        serde_json::to_string(&ThreadCacheMeta { index_len }).unwrap()
    );
    for entry in posts {
        let _ = writeln!(file, "{}", serde_json::to_string(entry).unwrap());
    }
}

#[allow(dead_code)]
fn compute_and_save_thread_roots(
    entries: &[PasteIndex],
    uucp_dir: &str,
    index_len: usize,
) -> Vec<PasteIndex> {
    let info = compute_thread_root_info(entries, uucp_dir);
    write_threads_cache(&info, uucp_dir, index_len);
    info.iter().map(|entry| PasteIndex::from(entry)).collect()
}

#[allow(dead_code)]
fn compute_thread_root_info(entries: &[PasteIndex], uucp_dir: &str) -> Vec<ThreadCacheRootEntry> {
    let entries_by_id: HashMap<String, PasteIndex> = entries
        .iter()
        .map(|entry| (entry.id.clone(), entry.clone()))
        .collect();
    let mut children_by_parent: HashMap<String, Vec<String>> = HashMap::new();

    for entry in entries {
        if let Some(parent) = entry_reply_to(entry, uucp_dir) {
            children_by_parent
                .entry(parent)
                .or_default()
                .push(entry.id.clone());
        }
    }

    let roots: Vec<String> = entries
        .iter()
        .filter(|e| {
            if let Some(parent) = entry_reply_to(e, uucp_dir) {
                entries_by_id.contains_key(&parent)
            } else {
                true
            }
        })
        .map(|e| e.id.clone())
        .collect();

    let mut visited = std::collections::HashSet::new();
    let mut root_sizes: HashMap<String, usize> = HashMap::new();
    let mut root_max_times: HashMap<String, String> = HashMap::new();

    for root in &roots {
        if !visited.insert(root.clone()) {
            continue;
        }
        let mut stack = vec![root.clone()];
        let mut count = 0usize;
        let mut max_ts = String::new();
        while let Some(id) = stack.pop() {
            count += 1;
            if let Some(entry) = entries_by_id.get(&id) {
                if entry.timestamp > max_ts {
                    max_ts = entry.timestamp.clone();
                }
            }
            for child in children_by_parent.get(&id).into_iter().flatten() {
                if visited.insert(child.clone()) {
                    stack.push(child.clone());
                }
            }
        }
        root_sizes.insert(root.clone(), count);
        root_max_times.insert(root.clone(), max_ts);
    }

    roots
        .into_iter()
        .filter_map(|id| {
            let entry = entries_by_id.get(&id)?;
            Some(ThreadCacheRootEntry {
                id: entry.id.clone(),
                title: entry.title.clone(),
                description: entry.description.clone(),
                timestamp: entry.timestamp.clone(),
                size: entry.size,
                reply_count: *root_sizes.get(&id).unwrap_or(&1),
                last_timestamp: root_max_times
                    .get(&id)
                    .cloned()
                    .unwrap_or_else(|| entry.timestamp.clone()),
            })
        })
        .collect()
}

fn render_paste_entry(e: &PasteIndex, base_path: &str) -> String {
    let display_title = if e.title == "untitled" || e.title.is_empty() {
        e.description.as_deref().unwrap_or("untitled")
    } else {
        &e.title
    };
    let tags = if !e.keywords.is_empty() {
        format!(
            " <span style=\"color:#666;font-size:11px\">[{}]</span>",
            e.keywords
                .iter()
                .map(|k| html_escape(k))
                .collect::<Vec<_>>()
                .join(", ")
        )
    } else {
        String::new()
    };
    format!(
        r#"<div style="border-bottom:1px solid #333;padding:10px"><a href="{}/paste/{}">{}</a>{} <span style="color:#666">{}</span> <a href="{}/thread/{}" style="font-size:12px">Thread</a></div>"#,
        base_path,
        html_escape(&e.id),
        html_escape(display_title),
        tags,
        html_escape(&e.timestamp),
        base_path,
        html_escape(&e.id)
    )
}

fn render_search_result_entry(r: &SearchResult, base_path: &str) -> String {
    let display_title = if r.title.is_empty() {
        r.description.as_deref().unwrap_or(&r.id)
    } else {
        &r.title
    };
    let excerpt = if r.excerpt.is_empty() {
        String::new()
    } else {
        format!(r#"<div class="excerpt">{}</div>"#, html_escape(&r.excerpt))
    };
    format!(
        r#"<div style="border-bottom:1px solid #333;padding:10px"><a href="{}/paste/{}">{}</a> <span style="color:#666">{} · {} · {}</span>{}</div>"#,
        base_path,
        html_escape(&r.id),
        html_escape(display_title),
        html_escape(&r.timestamp),
        format_size(r.size as u64),
        html_escape(&r.match_type),
        excerpt
    )
}

fn render_browse_page(
    base_path: &str,
    q: &str,
    items: &str,
    note: &str,
    export_visible: bool,
) -> String {
    let search_box = format!(
        r#"<form method="get"><input type="text" name="q" value="{}" placeholder="Search..." style="padding:5px;width:300px"><button type="submit">🔍</button></form>"#,
        html_escape(q)
    );
    let title_json = serde_json::to_string(q).unwrap_or_else(|_| "\"browse results\"".to_string());
    let export_button = if export_visible {
        format!(
            r#"<button type="button" id="exportVisible" style="background:#0f0;color:#000;border:none;padding:8px 12px;cursor:pointer;margin:10px 5px 10px 0">📤 Export visible as paste</button><button type="button" id="exportChunkedVisible" style="background:#0f0;color:#000;border:none;padding:8px 12px;cursor:pointer;margin:10px 0">🧩 Export chunked</button>"#
        )
    } else {
        String::new()
    };
    let note = if note.is_empty() {
        String::new()
    } else {
        format!(r#"<p style="color:#666">{}</p>"#, html_escape(note))
    };
    let title = title_json.clone();
    format!(
        r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Browse Pastes</title>
<style>body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}.excerpt{{color:#0a0;white-space:pre-wrap}}</style>
</head><body>
<div><a href="{}/">🏠 Home</a></div>
<h1>Browse Pastes</h1>
{}
{}
{}
<div id="exportStatus" style="color:#0f0;margin:10px 0"></div>
<div id="results" style="margin-top:20px">{}</div>
<script>
async function exportVisible() {{
  const ids = Array.from(document.querySelectorAll('#results a[href*="/paste/"]')).map(a => a.getAttribute('href').split('/').pop()).filter(Boolean);
  if (!ids.length) {{ alert('No visible results'); return; }}
  const btn = document.getElementById('exportVisible');
  const status = document.getElementById('exportStatus');
  btn.disabled = true;
  status.textContent = 'Exporting...';
  const res = await fetch('{}/api/search-results-bundle', {{
    method: 'POST',
    headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify({{ results: ids.map(id => ({{ id: id }})), title: {} }})
  }});
  const data = await res.json();
  if (!res.ok || data.error) {{ status.textContent = 'Export failed: ' + (data.error || 'unknown'); btn.disabled = false; btn.textContent = '📤 Export visible as paste'; return; }}
  status.textContent = 'Opening paste...';
  const url = (data.url && data.url.startsWith('/paste/')) ? '{}/' + data.url.slice(1) : (data.url || '{}/paste/' + data.id);
  window.location = url;
}}
async function exportChunkedVisible() {{
  const ids = Array.from(document.querySelectorAll('#results a[href*="/paste/"]')).map(a => a.getAttribute('href').split('/').pop()).filter(Boolean);
  if (!ids.length) {{ alert('No visible results'); return; }}
  const btn = document.getElementById('exportChunkedVisible');
  const status = document.getElementById('exportStatus');
  const chunkSize = Number(prompt('Chunk bytes per paste', '250000'));
  btn.disabled = true;
  status.textContent = 'Deduplicating lines and chunking...';
  const res = await fetch('{}/api/search-results-chunks', {{
    method: 'POST',
    headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify({{ results: ids.map(id => ({{ id: id }})), title: {}, chunk_size: Number.isFinite(chunkSize) && chunkSize > 0 ? chunkSize : 250000, overlap: 0 }})
  }});
  const data = await res.json();
  if (!res.ok || data.error) {{ status.textContent = 'Chunk export failed: ' + (data.error || 'unknown'); btn.disabled = false; btn.textContent = '🧩 Export chunked'; return; }}
  status.textContent = 'Opening chunk manifest...';
  const url = (data.url && data.url.startsWith('/paste/')) ? '{}/' + data.url.slice(1) : (data.url || '{}/paste/' + data.id);
  window.location = url;
}}
const exportBtn = document.getElementById('exportVisible');
const exportChunkedBtn = document.getElementById('exportChunkedVisible');
if (exportBtn) exportBtn.onclick = exportVisible;
if (exportChunkedBtn) exportChunkedBtn.onclick = exportChunkedVisible;
</script>
</body></html>"#,
        base_path,
        search_box,
        note,
        export_button,
        items,
        base_path,
        title,
        base_path,
        base_path,
        base_path,
        base_path,
        base_path,
        base_path
    )
}

/// Helper: extract raw paste content from a stored paste file
/// The stored format wraps content with metadata headers and sheaf RDFa.
fn read_paste_content_by_id(paste_id: &str) -> Option<String> {
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    read_index_entries(&uucp_dir)
        .into_iter()
        .find(|e| e.id == paste_id)
        .and_then(|e| read_paste_content(&e.uucp_path))
        .or_else(|| read_paste_content(&format!("{}/{}.txt", uucp_dir, paste_id)))
}

fn resolve_split_content(body: &serde_json::Value) -> std::result::Result<String, HttpResponse> {
    let paste_id = body
        .get("paste_id")
        .and_then(|v| v.as_str())
        .or_else(|| body.get("id").and_then(|v| v.as_str()))
        .map(str::trim)
        .filter(|s| !s.is_empty());

    if let Some(paste_id) = paste_id {
        return read_paste_content_by_id(paste_id).ok_or_else(|| {
            HttpResponse::BadRequest().json(serde_json::json!({
                "error": format!("paste content unavailable for id: {}", paste_id)
            }))
        });
    }

    body.get("content")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| {
            HttpResponse::BadRequest()
                .json(serde_json::json!({"error": "missing content or paste_id"}))
        })
}

fn read_paste_content(uucp_path: &str) -> Option<String> {
    let raw = fs::read_to_string(uucp_path).ok()?;
    // The format is:
    // --- id ---\n
    // Title: ...\n
    // Keywords: ...\n
    // CID: ...\n
    // Witness: ...\n
    // IPFS: ...\n
    // DASL: ...\n
    // Reply-To: ...\n
    // {sheaf_header}\n\n
    // {content}\n\n
    // {sheaf_rdfa}\n
    if let Some(body_start) = raw.find("\n\n") {
        let header = &raw[..body_start];
        if let Some(sheaf_rel) = header.find("Sheaf:") {
            let sheaf_start = sheaf_rel;
            let mut content_start = raw[sheaf_start..]
                .find('\n')
                .map(|line_end| sheaf_start + line_end + 1)
                .unwrap_or(raw.len());
            if raw[content_start..].starts_with('\n') {
                content_start += 1;
            }
            if let Some(rdfa_start) = raw[content_start..].find("<div") {
                return Some(
                    raw[content_start..content_start + rdfa_start]
                        .trim()
                        .to_string(),
                );
            }
            return Some(raw[content_start..].trim().to_string());
        }

        if let Some(body_start2) = raw[body_start + 2..].find("\n\n") {
            let content_start = body_start + 2 + body_start2 + 2;
            if let Some(rdfa_start) = raw[content_start..].find("<div") {
                return Some(
                    raw[content_start..content_start + rdfa_start]
                        .trim()
                        .to_string(),
                );
            }
            return Some(raw[content_start..].trim().to_string());
        }
        return Some(raw[body_start + 2..].trim().to_string());
    }

    Some(raw.trim().to_string())
}

/// Helper: create a content excerpt around a search match (byte-safe)
fn excerpt_around(content: &str, query: &str, context: usize) -> String {
    let lower = content.to_lowercase();
    let q = query.to_lowercase();
    if let Some(pos) = lower.find(&q) {
        // Find safe char boundaries around the match
        let chars: Vec<(usize, char)> = content.char_indices().collect();
        let mut start_char = 0;
        for (i, &(idx, _)) in chars.iter().enumerate() {
            if idx >= pos.saturating_sub(context * 4) {
                start_char = i.saturating_sub(5);
                break;
            }
        }
        // Find the match end in char indices
        let match_end_byte = pos + q.len();
        let mut end_char = chars.len() - 1;
        for (i, &(idx, _)) in chars.iter().enumerate() {
            if idx >= match_end_byte {
                end_char = (i + 5).min(chars.len() - 1);
                break;
            }
        }
        let byte_start = chars[start_char].0;
        let byte_end = chars[end_char].0 + chars[end_char].1.len_utf8();
        let prefix = if start_char > 0 { "…" } else { "" };
        let suffix = if end_char < chars.len() - 1 {
            "…"
        } else {
            ""
        };
        format!("{}{}{}", prefix, &content[byte_start..byte_end], suffix)
    } else {
        // No match — return first N characters (char-safe)
        content.chars().take(context * 2).collect()
    }
}

#[derive(serde::Serialize)]
struct SearchResult {
    id: String,
    title: String,
    description: Option<String>,
    keywords: Vec<String>,
    match_type: String, // "metadata" | "content" | "doc"
    excerpt: String,
    url: String,
    timestamp: String,
    size: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<String>, // "paste" or "doc"
    #[serde(skip_serializing_if = "Option::is_none")]
    file_path: Option<String>, // for doc results, the filesystem path
}

/// GET /api/search?q=... - JSON search API, searches both metadata and paste content
/// CLI usage: curl 'http://localhost:8090/api/search?q=CL(15,0,0)'
/// Optional: &content=0 to skip content search (metadata only, faster)
/// Optional: &limit=N to control result count (default: 50)
/// Parse query string manually from the raw URI (handles `(`, `)`, etc.)
/// Parse query string manually from the raw URI (handles `(`, `)`, etc.)
fn parse_query_param(uri: &str, key: &str) -> Option<String> {
    let uri = if let Some(idx) = uri.find('?') {
        &uri[idx + 1..]
    } else {
        uri
    };
    for pair in uri.split('&') {
        let mut parts = pair.splitn(2, '=');
        let k = parts.next().unwrap_or("").trim();
        if k == key {
            let v = parts.next().unwrap_or("").trim().to_string();
            if v.contains('%') {
                return Some(
                    v.replace("+", " ")
                        .replace("%20", " ")
                        .replace("%28", "(")
                        .replace("%29", ")")
                        .replace("%2C", ",")
                        .replace("%2F", "/"),
                );
            }
            return Some(v);
        }
    }
    None
}

fn search_terms(query: &str) -> Vec<String> {
    query
        .split(|c: char| c.is_whitespace() || c == ',' || c == ';' || c == '|')
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect()
}

fn terms_match(content: &str, terms: &[String], mode: &str) -> bool {
    if terms.is_empty() {
        return false;
    }
    match mode {
        "all" => terms.iter().all(|term| content.contains(term)),
        "any" => terms.iter().any(|term| content.contains(term)),
        _ => content.contains(&terms.join(" ")),
    }
}

fn best_excerpt(content: &str, terms: &[String], context: usize) -> String {
    if terms.is_empty() {
        return content.chars().take(context * 2).collect();
    }
    let lower = content.to_lowercase();
    let mut best_start = None;
    let mut best_len = 0usize;
    for term in terms {
        let mut offset = 0usize;
        while let Some(rel) = lower[offset..].find(term) {
            let start = offset + rel;
            let len = term.len();
            if best_start.map_or(true, |old: usize| start < old) {
                best_start = Some(start);
                best_len = len;
            }
            offset = start + len.max(1);
        }
    }
    if let Some(start) = best_start {
        let char_start = content[..start].chars().count().saturating_sub(context);
        let char_end = char_start + content[start..start + best_len].chars().count() + context;
        let byte_start = content
            .char_indices()
            .nth(char_start)
            .map(|(i, _)| i)
            .unwrap_or(0);
        let byte_end = content
            .char_indices()
            .nth(char_end)
            .map(|(i, _)| i)
            .unwrap_or(content.len());
        let prefix = if char_start > 0 { "…" } else { "" };
        let suffix = if byte_end < content.len() { "…" } else { "" };
        format!("{}{}{}", prefix, &content[byte_start..byte_end], suffix)
    } else {
        content.chars().take(context * 2).collect()
    }
}

/// GET /api/search?q=... - JSON search API, searches both metadata and paste content
/// CLI usage: curl 'http://localhost:8090/api/search?q=CL(15,0,0)'
/// Optional: &mode=phrase|all|any
/// Optional: &scope=all|metadata|content
/// Optional: &limit=N to control result count (default: 50)
pub async fn api_search(req: HttpRequest) -> Result<HttpResponse> {
    let Some((search_q, mode, scope, limit, results)) = paste_search_results(&req, 50, true)?
    else {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Missing query parameter: q",
            "usage": "curl 'http://localhost:8090/api/search?q=<query>'"
        })));
    };
    let terms = search_terms(&search_q);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "query": &search_q,
        "terms": terms,
        "mode": mode,
        "scope": scope,
        "total": results.len(),
        "limit": limit,
        "results": results,
    })))
}

fn paste_search_results(
    req: &HttpRequest,
    default_limit: usize,
    require_q: bool,
) -> Result<Option<(String, String, String, usize, Vec<SearchResult>)>> {
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let uri = req.uri().to_string();
    let Some((raw_query, mode, scope, limit)) = parse_search_query(&uri, default_limit, require_q)
    else {
        return Ok(None);
    };
    let search_q = raw_query.to_lowercase();
    let terms = search_terms(&search_q);
    let entries = read_index_entries(&uucp_dir);
    let mut results: Vec<SearchResult> = Vec::new();

    for entry in entries.iter().rev() {
        if results.len() >= limit {
            break;
        }
        let metadata = format!(
            "{} {} {}",
            entry.title,
            entry.description.as_deref().unwrap_or(""),
            entry.keywords.join(" ")
        )
        .to_lowercase();
        let metadata_match = terms_match(&metadata, &terms, &mode);
        if scope == "metadata" && metadata_match {
            results.push(SearchResult {
                id: entry.id.clone(),
                title: entry.title.clone(),
                description: entry.description.clone(),
                keywords: entry.keywords.clone(),
                match_type: "metadata".to_string(),
                excerpt: String::new(),
                url: format!("/paste/{}", entry.id),
                timestamp: entry.timestamp.clone(),
                size: entry.size,
                source: Some("paste".to_string()),
                file_path: None,
            });
            continue;
        }
        if scope == "metadata" {
            continue;
        }
        if let Some(content) = read_paste_content(&entry.uucp_path) {
            let lower_content = content.to_lowercase();
            let content_match = terms_match(&lower_content, &terms, &mode);
            if metadata_match || content_match {
                let excerpt = if content_match {
                    best_excerpt(&content, &terms, 80)
                } else {
                    String::new()
                };
                results.push(SearchResult {
                    id: entry.id.clone(),
                    title: entry.title.clone(),
                    description: entry.description.clone(),
                    keywords: entry.keywords.clone(),
                    match_type: if metadata_match && content_match {
                        "metadata+content".to_string()
                    } else if metadata_match {
                        "metadata".to_string()
                    } else {
                        "content".to_string()
                    },
                    excerpt,
                    url: format!("/paste/{}", entry.id),
                    timestamp: entry.timestamp.clone(),
                    size: entry.size,
                    source: Some("paste".to_string()),
                    file_path: None,
                });
            }
        }
    }

    Ok(Some((search_q, mode, scope, limit, results)))
}

fn parse_search_query(
    uri: &str,
    default_limit: usize,
    require_q: bool,
) -> Option<(String, String, String, usize)> {
    let raw_query = parse_query_param(uri, "q").unwrap_or_default();
    if require_q && raw_query.is_empty() {
        return None;
    }
    let mode = parse_query_param(uri, "mode").unwrap_or_else(|| "phrase".to_string());
    let scope = parse_query_param(uri, "scope").unwrap_or_else(|| "all".to_string());
    let limit = parse_query_param(uri, "limit")
        .and_then(|s| s.parse().ok())
        .unwrap_or(default_limit)
        .min(200);
    Some((raw_query, mode, scope, limit))
}

pub async fn search_page() -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(crate::view::render_search(&base_path)))
}

/// Search files in configured doc directories for matching content.
fn search_directories(query: &str, limit: usize, max_per_dir: usize) -> Vec<SearchResult> {
    let dirs = env::var("SEARCH_DIRS").unwrap_or_else(|_| {
        let home = env::var("HOME").unwrap_or_else(|_| "/home/mdupont".to_string());
        format!("{}/DOCS/search", home)
    });

    let q = query.to_lowercase();
    let mut results = Vec::new();

    for dir in dirs.split(':') {
        if results.len() >= limit {
            break;
        }
        let dir = dir.trim();
        if dir.is_empty() {
            continue;
        }

        let entries = match fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => continue,
        };

        let mut dir_count = 0;
        for entry in entries.flatten() {
            if dir_count >= max_per_dir {
                break;
            }
            let path = entry.path();
            if !path.is_file() {
                continue;
            }

            // Check file name match first
            let fname = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_lowercase();
            if fname.contains(&q) {
                let title = format!("DOCS/search/{}", fname);
                let size = fs::metadata(&path).map(|m| m.len() as usize).unwrap_or(0);
                results.push(SearchResult {
                    id: dir_count.to_string(),
                    title,
                    description: Some(format!("File name match in {}", dir)),
                    keywords: vec![],
                    match_type: "doc".to_string(),
                    excerpt: String::new(),
                    url: format!("/api/search-doc?path={}", path.display()),
                    timestamp: String::new(),
                    size,
                    source: Some("doc".to_string()),
                    file_path: Some(path.display().to_string()),
                });
                dir_count += 1;
                if results.len() >= limit {
                    break;
                }
                continue;
            }

            // Try to read file content for text files
            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
            match ext {
                "md" | "txt" | "sh" | "org" | "json" | "yaml" | "yml" | "toml" | "nix" | "rs"
                | "py" | "js" | "ts" | "html" | "css" | "xml" | "rst" | "rb" | "go" | "java"
                | "c" | "h" => {}
                _ => continue,
            }

            let content = match fs::read_to_string(&path) {
                Ok(c) => c,
                Err(_) => continue,
            };

            if content.to_lowercase().contains(&q) {
                let title = format!("DOCS/search/{}", path.display());
                let excerpt = excerpt_around(&content, query, 80);
                let size = fs::metadata(&path).map(|m| m.len() as usize).unwrap_or(0);
                results.push(SearchResult {
                    id: format!("doc-{}", dir_count),
                    title,
                    description: Some(format!("Content match in {}", dir)),
                    keywords: vec![],
                    match_type: "doc".to_string(),
                    excerpt,
                    url: format!("/api/search-doc?path={}", path.display()),
                    timestamp: String::new(),
                    size,
                    source: Some("doc".to_string()),
                    file_path: Some(path.display().to_string()),
                });
                dir_count += 1;
                if results.len() >= limit {
                    break;
                }
            }
        }
    }

    results
}

/// GET /api/search-doc?path=<path> - View a doc file returned by search
/// CLI: curl 'http://localhost:8090/api/search-doc?path=/home/mdupont/DOCS/search/README.md'
pub async fn search_doc(req: HttpRequest) -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let uri = req.uri().to_string();
    let path = match parse_query_param(&uri, "path") {
        Some(p) if !p.is_empty() => p,
        _ => {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Missing path parameter",
                "usage": "curl 'http://localhost:8090/api/search-doc?path=<filepath>'"
            })))
        }
    };

    match fs::read_to_string(&path) {
        Ok(content) => {
            let ext = std::path::Path::new(&path)
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("txt")
                .to_string();
            let fname = std::path::Path::new(&path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("doc")
                .to_string();
            let html = format!(
                r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>{} — Kant Pastebin</title>
<style>
body{{font-family:monospace;max-width:900px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
h1{{color:#0f0;border-bottom:1px solid #333}}
pre{{background:#111;padding:15px;border:1px solid #333;overflow-x:auto;white-space:pre-wrap;word-wrap:break-word}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
code{{font-family:monospace}}
.meta{{color:#888;font-size:0.9em}}
</style></head><body>
<div class="nav"><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/api/search">🔍 Search</a></div>
<h1>📄 {}</h1>
<p class="meta">📁 {} <span style="float:right">{}</span></p>
<hr><pre><code>{}</code></pre>
</body></html>"#,
                base_path, base_path, base_path, fname, fname, path, ext, content
            );
            Ok(HttpResponse::Ok()
                .content_type("text/html; charset=utf-8")
                .body(html))
        }
        Err(e) => Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": format!("Cannot read file: {}", e),
            "path": path,
        }))),
    }
}

#[derive(serde::Serialize)]
struct SimilarResult {
    id: String,
    title: String,
    description: Option<String>,
    keywords: Vec<String>,
    match_type: String,
    excerpt: String,
    url: String,
    timestamp: String,
    size: usize,
    score: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    file_path: Option<String>,
}

fn similarity_terms(content: &str) -> Vec<String> {
    let mut terms = content
        .to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .map(|s| s.trim().to_string())
        .filter(|s| s.len() >= 4)
        .collect::<Vec<_>>();
    terms.sort();
    terms.dedup();
    terms
}

fn similarity_score(
    source_terms: &[String],
    source_keywords: &[String],
    source_ngrams: &[(String, usize)],
    entry: &PasteIndex,
    entry_content: Option<&str>,
) -> f64 {
    let entry_terms = similarity_terms(&format!(
        "{} {} {}",
        entry.title,
        entry.description.as_deref().unwrap_or(""),
        entry.keywords.join(" ")
    ));
    let entry_keywords_lc = entry
        .keywords
        .iter()
        .map(|k| k.to_lowercase())
        .collect::<Vec<_>>();
    let source_keywords_lc = source_keywords
        .iter()
        .map(|k| k.to_lowercase())
        .collect::<Vec<_>>();

    let keyword_score = source_keywords_lc
        .iter()
        .filter(|k| entry_keywords_lc.contains(k))
        .count() as f64
        * 3.0;
    let metadata_score = source_terms
        .iter()
        .filter(|term| entry_terms.contains(term))
        .count() as f64
        * 2.0;

    let source_ngram_counts: HashMap<String, usize> = source_ngrams
        .iter()
        .map(|(term, count)| (term.to_lowercase(), *count))
        .collect();
    let mut ngram_score = 0.0;
    for (term, count) in source_ngram_counts {
        if let Some((_, entry_count)) = entry.ngrams.iter().find(|(t, _)| t == &term) {
            ngram_score += (*entry_count).min(count).min(3) as f64;
        }
    }

    let mut content_score = 0.0;
    if let Some(content) = entry_content {
        let lower_content = content.to_lowercase();
        for term in source_terms.iter().take(120) {
            if lower_content.contains(term) {
                content_score += 1.0;
                if content_score >= 25.0 {
                    break;
                }
            }
        }
    }

    keyword_score + metadata_score + ngram_score + content_score
}

/// GET /api/similar/{id} - Find similar pastes by searching the content of the given paste
/// CLI: curl 'http://localhost:8090/api/similar/20260514_143739'
pub async fn api_similar(
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let limit: usize = query
        .get("limit")
        .and_then(|s| s.parse().ok())
        .unwrap_or(10)
        .min(50);

    let entries: Vec<PasteIndex> = fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .collect();
    let Some(source) = entries.iter().find(|entry| entry.id == id) else {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": format!("Paste {} not found", id)
        })));
    };

    let source_content = read_paste_content(&source.uucp_path)
        .or_else(|| read_paste_content(&format!("{}/{}.txt", uucp_dir, id)))
        .unwrap_or_default();
    let source_terms = similarity_terms(&format!(
        "{} {} {}",
        source.title,
        source.description.as_deref().unwrap_or(""),
        source_content
    ));
    let source_ngrams = tagging::extract_ngrams(&source_content, 3, 20);
    let mut results: Vec<SimilarResult> = Vec::new();

    for entry in entries.iter().rev() {
        if entry.id == id {
            continue;
        }
        let entry_content = read_paste_content(&entry.uucp_path)
            .or_else(|| read_paste_content(&format!("{}/{}.txt", uucp_dir, &entry.id)));
        let score = similarity_score(
            &source_terms,
            &source.keywords,
            &source_ngrams,
            entry,
            entry_content.as_deref(),
        );
        if score <= 0.0 {
            continue;
        }

        let best_term = source_terms
            .iter()
            .find(|term| {
                let metadata = format!(
                    "{} {} {}",
                    entry.title,
                    entry.description.as_deref().unwrap_or(""),
                    entry.keywords.join(" ")
                )
                .to_lowercase();
                metadata.contains(*term)
            })
            .cloned()
            .or_else(|| source_terms.first().cloned())
            .unwrap_or_default();
        let excerpt = entry_content
            .as_deref()
            .map(|content| best_excerpt(content, &[best_term.clone()], 80))
            .unwrap_or_default();

        results.push(SimilarResult {
            id: entry.id.clone(),
            title: entry.title.clone(),
            description: entry.description.clone(),
            keywords: entry.keywords.clone(),
            match_type: "similarity".to_string(),
            excerpt,
            url: format!("/paste/{}", entry.id),
            timestamp: entry.timestamp.clone(),
            size: entry.size,
            score,
            source: Some("paste".to_string()),
            file_path: None,
        });
    }

    results.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.timestamp.cmp(&a.timestamp))
    });
    results.truncate(limit);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "source_id": &id,
        "total": results.len(),
        "results": results,
    })))
}

/// POST /api/bundle - Create a DAG-CBOR bundle from selected pastes
/// Body: {"pastes": ["id1","id2",...]}
/// CLI: curl -X POST http://localhost:8090/api/bundle -d '{"pastes":["id1","id2"]}' -H 'Content-Type: application/json'
pub async fn api_bundle(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let pastes = match body.get("pastes").and_then(|v| v.as_array()) {
        Some(arr) => arr,
        None => {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Missing 'pastes' array",
                "usage": "curl -X POST ... -d '{\"pastes\":[\"id1\",\"id2\"]}'"
            })))
        }
    };

    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());

    // Collect all paste data
    let mut nodes: Vec<serde_json::Value> = Vec::new();
    for paste_id in pastes {
        let pid = paste_id.as_str().unwrap_or("");
        if pid.is_empty() {
            continue;
        }

        // Read from index
        let index_file = format!("{}/index.jsonl", uucp_dir);
        let entry: Option<PasteIndex> = fs::read_to_string(&index_file).ok().and_then(|s| {
            s.lines()
                .filter_map(|l| serde_json::from_str::<PasteIndex>(l).ok())
                .find(|e: &PasteIndex| e.id == pid)
        });

        // Read content
        let content = read_paste_content(&format!("{}/{}.txt", uucp_dir, pid));

        let node = serde_json::json!({
            "id": pid,
            "title": entry.as_ref().map(|e| e.title.as_str()).unwrap_or(""),
            "description": entry.as_ref().and_then(|e| e.description.as_deref()),
            "keywords": entry.as_ref().map(|e| e.keywords.clone()).unwrap_or_default(),
            "cid": entry.as_ref().map(|e| e.cid.as_str()).unwrap_or(""),
            "witness": entry.as_ref().map(|e| e.witness.as_str()).unwrap_or(""),
            "timestamp": entry.as_ref().map(|e| e.timestamp.as_str()).unwrap_or(""),
            "content": content.unwrap_or_default(),
            "url": format!("/paste/{}", pid),
        });
        nodes.push(node);
    }

    // Build the bundle as a graph
    let graph = serde_json::json!({
        "version": "1",
        "type": "dag-bundle",
        "created": Utc::now().format("%Y%m%d_%H%M%S").to_string(),
        "total_nodes": nodes.len(),
        "nodes": nodes,
    });

    // Serialize as CBOR
    let mut cbor_bytes = Vec::new();
    ciborium::ser::into_writer(&graph, &mut cbor_bytes)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("CBOR error: {}", e)))?;

    // Also keep JSON version
    let json_str = serde_json::to_string_pretty(&graph)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("JSON error: {}", e)))?;

    // Store the bundle as a new paste
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let pastes_str: String = pastes
        .iter()
        .filter_map(|v| v.as_str())
        .collect::<Vec<_>>()
        .join("_");
    let title = format!(
        "dag-bundle-{}",
        &pastes_str.chars().take(40).collect::<String>()
    );
    let filename = format!(
        "{}_{}.cbor",
        ts,
        title
            .clone()
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' {
                c
            } else {
                '_'
            })
            .collect::<String>()
    );
    let id = filename.trim_end_matches(".cbor").to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);

    let mut hasher = Sha256::new();
    hasher.update(&json_str.as_bytes());
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);

    // Write the CBOR file
    fs::write(&uucp, &cbor_bytes).ok();

    // Write a JSON sidecar (human-readable)
    let json_path = format!("{}/{}.json", uucp_dir, id);
    fs::write(&json_path, &json_str).ok();

    // Also write the JSON as a .txt for viewing in the pastebin
    let txt_uucp = format!("{}/{}.txt", uucp_dir, id);
    let txt_content = format!(
        "--- {} ---\nTitle: {}\nKeywords: dag-bundle, cbor, graph\nCID: {}\nWitness: {}\nSize: {}\n\n{}",
        id, title, local_cid, witness, cbor_bytes.len(),
        json_str
    );
    fs::write(&txt_uucp, &txt_content).ok();

    // Write index entry
    let keywords = vec![
        "dag-bundle".to_string(),
        "cbor".to_string(),
        "graph".to_string(),
    ];
    let ngrams = tagging::extract_ngrams(&format!("{} {}", title, "dag-bundle cbor graph"), 3, 10);
    let index_entry = PasteIndex {
        id: id.clone(),
        title,
        description: Some(format!(
            "DAG-CBOR bundle of {} pastes: {}",
            nodes.len(),
            pastes_str
        )),
        keywords,
        cid: local_cid.clone(),
        witness: witness.clone(),
        timestamp: ts,
        filename: filename.clone(),
        ngrams,
        ipfs_cid: None,
        reply_to: None,
        size: cbor_bytes.len(),
        uucp_path: uucp.clone(),
        root: None,
    };
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let index_line = format!("{}\n", serde_json::to_string(&index_entry).unwrap());
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&index_file)
        .and_then(|mut f| std::io::Write::write_all(&mut f, index_line.as_bytes()))
        .ok();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id,
        "title": index_entry.title,
        "cid": local_cid,
        "witness": witness,
        "total_nodes": nodes.len(),
        "format": "dag-cbor",
        "cbor_size": cbor_bytes.len(),
        "url": format!("/paste/{}", id),
        "download_url": format!("/file/{}", id),
    })))
}

pub async fn api_search_results_bundle(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let ids: Vec<String> = body
        .get("results")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| {
                    v.get("id")
                        .and_then(|id| id.as_str())
                        .map(|s| s.to_string())
                })
                .collect()
        })
        .unwrap_or_default();

    if ids.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Missing or empty 'results' array"
        })));
    }

    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let entries: Vec<PasteIndex> = fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .collect();

    let title = body
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("search results bundle")
        .to_string();

    let mut bundle = String::new();
    bundle.push_str(&format!(
        "=== Search Results Bundle ===\nTitle: {}\nCreated: {}\nTotal results: {}\n\n",
        title,
        Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
        ids.len()
    ));

    for (idx, pid) in ids.iter().enumerate() {
        let entry = entries.iter().find(|e| e.id == *pid);
        let uucp_path = entry
            .map(|e| e.uucp_path.clone())
            .unwrap_or_else(|| format!("{}/{}.txt", uucp_dir, pid));
        let content =
            read_paste_content(&uucp_path).unwrap_or_else(|| "[content unavailable]".to_string());
        bundle.push_str(&format!(
            "\n\n===== Result {}/{} =====\nID: {}\nTitle: {}\nTimestamp: {}\nKeywords: {}\nURL: /paste/{}\n\n{}\n",
            idx + 1,
            ids.len(),
            pid,
            entry.map(|e| e.title.as_str()).unwrap_or(pid),
            entry.map(|e| e.timestamp.as_str()).unwrap_or(""),
            entry.map(|e| e.keywords.join(", ")).unwrap_or_default(),
            pid,
            content
        ));
    }

    let paste = Paste {
        title: Some(title.clone()),
        description: Some(format!("Search results bundle from {} entries", title)),
        content: Some(bundle),
        keywords: Some(vec![
            "search".to_string(),
            "bundle".to_string(),
            "results".to_string(),
        ]),
        cid: None,
        reply_to: None,
    };
    create_paste(web::Json(paste)).await
}

struct StoredChunkPaste {
    id: String,
    url: String,
    sha256: String,
    byte_len: usize,
}

async fn create_chunked_paste(
    title: &str,
    content: String,
    keywords: Vec<String>,
) -> Result<StoredChunkPaste> {
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let trimmed = content.trim();
    let html_title = tagging::extract_html_title(&content);
    let auto_desc = tagging::auto_describe(&content);
    let title_owned = if title.is_empty() {
        html_title.unwrap_or_else(|| {
            let auto_tags = tagging::auto_tag(&content);
            if !auto_tags.is_empty() {
                auto_desc
            } else {
                "untitled".to_string()
            }
        })
    } else {
        title.to_string()
    };
    let slug_title = tagging::slugify(&title_owned);
    let slug_keywords = keywords
        .iter()
        .map(|k| tagging::slugify(k))
        .collect::<Vec<_>>()
        .join("_");
    let filename = if slug_keywords.is_empty() {
        format!("{}_{}.txt", ts, slug_title)
    } else {
        format!("{}_{}_{}.txt", ts, slug_title, slug_keywords)
    };
    let id = filename.trim_end_matches(".txt").to_string();
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let uucp = format!("{}/{}", uucp_dir, filename);

    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(hash);
    let dasl_cid = crate::dasl::dasl_cid(content.as_bytes());
    let section =
        erdfa_publish::sheaf::Section::new(content.as_bytes(), erdfa_publish::sheaf::Encoding::Raw);
    let paste_content = format!(
        "--- {} ---\nTitle: {}\nKeywords: {}\nCID: {}\nWitness: {}\nIPFS: {}\nDASL: {}\nReply-To: \n{}\n\n{}\n\n{}\n",
        id,
        title_owned,
        keywords.join(", "),
        local_cid,
        witness,
        "",
        dasl_cid,
        erdfa_publish::sheaf::sheaf_header(&section),
        content,
        section.to_rdfa()
    );
    fs::write(&uucp, paste_content).ok();
    fs::write(format!("{}/{}.cid", uucp_dir, local_cid), &id).ok();

    let index_entry = PasteIndex {
        id: id.clone(),
        title: if title_owned == "untitled" {
            tagging::auto_describe(&content)
        } else {
            title_owned
        },
        description: Some(tagging::auto_describe(&content)),
        keywords: keywords.clone(),
        cid: local_cid.clone(),
        witness: witness.clone(),
        timestamp: ts,
        filename: filename.clone(),
        ngrams: tagging::extract_ngrams(trimmed, 3, 10),
        ipfs_cid: None,
        reply_to: None,
        size: content.len(),
        uucp_path: uucp.clone(),
        root: None,
    };
    let index_line = format!("{}\n", serde_json::to_string(&index_entry).unwrap());
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(format!("{}/index.jsonl", uucp_dir))
        .and_then(|mut f| std::io::Write::write_all(&mut f, index_line.as_bytes()))
        .ok();

    Ok(StoredChunkPaste {
        id: index_entry.id.clone(),
        url: with_base_url(&format!("/paste/{}", index_entry.id)),
        sha256: sha256_hex(content.as_bytes()),
        byte_len: content.len(),
    })
}

pub async fn api_search_results_chunks(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let ids: Vec<String> = body
        .get("results")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| {
                    v.get("id")
                        .and_then(|id| id.as_str())
                        .map(|s| s.to_string())
                })
                .collect()
        })
        .unwrap_or_default();

    if ids.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Missing or empty 'results' array"
        })));
    }

    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let entries: Vec<PasteIndex> = read_index_entries(&uucp_dir);
    let entry_map: HashMap<String, PasteIndex> =
        entries.into_iter().map(|e| (e.id.clone(), e)).collect();
    let title = body
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("search results chunked export")
        .to_string();
    let chunk_size = body
        .get("chunk_size")
        .and_then(|v| v.as_u64())
        .unwrap_or(250_000)
        .clamp(8_000, 4_000_000) as usize;
    let overlap = body
        .get("overlap")
        .and_then(|v| v.as_u64())
        .unwrap_or(0)
        .min((chunk_size / 8).max(1) as u64) as usize;

    let mut all_lines: Vec<String> = Vec::new();
    for pid in &ids {
        let content = entry_map
            .get(pid)
            .and_then(|e| read_paste_content(&e.uucp_path))
            .or_else(|| read_paste_content(&format!("{}/{}.txt", uucp_dir, pid)))
            .unwrap_or_else(|| "[content unavailable]".to_string());
        all_lines.extend(content.lines().map(|line| line.to_string()));
    }

    let total_lines = all_lines.len();
    let mut unique_lines: Vec<String> = Vec::new();
    let mut seen: HashMap<String, usize> = HashMap::new();
    for line in all_lines {
        if !seen.contains_key(&line) {
            seen.insert(line.clone(), unique_lines.len());
            unique_lines.push(line);
        }
    }

    let line_store = create_chunk_line_store(&title, &unique_lines).await?;
    let chunks = build_line_chunks(&unique_lines, chunk_size, overlap);
    let mut chunk_infos: Vec<serde_json::Value> = Vec::new();

    for (idx, chunk) in chunks.iter().enumerate() {
        let text = chunk_text(&unique_lines, chunk);
        let stored = create_chunked_paste(
            &format!("{} chunk {}/{}", title, idx + 1, chunks.len()),
            render_chunk_json(idx, chunk, &text),
            vec![
                "chunked".to_string(),
                "dedup".to_string(),
                "search".to_string(),
            ],
        )
        .await?;
        chunk_infos.push(serde_json::json!({
            "index": idx,
            "paste_id": stored.id,
            "start_line": chunk.start_line,
            "end_line": chunk.end_line,
            "line_count": chunk.line_ids.len(),
            "byte_len": stored.byte_len,
            "sha256": stored.sha256,
            "url": stored.url,
        }));
    }

    let manifest = serde_json::json!({
        "version": 1,
        "type": "chunked-line-dedup",
        "title": title,
        "created": Utc::now().format("%Y-%m-%d %H:%M:%S UTC").to_string(),
        "source_ids": ids,
        "window": {
            "chunk_size": chunk_size,
            "overlap": overlap,
            "unit": "bytes"
        },
        "total_lines": total_lines,
        "unique_lines": unique_lines.len(),
        "dedup_ratio": if total_lines == 0 { 1.0 } else { unique_lines.len() as f64 / total_lines as f64 },
        "line_store": {
            "id": line_store.id.clone(),
            "url": line_store.url.clone(),
            "sha256": line_store.sha256.clone(),
            "byte_len": line_store.byte_len,
        },
        "chunks": chunk_infos,
    });
    let manifest_json = serde_json::to_string_pretty(&manifest)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("JSON error: {}", e)))?;
    let manifest = create_chunked_paste(
        &format!("{} manifest", title),
        manifest_json,
        vec![
            "chunked".to_string(),
            "manifest".to_string(),
            "dedup".to_string(),
            "search".to_string(),
        ],
    )
    .await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": manifest.id,
        "title": format!("{} manifest", title),
        "format": "chunked-line-dedup",
        "total_lines": total_lines,
        "unique_lines": unique_lines.len(),
        "chunk_count": chunk_infos.len(),
        "chunk_size": chunk_size,
        "overlap": overlap,
        "url": manifest.url,
        "line_store": {
            "id": line_store.id,
            "url": line_store.url,
        },
        "chunks": chunk_infos,
    })))
}

fn with_base_url(url: &str) -> String {
    let base_path = env::var("BASE_PATH").unwrap_or_default();
    if base_path.is_empty() || !url.starts_with("/paste/") {
        url.to_string()
    } else {
        format!(
            "{}/{}",
            base_path.trim_end_matches('/'),
            url.trim_start_matches('/')
        )
    }
}

fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

struct LineChunk {
    start_line: usize,
    end_line: usize,
    line_ids: Vec<usize>,
}

fn build_line_chunks(lines: &[String], chunk_size: usize, overlap: usize) -> Vec<LineChunk> {
    if lines.is_empty() {
        return Vec::new();
    }
    let mut chunks: Vec<LineChunk> = Vec::new();
    let mut start = 0usize;
    while start < lines.len() {
        let mut end = start;
        let mut bytes = 0usize;
        while end < lines.len() {
            let next = bytes + lines[end].len() + 1;
            if end > start && next > chunk_size {
                break;
            }
            bytes = next;
            end += 1;
        }
        if end == start {
            end = start + 1;
        }
        let line_ids: Vec<usize> = (start..end).collect();
        chunks.push(LineChunk {
            start_line: start,
            end_line: end,
            line_ids,
        });
        if end == lines.len() {
            break;
        }
        start = end.saturating_sub(overlap);
    }
    chunks
}

fn chunk_text(lines: &[String], chunk: &LineChunk) -> String {
    chunk
        .line_ids
        .iter()
        .map(|idx| lines[*idx].as_str())
        .collect::<Vec<_>>()
        .join("\n")
}

fn render_chunk_json(index: usize, chunk: &LineChunk, text: &str) -> String {
    serde_json::json!({
        "version": 1,
        "type": "chunked-export-chunk",
        "chunk_index": index,
        "start_line": chunk.start_line,
        "end_line": chunk.end_line,
        "line_count": chunk.line_ids.len(),
        "byte_len": text.len(),
        "sha256": sha256_hex(text.as_bytes()),
        "line_ids": chunk.line_ids,
        "text": text,
    })
    .to_string()
}

async fn create_chunk_line_store(title: &str, lines: &[String]) -> Result<StoredChunkPaste> {
    let mut content = String::new();
    for (idx, line) in lines.iter().enumerate() {
        let obj = serde_json::json!({
            "id": idx,
            "sha256": sha256_hex(line.as_bytes()),
            "text": line,
        });
        content.push_str(&obj.to_string());
        content.push('\n');
    }
    create_chunked_paste(
        &format!("{} line store", title),
        content,
        vec![
            "chunked".to_string(),
            "line-store".to_string(),
            "dedup".to_string(),
        ],
    )
    .await
}

/// GET /ipfs/{cid} - Proxy IPFS content (local flatfs only, no shell-out)
pub async fn ipfs_proxy(path: web::Path<String>) -> Result<HttpResponse> {
    let cid = path.into_inner();

    if let Some(block) = ipfs::ipfs_cat(&cid) {
        let ct = match &block[..4.min(block.len())] {
            [0x89, 0x50, 0x4E, 0x47] => "image/png",
            [0xFF, 0xD8, ..] => "image/jpeg",
            [0x3C, ..] => "text/html; charset=utf-8",
            [0x7B, ..] => "application/json",
            _ if block.starts_with(b"<!") || block.starts_with(b"<html") => {
                "text/html; charset=utf-8"
            }
            _ => "application/octet-stream",
        };
        return Ok(HttpResponse::Ok().content_type(ct).body(block));
    }

    Ok(HttpResponse::NotFound().body(format!("IPFS CID not found: {}", cid)))
}

/// GET /gallery - NFT gallery from enriched directory
pub async fn gallery() -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_default();
    let nft_dir = env::var("NFT_DIR")
        .unwrap_or_else(|_| "/mnt/data1/time-2026/03-march/13/nft_enriched".to_string());

    let mut items = Vec::new();
    if let Ok(entries) = fs::read_dir(&nft_dir) {
        for entry in entries.flatten() {
            if !entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                continue;
            }
            let qid = entry.file_name().to_string_lossy().to_string();
            let meta_path = entry.path().join("metadata.rdfa");
            let mut meta = std::collections::HashMap::new();
            if let Ok(content) = fs::read_to_string(&meta_path) {
                for line in content.lines() {
                    if let Some((k, v)) = line.split_once('=') {
                        meta.insert(k.to_string(), v.to_string());
                    }
                }
            }
            let name = meta.get("name").cloned().unwrap_or_else(|| qid.clone());
            let desc = meta.get("description").cloned().unwrap_or_default();
            let html_cid = meta.get("ipfs_html_cid").cloned().unwrap_or_default();
            let nft_cid = meta.get("ipfs_nft_cid").cloned().unwrap_or_default();
            let dir_cid = meta.get("ipfs_dir_cid").cloned().unwrap_or_default();
            let witness = meta.get("witness").cloned().unwrap_or_default();
            let has_image = entry.path().join("source.jpg").exists();

            let img_html = if has_image && !nft_cid.is_empty() {
                format!(
                    r#"<img src="{}/ipfs/{}" style="max-width:200px;max-height:150px;border-radius:4px" alt="{}">"#,
                    base_path, nft_cid, name
                )
            } else if has_image {
                format!(
                    r#"<img src="{}/gallery/img/{}" style="max-width:200px;max-height:150px;border-radius:4px" alt="{}">"#,
                    base_path, qid, name
                )
            } else {
                r#"<div style="width:200px;height:150px;background:#222;display:flex;align-items:center;justify-content:center;border-radius:4px">🖼️ No image</div>"#.to_string()
            };

            items.push(format!(
                r#"<div style="background:#1a1a1a;padding:15px;border-radius:8px;display:flex;gap:15px;align-items:start">
{img_html}
<div>
<h3 style="color:#0ff;margin:0"><a href="{bp}/ipfs/{hcid}">{name}</a></h3>
<p style="color:#999;margin:5px 0">{desc}</p>
<p style="font-size:12px;color:#666">
<a href="https://www.wikidata.org/wiki/{qid}">{qid}</a>
{nft_link}
{dir_link}
</p>
<code style="font-size:10px;color:#555">{witness}</code>
</div></div>"#,
                bp = base_path,
                hcid = html_cid,
                name = name,
                desc = desc,
                qid = qid,
                nft_link = if nft_cid.is_empty() { String::new() } else { format!(r#"| <a href="{}/ipfs/{}">NFT</a>"#, base_path, nft_cid) },
                dir_link = if dir_cid.is_empty() { String::new() } else { format!(r#"| <a href="{}/ipfs/{}">IPFS Dir</a>"#, base_path, dir_cid) },
                witness = &witness[..witness.len().min(16)],
            ));
        }
    }

    let html = format!(
        r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>NFT Gallery</title>
<style>
body{{font-family:system-ui,sans-serif;max-width:900px;margin:0 auto;padding:20px;background:#111;color:#eee}}
a{{color:#0ff;text-decoration:none}}
.nav{{background:#1a1a1a;padding:10px;margin-bottom:20px;border-radius:8px}}
.nav a{{margin-right:15px}}
h1{{color:#0ff}}
</style></head><body>
<div class="nav">
<a href="{bp}/">🏠 Home</a>
<a href="{bp}/browse">📚 Browse</a>
<a href="{bp}/gallery">🖼️ Gallery</a>
</div>
<h1>🖼️ NFT Gallery</h1>
<p style="color:#999">{count} enriched entities</p>
<div style="display:flex;flex-direction:column;gap:10px">{items}</div>
</body></html>"#,
        bp = base_path,
        count = items.len(),
        items = items.join("\n"),
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// GET /gallery/img/{qid} - Serve source image from enriched dir
pub async fn gallery_image(path: web::Path<String>) -> Result<HttpResponse> {
    let qid = path.into_inner();
    let nft_dir = env::var("NFT_DIR")
        .unwrap_or_else(|_| "/mnt/data1/time-2026/03-march/13/nft_enriched".to_string());
    let img_path = format!("{}/{}/source.jpg", nft_dir, qid);
    match fs::read(&img_path) {
        Ok(data) => {
            let ct = if data.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
                "image/png"
            } else {
                "image/jpeg"
            };
            Ok(HttpResponse::Ok().content_type(ct).body(data))
        }
        Err(_) => Ok(HttpResponse::NotFound().body("Image not found")),
    }
}

/// Enrich a Wikidata QID — disabled, no shell-out allowed.
async fn enrich_qid(_qid: &str) -> Result<HttpResponse> {
    log::warn!("enrich_qid called but shell-out is disabled by requirements");
    Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
        "error": "enrichment pipeline disabled: no shell-out allowed",
    })))
}

/// GET /plugins - List available plugins
pub async fn list_plugins(
    registry: web::Data<std::sync::Mutex<plugin::PluginRegistry>>,
) -> Result<HttpResponse> {
    let reg = registry.lock().unwrap();
    let plugins: Vec<_> = reg
        .list()
        .iter()
        .map(|(n, v, d)| serde_json::json!({"name": n, "version": v, "description": d}))
        .collect();
    Ok(HttpResponse::Ok().json(serde_json::json!({"plugins": plugins})))
}

/// POST /plugin/{name}/{id} - Run plugin on a paste
pub async fn run_plugin(
    path: web::Path<(String, String)>,
    registry: web::Data<std::sync::Mutex<plugin::PluginRegistry>>,
    body: web::Json<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let (plugin_name, paste_id) = path.into_inner();
    let base_path = env::var("BASE_PATH").unwrap_or_default();
    let base_url = env::var("BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8090".to_string());
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());

    // Load paste content
    let content = storage::load_content(&paste_id).unwrap_or_default();
    let url = format!("{}{}/paste/{}", base_url, base_path, paste_id);

    let mut extra = body.into_inner();
    extra.insert("base_path".into(), base_path.clone());
    let input = plugin::PluginInput {
        id: paste_id.clone(),
        content: content.into_bytes(),
        mime: "text/plain".into(),
        url,
        extra,
    };

    let reg = registry.lock().unwrap();
    match reg.execute(&plugin_name, &input) {
        Ok(result) => Ok(HttpResponse::Ok().json(result)),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({"error": e}))),
    }
}

// ═════════════════════════════════════════════════════════════════════
// Archive Upload + Viewer
// ═════════════════════════════════════════════════════════════════════

/// Temporary in-memory storage for extracted archives keyed by session ID.
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref ARCHIVE_STORE: Mutex<HashMap<String, crate::archive::ArchiveResult>> =
        Mutex::new(HashMap::new());
}

/// POST /upload-archive — upload a .tar.gz/.zip/etc., extract, return listing
pub async fn upload_archive(mut payload: actix_multipart::Multipart) -> Result<HttpResponse> {
    use actix_web::web::BytesMut;
    use futures_util::StreamExt as _;
    use sha2::{Digest, Sha256};

    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let mut file_data: Vec<u8> = Vec::new();
    let mut orig_name = String::new();
    let mut title = String::new();
    let mut description = String::new();

    while let Some(item) = payload.next().await {
        let mut field = item.map_err(|e| actix_web::error::ErrorBadRequest(e))?;
        let field_name = field.name().unwrap_or("").to_string();
        let mut buf: Vec<u8> = Vec::new();
        while let Some(chunk) = field.next().await {
            let data = chunk.map_err(|e| actix_web::error::ErrorBadRequest(e))?;
            buf.extend_from_slice(&data);
        }
        match field_name.as_str() {
            "file" => {
                orig_name = field
                    .content_disposition()
                    .and_then(|cd| cd.get_filename().map(|s| s.to_string()))
                    .unwrap_or_else(|| "archive.tar.gz".to_string());
                file_data = buf;
            }
            "title" => {
                title = clean_field(&String::from_utf8_lossy(&buf));
            }
            "description" => {
                description = clean_field(&String::from_utf8_lossy(&buf));
            }
            _ => {}
        }
    }

    if file_data.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "no file"})));
    }

    // Extract the archive
    let mut result = match crate::archive::extract(&file_data, &orig_name) {
        Ok(r) => r,
        Err(e) => return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": e}))),
    };
    if title.is_empty() {
        title = result.title.clone();
    }
    if description.is_empty() {
        description =
            archive_name_description(&title, &orig_name, result.entry_count, file_data.len());
    }
    result.title = title.clone();
    result.description = description.clone();

    // Generate a session ID
    let mut hasher = Sha256::new();
    hasher.update(&file_data);
    hasher.update(ts.as_bytes());
    let session_id = hex::encode(&hasher.finalize())[..16].to_string();

    // Store for later access
    let entry_count = result.entries.len();
    ARCHIVE_STORE
        .lock()
        .unwrap()
        .insert(session_id.clone(), result);

    // ── Register the archive file itself in the spool + index ──────────
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let mut hasher2 = Sha256::new();
    hasher2.update(&file_data);
    let hash = hasher2.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    let ipfs_cid = ipfs::ipfs_add_bytes(&file_data);
    let slug = tagging::slugify(&title);
    let ext = orig_name.rsplit('.').next().unwrap_or("bin");
    let filename = format!("{}_{}.{}", ts, slug, ext);
    let steam_id = filename
        .rsplit_once('.')
        .map(|(s, _)| s)
        .unwrap_or(&filename)
        .to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);

    // Write the raw archive file to spool
    fs::write(&uucp, &file_data).ok();
    // Write metadata sidecar
    let meta = format!("--- {} ---\nTitle: {}\nDescription: {}\nMime: application/octet-stream\nCID: {}\nWitness: {}\nIPFS: {}\nSize: {}\nEntries: {}\n",
        steam_id, title, description, local_cid, witness, ipfs_cid.as_deref().unwrap_or(""), file_data.len(), entry_count);
    fs::write(format!("{}.meta", uucp), &meta).ok();
    // CID dedup file
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    fs::write(&cid_file, &steam_id).ok();
    // Index entry
    write_index_entry(
        &uucp_dir,
        &steam_id,
        &title,
        Some(&description),
        vec!["archive".to_string(), ext.to_string()],
        &local_cid,
        &witness,
        &filename,
        file_data.len(),
        ipfs_cid,
        None,
        Some(session_id.clone()),
    );

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "session_id": session_id,
        "filename": orig_name,
        "title": title,
        "description": description,
        "entry_count": entry_count,
        "id": steam_id,
        "cid": local_cid,
        "url": format!("/browse-archive/{}", session_id),
        "paste_url": format!("/paste/{}", steam_id),
    })))
}

/// GET /archive-viewer/{session_id} — HTML view of extracted files with checkboxes
pub async fn archive_viewer(path: web::Path<String>) -> Result<HttpResponse> {
    let session_id = path.into_inner();
    let store = ARCHIVE_STORE.lock().unwrap();
    let result = match store.get(&session_id) {
        Some(r) => r,
        None => return Ok(HttpResponse::NotFound().body("Archive session not found or expired")),
    };

    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let mut file_rows = String::new();
    let mut total_size = 0u64;

    for (i, entry) in result.entries.iter().enumerate() {
        if entry.is_dir {
            file_rows.push_str(&format!(
                r#"<tr style="color:#666"><td><input type="checkbox" disabled></td><td>📁 {}</td><td>—</td><td>dir</td></tr>"#,
                html_escape(&entry.path)
            ));
        } else {
            total_size += entry.size;
            let size_str = if entry.size > 1024 * 1024 {
                format!("{:.1} MB", entry.size as f64 / (1024.0 * 1024.0))
            } else if entry.size > 1024 {
                format!("{:.1} KB", entry.size as f64 / 1024.0)
            } else {
                format!("{} B", entry.size)
            };
            let has_preview = entry.content.is_some();
            let preview_btn = if has_preview {
                format!(
                    r#"<button class="preview-btn" onclick="previewFile({},'{}')">👁️</button>"#,
                    i,
                    html_escape(&entry.path)
                )
            } else {
                String::new()
            };
            let post_btn = if has_preview {
                format!(
                    r#"<button class="post-btn" onclick="postFile({},'{}')">📤</button>"#,
                    i,
                    html_escape(&entry.path)
                )
            } else {
                String::new()
            };
            file_rows.push_str(&format!(
                r#"<tr>
                  <td><input type="checkbox" class="file-select" value="{}" data-idx="{}" onchange="updateSelectAll()"></td>
                  <td>📄 {} {} {}</td>
                  <td>{}</td>
                  <td>{}</td>
                </tr>"#,
                html_escape(&entry.path),
                i,
                html_escape(&entry.path),
                preview_btn,
                post_btn,
                size_str,
                if entry.content.is_some() { "text" } else { "binary" },
            ));
        }
    }

    let html = format!(
        r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<title>Archive Viewer — {}</title>
<style>
body{{font-family:monospace;max-width:900px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
.nav a{{margin-right:15px}}
table{{width:100%;border-collapse:collapse;margin:10px 0}}
th,td{{text-align:left;padding:8px;border-bottom:1px solid #333}}
th{{color:#0ff}}
.file-select{{cursor:pointer}}
.actions{{background:#111;padding:15px;margin:15px 0;border:1px solid #0f0}}
.actions button{{background:#0f0;color:#000;border:none;padding:10px 20px;cursor:pointer;font-weight:bold;margin-right:10px}}
.actions button:disabled{{background:#333;color:#666;cursor:not-allowed}}
.post-btn,.preview-btn{{background:transparent;border:1px solid #0f0;color:#0f0;cursor:pointer;padding:2px 6px;margin-left:4px;font-size:12px;border-radius:3px}}
.post-btn:hover,.preview-btn:hover{{background:#0f0;color:#000}}
input[type="checkbox"]{{accent-color:#0f0}}
.preview-modal{{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:#0a0a0a;z-index:1000;overflow:auto;padding:40px;box-sizing:border-box}}
.preview-modal pre{{background:#111;padding:20px;border:1px solid #0f0;white-space:pre-wrap;word-wrap:break-word;max-height:80vh;overflow:auto}}
.summary{{color:#999;font-size:12px;margin-bottom:10px}}
</style>
</head><body>
<div class="nav">
<a href="{}/">🏠 Home</a>
<a href="{}/browse">📚 Browse</a>
<a href="{}/gallery">🖼️ Gallery</a>
<a href="{}/splitter/">✂️ Splitter</a>
</div>
<h1>📦 Archive: {}</h1>
<p class="summary">{} files · {} total · {} entries</p>

<div class="actions">
  <label><input type="checkbox" id="selectAll" onchange="toggleAll()"> Select All</label>
  <button id="generateBtn" onclick="generateAllm()">📝 Generate allm.txt</button>
  <button id="splitBtn" onclick="splitSelected()">✂️ Split Selected</button>
</div>

<table>
<thead><tr><th style="width:30px"></th><th>File</th><th>Size</th><th>Type</th></tr></thead>
<tbody>
<tr style="color:#666"><td></td><td>📁 / (root)</td><td>{}</td><td>dir</td></tr>
{}
</tbody>
</table>

<div id="previewModal" class="preview-modal">
  <button onclick="closePreview()" style="position:sticky;top:10px;float:right;background:#f00;color:#fff;border:none;padding:5px 15px;cursor:pointer">✕ Close</button>
  <h3 id="previewTitle"></h3>
  <pre id="previewContent"></pre>
</div>

<script>
const files = {{}};
const base_path = '{}';
const session_id = '{}';

function toggleAll() {{
  const checked = document.getElementById('selectAll').checked;
  document.querySelectorAll('.file-select').forEach(cb => cb.checked = checked);
}}

function updateSelectAll() {{
  const all = document.querySelectorAll('.file-select');
  const checked = document.querySelectorAll('.file-select:checked');
  document.getElementById('selectAll').checked = all.length === checked.length;
}}

async function generateAllm() {{
  const checked = Array.from(document.querySelectorAll('.file-select:checked')).map(cb => cb.value);
  if (checked.length === 0) {{ alert('Select at least one file.'); return; }}
  const btn = document.getElementById('generateBtn');
  btn.disabled = true; btn.textContent = '⏳ Generating...';
  try {{
    const res = await fetch(base_path + '/archive-generate/' + session_id, {{
      method: 'POST',
      headers: {{'Content-Type': 'application/json'}},
      body: JSON.stringify({{ files: checked }})
    }});
    const data = await res.json();
    if (data.error) {{ alert('Error: ' + data.error); return; }}
    // Navigate to the generated paste
    window.location = base_path + data.url;
  }} catch(e) {{ alert('Error: ' + e.message); }}
  finally {{ btn.disabled = false; btn.textContent = '📝 Generate allm.txt'; }}
}}

async function splitSelected() {{
  const checked = Array.from(document.querySelectorAll('.file-select:checked')).map(cb => cb.value);
  if (checked.length === 0) {{ alert('Select at least one file.'); return; }}
  const btn = document.getElementById('splitBtn');
  btn.disabled = true; btn.textContent = '⏳ Splitting...';
  try {{
    const res = await fetch(base_path + '/archive-split/' + session_id, {{
      method: 'POST',
      headers: {{'Content-Type': 'application/json'}},
      body: JSON.stringify({{ files: checked }})
    }});
    const data = await res.json();
    if (data.error) {{ alert('Error: ' + data.error); return; }}
    window.location = base_path + data.url;
  }} catch(e) {{ alert('Error: ' + e.message); }}
  finally {{ btn.disabled = false; btn.textContent = '✂️ Split Selected'; }}
}}

function previewFile(idx, name) {{
  fetch(base_path + '/archive-preview/' + session_id + '/' + idx)
    .then(r => r.json())
    .then(data => {{
      document.getElementById('previewTitle').textContent = name;
      document.getElementById('previewContent').textContent = data.content || '(binary file — no preview)';
      document.getElementById('previewModal').style.display = 'block';
    }});
}}

function closePreview() {{
  document.getElementById('previewModal').style.display = 'none';
}}

async function postFile(idx, name) {{
  if (!confirm('Post "' + name + '" as a new paste?')) return;
  try {{
    const res = await fetch(base_path + '/archive-post-file/' + session_id + '/' + idx, {{ method: 'POST' }});
    const data = await res.json();
    if (data.error) {{ alert('Error: ' + data.error); return; }}
    window.location = base_path + data.url;
  }} catch(e) {{ alert('Error: ' + e.message); }}
}}
</script>
</body></html>"#,
        result.filename,
        base_path,
        base_path,
        base_path,
        base_path,
        result.filename,
        result.entry_count,
        format_size(result.total_size),
        result.entries.len(),
        format_size(total_size),
        file_rows,
        base_path,
        session_id,
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// POST /archive-generate/{session_id} — concatenate selected files into a paste
pub async fn archive_generate(
    path: web::Path<String>,
    body: web::Json<HashMap<String, Vec<String>>>,
) -> Result<HttpResponse> {
    let session_id = path.into_inner();
    let files = body.into_inner().remove("files").unwrap_or_default();

    let store = ARCHIVE_STORE.lock().unwrap();
    let result = match store.get(&session_id) {
        Some(r) => r,
        None => {
            return Ok(
                HttpResponse::NotFound().json(serde_json::json!({"error": "Session expired"}))
            )
        }
    };

    let post_title = if result.title.trim().is_empty() {
        archive_name_title(&result.filename)
    } else {
        result.title.clone()
    };
    let post_description = if result.description.trim().is_empty() {
        archive_name_description(
            &post_title,
            &result.filename,
            result.entry_count,
            result.total_size as usize,
        )
    } else {
        result.description.clone()
    };

    // Build a table of contents
    let mut allm = String::new();
    allm.push_str(&format!("=== {}.TXT ===\n", post_title.to_uppercase()));
    allm.push_str(&format!("Source archive: {}\n", result.filename));
    allm.push_str(&format!(
        "Generated: {}\n",
        Utc::now().format("%Y-%m-%d %H:%M:%S UTC")
    ));
    allm.push_str(&format!("Selected files: {}\n\n", files.join(", ")));

    for file_path in &files {
        // Find the entry by path
        if let Some(entry) = result.entries.iter().find(|e| e.path == *file_path) {
            allm.push_str(&format!(
                "\n───── {} ({}) ─────\n",
                entry.path,
                format_size(entry.size)
            ));
            if let Some(ref content) = entry.content {
                allm.push_str(content);
                if !content.ends_with('\n') {
                    allm.push_str("\n");
                }
            } else {
                allm.push_str("[binary file — omitted]\n");
            }
        }
    }

    // Save as a paste
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let slug_title = if post_title.trim().is_empty() {
        "all".to_string()
    } else {
        tagging::slugify(&post_title)
    };
    let filename = format!("{}_all_{}.txt", ts, slug_title);
    let id = filename.trim_end_matches(".txt").to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);

    // Generate hash and CID
    let mut hasher = Sha256::new();
    hasher.update(allm.as_bytes());
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    let ipfs_cid = ipfs::ipfs_add(&allm);

    let paste_content = format!("--- {} ---\nTitle: {}\nDescription: {}\nKeywords: allm, archive, {}\nCID: {}\nWitness: {}\nIPFS: {}\n\n{}\n",
        id, post_title, post_description, result.filename, local_cid, witness, ipfs_cid.as_deref().unwrap_or(""), allm);

    fs::write(&uucp, &paste_content).ok();
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    fs::write(&cid_file, &id).ok();
    // Index entry so the allm appears in browse
    write_index_entry(
        &uucp_dir,
        &id,
        &post_title,
        Some(&post_description),
        vec!["allm".to_string(), "archive".to_string()],
        &local_cid,
        &witness,
        &filename,
        allm.len(),
        ipfs_cid,
        None,
        None,
    );

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id,
        "title": post_title,
        "description": post_description,
        "cid": local_cid,
        "witness": witness,
        "url": format!("/paste/{}", id),
        "size": allm.len(),
        "files": files.len(),
    })))
}

/// POST /archive-split/{session_id} — split selected files into chunks
pub async fn archive_split(
    path: web::Path<String>,
    body: web::Json<HashMap<String, Vec<String>>>,
) -> Result<HttpResponse> {
    let session_id = path.into_inner();
    let files = body.into_inner().remove("files").unwrap_or_default();

    let store = ARCHIVE_STORE.lock().unwrap();
    let result = match store.get(&session_id) {
        Some(r) => r,
        None => {
            return Ok(
                HttpResponse::NotFound().json(serde_json::json!({"error": "Session expired"}))
            )
        }
    };

    // Collect text from selected files
    let mut all_text = String::new();
    for file_path in &files {
        if let Some(entry) = result.entries.iter().find(|e| e.path == *file_path) {
            if let Some(ref content) = entry.content {
                all_text.push_str(&format!("\n───── {} ─────\n", entry.path));
                all_text.push_str(content);
                if !content.ends_with('\n') {
                    all_text.push_str("\n");
                }
            }
        }
    }

    if all_text.is_empty() {
        return Ok(HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "No text content in selected files"})));
    }

    // Split into chunks of ~100KB
    let chunk_size: usize = 100 * 1024;
    let chunks = crate::splitter::split_text(
        &all_text,
        chunk_size,
        crate::model::SplitUnit::Byte,
        crate::model::SplitMode::Word,
    );

    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let mut chunk_ids = Vec::new();

    for (i, chunk) in chunks.iter().enumerate() {
        let chunk_name = format!("split_{}_part{:04}", ts, i);
        let filename = format!("{}.txt", chunk_name);
        let uucp = format!("{}/{}", uucp_dir, filename);

        let mut hasher = Sha256::new();
        hasher.update(chunk.as_bytes());
        let hash = hasher.finalize();
        let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
        let witness = hex::encode(&hash);

        let paste_content = format!("--- {} ---\nTitle: {} (chunk {}/{})\nKeywords: split, chunk\nCID: {}\nWitness: {}\n\n{}\n",
            chunk_name, result.filename, i + 1, chunks.len(), local_cid, witness, chunk);

        fs::write(&uucp, &paste_content).ok();
        chunk_ids.push(chunk_name);
    }

    // Create an index paste linking all chunks
    let index_content = format!(
        "=== Split Index ===\nSource: {}\nDate: {}\nTotal chunks: {}\nFiles: {}\n\n",
        result.filename,
        Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
        chunks.len(),
        files.join(", ")
    );
    let index_content = index_content
        + &chunk_ids
            .iter()
            .enumerate()
            .map(|(i, id)| format!("Chunk {:04}: /paste/{}\n", i, id))
            .collect::<String>();

    let index_id = format!("split_index_{}", ts);
    let idx_filename = format!("{}.txt", index_id);
    let idx_uucp = format!("{}/{}", uucp_dir, idx_filename);
    fs::write(&idx_uucp, &index_content).ok();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "chunks": chunks.len(),
        "chunk_ids": chunk_ids,
        "total_size": all_text.len(),
        "url": format!("/paste/{}", index_id),
    })))
}

/// GET /archive-preview/{session_id}/{index} — JSON preview of a single file
pub async fn archive_preview(path: web::Path<(String, usize)>) -> Result<HttpResponse> {
    let (session_id, idx) = path.into_inner();
    let store = ARCHIVE_STORE.lock().unwrap();
    let result = match store.get(&session_id) {
        Some(r) => r,
        None => {
            return Ok(
                HttpResponse::NotFound().json(serde_json::json!({"error": "Session expired"}))
            )
        }
    };

    match result.entries.get(idx) {
        Some(entry) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "path": entry.path,
            "size": entry.size,
            "content": entry.content.as_deref().unwrap_or(""),
            "is_text": entry.content.is_some(),
        }))),
        None => {
            Ok(HttpResponse::NotFound().json(serde_json::json!({"error": "Index out of range"})))
        }
    }
}

/// POST /archive-post-file/{session_id}/{idx} — post a single file from archive as a paste
pub async fn archive_post_file(path: web::Path<(String, usize)>) -> Result<HttpResponse> {
    let (session_id, idx) = path.into_inner();
    let store = ARCHIVE_STORE.lock().unwrap();
    let result = match store.get(&session_id) {
        Some(r) => r,
        None => {
            return Ok(
                HttpResponse::NotFound().json(serde_json::json!({"error": "Session expired"}))
            )
        }
    };

    let entry = match result.entries.get(idx) {
        Some(e) => e,
        None => {
            return Ok(
                HttpResponse::NotFound().json(serde_json::json!({"error": "Index out of range"}))
            )
        }
    };

    let content = match entry.content {
        Some(ref c) => c,
        None => {
            return Ok(HttpResponse::BadRequest()
                .json(serde_json::json!({"error": "Binary file — cannot post as paste"})))
        }
    };

    // Build paste content
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let slug_title = tagging::slugify(&entry.path);
    let filename = format!("{}_{}.txt", ts, slug_title);
    let id = format!("{}_{}", ts, slug_title);
    let uucp = format!("{}/{}", uucp_dir, filename);

    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    let ipfs_cid = ipfs::ipfs_add(content);

    let post_description = format!("From archive: {}", result.title);
    let paste_content = format!("--- {} ---\nTitle: {}\nDescription: {}\nKeywords: archive, {}\nCID: {}\nWitness: {}\nIPFS: {}\n\n--- From archive: {} ---\n\n{}\n",
        id, entry.path, post_description, result.title, local_cid, witness, ipfs_cid.as_deref().unwrap_or(""), result.filename, content);

    fs::write(&uucp, &paste_content).ok();
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    fs::write(&cid_file, &id).ok();

    // Index entry
    write_index_entry(
        &uucp_dir,
        &id,
        &entry.path,
        Some(&post_description),
        vec!["archive".to_string(), "paste".to_string()],
        &local_cid,
        &witness,
        &filename,
        content.len(),
        ipfs_cid,
        None,
        None,
    );

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id,
        "cid": local_cid,
        "witness": witness,
        "url": format!("/paste/{}", id),
        "size": content.len(),
    })))
}

/// GET /splitter/ — text splitter page
pub async fn splitter_page(query: web::Query<HashMap<String, String>>) -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let prefill = query
        .get("text")
        .map(|s| html_escape(s))
        .unwrap_or_default();

    let html = format!(
        r#"<!DOCTYPE html>
<meta charset="UTF-8">
<title>✂️ Text Splitter</title>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
.nav a{{margin-right:15px}}
textarea{{width:100%;height:300px;background:#111;color:#0f0;border:1px solid #0f0;padding:10px;font-family:monospace}}
input,select{{background:#111;color:#0f0;border:1px solid #0f0;padding:5px}}
button{{background:#0f0;color:#000;border:none;padding:10px 20px;cursor:pointer;font-weight:bold;margin:5px}}
button:disabled{{background:#333;color:#666;cursor:not-allowed}}
.result{{background:#111;padding:15px;margin:10px 0;border:1px solid #0f0;max-height:400px;overflow:auto}}
.result pre{{margin:5px 0;padding:10px;background:#0a0a0a;border-left:3px solid #0ff;white-space:pre-wrap;word-wrap:break-word}}
.chunk-label{{color:#0ff;font-weight:bold;margin-top:10px}}
.settings{{background:#111;padding:15px;margin:15px 0;border:1px solid #0f0}}
.profile-card{{display:inline-block;background:#1a1a2e;border:1px solid #0f0;border-radius:4px;padding:8px 12px;margin:4px;cursor:pointer;font-size:13px}}
.profile-card:hover{{background:#2a2a4e}}
.profile-card.active{{background:#0f0;color:#000;font-weight:bold}}
.profile-info{{font-size:11px;color:#888;margin-top:2px}}
</style>
</head><body>
<div class="nav">
<a href="{bp}/">🏠 Home</a>
<a href="{bp}/browse">📚 Browse</a>
<a href="{bp}/gallery">🖼️ Gallery</a>
</div>
<h1>✂️ Text Splitter</h1>
<p>Paste text below, pick a platform profile, and split into LLM-ready chunks.</p>

<div class="settings">
  <label>Platform profile: </label><br>
  <div id="profileCards" style="margin:8px 0"></div>
    <div style="margin-top:10px">
      <label>Chunk size: </label>
      <input id="chunkSize" type="number" value="100000" style="width:100px"> <span id="chunkUnit">words</span>
      <label style="margin-left:15px">Overlap: </label>
      <input id="overlap" type="number" value="0" style="width:80px"> <span id="overlapUnit">words</span>
      <label style="margin-left:15px">Split at: </label>
      <select id="splitMode">
        <option value="line">Newline</option>
        <option value="word" selected>Word boundary</option>
        <option value="exact">Exact</option>
      </select>
    </div>
    <p id="profileDesc" style="font-size:12px;color:#888;margin:5px 0"></p>
</div>

<textarea id="textInput" placeholder="Paste text to split here...">{prefill}</textarea><br>
  <button onclick="splitText(event)">✂️ Split</button>
  <button onclick="pasteFromClipboard()">📋 Paste from Clipboard</button>
  <button onclick="clearText()">🗑️ Clear</button>
  <button onclick="downloadAllChunks(event)">💾 Download ZIP</button>

<div id="result" style="display:none">
  <h3>Results</h3>
  <p id="summary"></p>
  <div id="chunks"></div>
  <button onclick="uploadAllChunks(event)">📤 Upload All as Pastes</button>
  <button onclick="downloadAllChunks(event)">💾 Download ZIP</button>
</div>

<script>
let profiles = [];
let activeProfile = null;

function unitLabel(unit) {{
  if (unit === 'word' || unit === 'words') return 'words';
  if (unit === 'token' || unit === 'tokens') return 'estimated tokens';
  return 'bytes';
}}

function formatNumber(n) {{
  return new Intl.NumberFormat().format(n || 0);
}}

function formatUnitValue(value, unit) {{
  const label = unitLabel(unit);
  if (label === 'bytes') {{
    if (value >= 1048576) return (value / 1048576).toFixed(value >= 104857600 ? 0 : 2) + ' MB';
    if (value >= 1024) return (value / 1024).toFixed(value >= 1048576 ? 0 : 1) + ' KB';
    return value + ' B';
  }}
  return formatNumber(value) + ' ' + label;
}}

function getProfile(name) {{
  return profiles.find(p => p.name === name) || null;
}}

async function loadProfiles() {{
  try {{
    const res = await fetch('{bp}/api/split-profiles');
    const data = await res.json();
    profiles = data.profiles || [];
    renderProfileCards();
    const defaultName = profiles.some(p => p.name === 'notebooklm') ? 'notebooklm' : (profiles.some(p => p.name === 'openai') ? 'openai' : (profiles[0] ? profiles[0].name : 'custom'));
    setTimeout(() => selectProfile(defaultName), 300);
  }} catch(e) {{
    console.error('Failed to load profiles:', e);
  }}
}}

function renderProfileCards() {{
  const container = document.getElementById('profileCards');
  container.innerHTML = '';
  profiles.forEach(p => {{
    const card = document.createElement('div');
    card.className = 'profile-card';
    card.dataset.name = p.name;
    const size = formatUnitValue(p.chunk_size, p.unit);
    const overlap = formatUnitValue(p.overlap, p.unit);
    const context = formatUnitValue(p.context_window, p.unit);
    card.innerHTML = p.label + '<div class="profile-info">' + size + ' chunks · ' + overlap + ' overlap · ' + context + ' context · ' + p.max_output_tokens + ' out</div>';
    card.onclick = () => selectProfile(p.name);
    container.appendChild(card);
  }});
  const custom = document.createElement('div');
  custom.className = 'profile-card';
  custom.dataset.name = 'custom';
  custom.innerHTML = '⚙️ Custom<div class="profile-info">Set your own chunk size</div>';
  custom.onclick = () => selectProfile('custom');
  container.appendChild(custom);
}}

function updateUnitLabels(unit) {{
  document.getElementById('chunkUnit').textContent = unitLabel(unit);
  document.getElementById('overlapUnit').textContent = unitLabel(unit);
}}

function selectProfile(name) {{
  activeProfile = name;
  document.querySelectorAll('.profile-card').forEach(c => c.classList.remove('active'));
  document.querySelector('.profile-card[data-name="'+name+'"]')?.classList.add('active');
  if (name === 'custom') {{
    document.getElementById('profileDesc').textContent = 'Custom — adjust chunk size, overlap, unit, and split mode manually';
    return;
  }}
  const p = getProfile(name);
  if (p) {{
    document.getElementById('chunkSize').value = p.chunk_size;
    document.getElementById('overlap').value = p.overlap;
    document.getElementById('splitMode').value = p.split_mode;
    updateUnitLabels(p.unit);
    document.getElementById('profileDesc').textContent = p.description || (p.label + ': ' + formatUnitValue(p.chunk_size, p.unit) + ' chunks, ' + formatUnitValue(p.overlap, p.unit) + ' overlap, ' + formatUnitValue(p.context_window, p.unit) + ' context, ' + p.max_output_tokens + ' output tokens');
  }}
}}

function splitBody() {{
  const chunkSize = parseInt(document.getElementById('chunkSize').value);
  const overlap = parseInt(document.getElementById('overlap').value) || 0;
  const splitMode = document.getElementById('splitMode').value;
  const unit = activeProfile && activeProfile !== 'custom' ? (getProfile(activeProfile)?.unit || 'word') : 'byte';
  const body = {{ content: document.getElementById('textInput').value, chunk_size: chunkSize, overlap: overlap, unit: unit, split_mode: splitMode }};
  if (activeProfile && activeProfile !== 'custom') body.profile = activeProfile;
  return body;
}}

async function splitText(event) {{
  const text = document.getElementById('textInput').value;
  if (!text.trim()) {{ alert('No text to split.'); return; }}
  const res = await fetch('{bp}/api/split', {{
    method: 'POST',
    headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify(splitBody())
  }});
  const data = await res.json();
  if (data.error) {{ alert('Error: ' + data.error); return; }}
  document.getElementById('result').style.display = 'block';
  const profileLabel = activeProfile && activeProfile !== 'custom' ? ' [' + activeProfile + ']' : '';
  const unit = data.unit || splitBody().unit;
  document.getElementById('summary').textContent = formatNumber(text.length) + ' bytes / ' + formatNumber(data.word_count) + ' words / ' + formatNumber(data.estimated_tokens) + ' estimated tokens → ' + data.chunks + ' chunks (' + formatUnitValue(data.chunk_size, unit) + ' chunks, ' + formatUnitValue(data.overlap, unit) + ' overlap)' + profileLabel;
  const chunksDiv = document.getElementById('chunks');
  chunksDiv.innerHTML = '';
  data.contents.forEach((c, i) => {{
    const div = document.createElement('div');
    div.innerHTML = '<div class="chunk-label">Chunk ' + (i+1) + '/' + data.chunks + ' (' + formatNumber(c.length) + ' chars)</div>'
      + '<pre>' + escHtml(c.slice(0,1000)) + (c.length > 1000 ? '<span style="color:#666">… (truncated)</span>' : '') + '</pre>';
    chunksDiv.appendChild(div);
  }});
}}

function escHtml(s) {{ return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }}

async function pasteFromClipboard() {{
  try {{ document.getElementById('textInput').value = await navigator.clipboard.readText(); }}
  catch(e) {{ alert('Cannot read clipboard: ' + e.message); }}
}}

function clearText() {{
  document.getElementById('textInput').value = '';
  document.getElementById('result').style.display = 'none';
}}

async function uploadAllChunks(event) {{
  const btn = event.target; btn.disabled = true; btn.textContent = '⏳ Uploading...';
  try {{
    const body = splitBody();
    body.title = 'splitter_upload';
    const res = await fetch('{bp}/api/split-upload', {{
      method: 'POST',
      headers: {{'Content-Type': 'application/json'}},
      body: JSON.stringify(body)
    }});
    const data = await res.json();
    if (data.error) {{ alert('Error: ' + data.error); return; }}
    window.location = '{bp}/paste/' + data.index_id;
  }} catch(e) {{ alert('Error: ' + e.message); }}
  finally {{ btn.disabled = false; btn.textContent = '📤 Upload All as Pastes'; }}
}}

async function downloadAllChunks(event) {{
  const btn = event.target;
  const text = document.getElementById('textInput').value;
  if (!text.trim()) {{ alert('No text to split.'); return; }}
  btn.disabled = true;
  btn.textContent = '⏳ Preparing ZIP...';
  const res = await fetch('{bp}/api/split-download', {{
    method: 'POST',
    headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify(splitBody())
  }});
  if (!res.ok) {{ alert('Error: ' + await res.text()); btn.disabled = false; btn.textContent = '💾 Download ZIP'; return; }}
  const blob = await res.blob();
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'split_chunks.zip';
  a.click();
  URL.revokeObjectURL(a.href);
  btn.disabled = false;
  btn.textContent = '💾 Download ZIP';
}}

const savedText = localStorage.getItem('splitter-text') || '';
if (savedText && !document.getElementById('textInput').value.trim()) {{
  document.getElementById('textInput').value = savedText;
}}

loadProfiles();
</script>
</body></html>"#,
        bp = base_path,
        prefill = prefill
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// POST /api/split — split text into chunks (JSON API)
pub async fn api_split(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let content = body.get("content").and_then(|v| v.as_str()).unwrap_or("");
    let split_options = match resolve_split_request(&body) {
        Ok(options) => options,
        Err(response) => return Ok(response),
    };
    let (
        effective_chunk_size,
        effective_overlap,
        effective_unit,
        effective_split_mode,
        profile_name,
    ) = split_options;

    if content.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "empty content"})));
    }

    let chunks = crate::splitter::split_text(
        content,
        effective_chunk_size,
        effective_unit.clone(),
        effective_split_mode.clone(),
    );
    let overlapped = crate::splitter::apply_overlap(
        chunks,
        effective_overlap,
        effective_unit.clone(),
        effective_split_mode.clone(),
    );

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "chunks": overlapped.len(),
        "chunk_size": effective_chunk_size,
        "overlap": effective_overlap,
        "unit": serde_json::to_value(&effective_unit).unwrap_or(serde_json::Value::String("byte".into())),
        "split_mode": serde_json::to_value(&effective_split_mode).unwrap_or(serde_json::Value::String("word".into())),
        "profile": profile_name,
        "total_size": content.len(),
        "word_count": crate::splitter::count_words(content),
        "estimated_tokens": crate::splitter::estimate_tokens(content),
        "contents": overlapped,
    })))
}

/// POST /api/split-paste — split a stored paste without returning all chunk bodies
pub async fn api_split_paste(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let content = match resolve_split_content(&body) {
        Ok(content) => content,
        Err(response) => return Ok(response),
    };
    let split_options = match resolve_split_request(&body) {
        Ok(options) => options,
        Err(response) => return Ok(response),
    };
    let (
        effective_chunk_size,
        effective_overlap,
        effective_unit,
        effective_split_mode,
        profile_name,
    ) = split_options;

    let chunks = crate::splitter::split_text(
        &content,
        effective_chunk_size,
        effective_unit.clone(),
        effective_split_mode.clone(),
    );
    let overlapped = crate::splitter::apply_overlap(
        chunks,
        effective_overlap,
        effective_unit.clone(),
        effective_split_mode.clone(),
    );
    let preview_limit: usize = body
        .get("preview_chars")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as usize;
    let preview_chunks: usize = body
        .get("preview_chunks")
        .and_then(|v| v.as_u64())
        .unwrap_or(3) as usize;
    let preview = overlapped
        .iter()
        .enumerate()
        .take(preview_chunks)
        .map(|(index, chunk)| {
            let text = if preview_limit == 0 {
                String::new()
            } else {
                chunk.chars().take(preview_limit).collect()
            };
            serde_json::json!({
                "index": index,
                "byte_len": chunk.len(),
                "text": text,
            })
        })
        .collect::<Vec<_>>();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "chunks": overlapped.len(),
        "chunk_size": effective_chunk_size,
        "overlap": effective_overlap,
        "unit": serde_json::to_value(&effective_unit).unwrap_or(serde_json::Value::String("byte".into())),
        "split_mode": serde_json::to_value(&effective_split_mode).unwrap_or(serde_json::Value::String("word".into())),
        "profile": profile_name,
        "total_size": content.len(),
        "word_count": crate::splitter::count_words(&content),
        "estimated_tokens": crate::splitter::estimate_tokens(&content),
        "preview_chunks": preview,
    })))
}

/// POST /api/split-download — download split chunks as a zip of plain .txt files
pub async fn api_split_download(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let content = match resolve_split_content(&body) {
        Ok(content) => content,
        Err(response) => return Ok(response),
    };
    let split_options = match resolve_split_request(&body) {
        Ok(options) => options,
        Err(response) => return Ok(response),
    };
    let (effective_chunk_size, effective_overlap, effective_unit, effective_split_mode, _) =
        split_options;

    if content.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "empty content"})));
    }

    let chunks = crate::splitter::split_text(
        &content,
        effective_chunk_size,
        effective_unit.clone(),
        effective_split_mode.clone(),
    );
    let overlapped = crate::splitter::apply_overlap(
        chunks,
        effective_overlap,
        effective_unit,
        effective_split_mode,
    );
    let zip_bytes = match create_split_zip(&overlapped) {
        Ok(bytes) => bytes,
        Err(e) => {
            return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("failed to create zip: {}", e)
            })))
        }
    };
    let filename = format!("split_chunks_{}.zip", Utc::now().format("%Y%m%d_%H%M%S"));

    Ok(HttpResponse::Ok()
        .content_type("application/zip")
        .insert_header((
            "Content-Disposition",
            format!("attachment; filename=\"{}\"", filename),
        ))
        .body(zip_bytes))
}

fn create_split_zip(chunks: &[String]) -> std::io::Result<Vec<u8>> {
    use std::io::{Cursor, Write};
    use zip::{write::FileOptions, CompressionMethod, ZipWriter};

    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    let options = FileOptions::<'_, ()>::default().compression_method(CompressionMethod::Deflated);

    for (i, chunk) in chunks.iter().enumerate() {
        let filename = format!("part_{:04}.txt", i + 1);
        zip.start_file(filename, options)?;
        zip.write_all(chunk.as_bytes())?;
    }

    Ok(zip.finish()?.into_inner())
}

/// POST /api/split-upload — split text and upload all chunks as pastes
pub async fn api_split_upload(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    use sha2::{Digest, Sha256};

    let content = match resolve_split_content(&body) {
        Ok(content) => content,
        Err(response) => return Ok(response),
    };
    let paste_id = body
        .get("paste_id")
        .and_then(|v| v.as_str())
        .or_else(|| body.get("id").and_then(|v| v.as_str()))
        .unwrap_or("paste");
    let title = body
        .get("title")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .unwrap_or_else(|| format!("split_{}", paste_id));
    let split_options = match resolve_split_request(&body) {
        Ok(options) => options,
        Err(response) => return Ok(response),
    };
    let (
        effective_chunk_size,
        effective_overlap,
        effective_unit,
        effective_split_mode,
        profile_name,
    ) = split_options;

    if content.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "empty content"})));
    }

    let chunks = crate::splitter::split_text(
        &content,
        effective_chunk_size,
        effective_unit.clone(),
        effective_split_mode.clone(),
    );
    let overlapped = crate::splitter::apply_overlap(
        chunks,
        effective_overlap,
        effective_unit,
        effective_split_mode,
    );

    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let mut chunk_ids = Vec::new();

    for (i, chunk) in overlapped.iter().enumerate() {
        let id = format!("{}_{}_part{:04}", ts, title, i);
        let filename = format!("{}.txt", id);
        let uucp = format!("{}/{}", uucp_dir, filename);

        let mut hasher = Sha256::new();
        hasher.update(chunk.as_bytes());
        let hash = hasher.finalize();
        let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
        let witness = hex::encode(&hash);

        let paste_content = format!("--- {} ---\nTitle: {} (chunk {}/{})\nKeywords: split, chunk\nCID: {}\nWitness: {}\n\n{}\n",
            id, title, i + 1, overlapped.len(), local_cid, witness, chunk);

        fs::write(&uucp, &paste_content).ok();
        chunk_ids.push(id);
    }

    // Index paste
    let index_id = format!("{}_{}_index", ts, title);
    let index_filename = format!("{}.txt", index_id);
    let index_uucp = format!("{}/{}", uucp_dir, index_filename);
    let index_content = format!(
        "=== Split Index ===\nTitle: {}\nDate: {}\nTotal chunks: {}\nProfile: {}\n\n{}\n",
        title,
        Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
        overlapped.len(),
        profile_name.unwrap_or_else(|| "custom".to_string()),
        chunk_ids
            .iter()
            .enumerate()
            .map(|(i, id)| format!("Chunk {:04}: /paste/{}\n", i, id))
            .collect::<String>()
    );
    fs::write(&index_uucp, &index_content).ok();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "chunks": overlapped.len(),
        "chunk_ids": chunk_ids,
        "index_id": index_id,
        "url": format!("/paste/{}", index_id),
        "total_size": content.len(),
        "word_count": crate::splitter::count_words(&content),
        "estimated_tokens": crate::splitter::estimate_tokens(&content),
    })))
}

fn resolve_split_request(
    body: &serde_json::Value,
) -> std::result::Result<(usize, usize, SplitUnit, SplitMode, Option<String>), HttpResponse> {
    let chunk_size = body
        .get("chunk_size")
        .and_then(|v| v.as_u64())
        .unwrap_or(102400) as usize;
    let overlap = body.get("overlap").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
    let profile_name = body
        .get("profile")
        .and_then(|v| v.as_str())
        .map(str::to_string);

    if let Some(name) = profile_name.as_deref() {
        if let Some(profile) = SplitProfile::find_preset(name) {
            return Ok((
                profile.chunk_size,
                profile.overlap,
                profile.unit,
                profile.split_mode,
                Some(name.to_string()),
            ));
        }

        return Err(HttpResponse::BadRequest().json(serde_json::json!({
            "error": format!("unknown profile: {}", name),
            "available": SplitProfile::presets().iter().map(|p| p.name.clone()).collect::<Vec<_>>()
        })));
    }

    let unit = match body.get("unit").and_then(|v| v.as_str()) {
        Some(value) => parse_split_unit(value)
            .map_err(|e| HttpResponse::BadRequest().json(serde_json::json!({"error": e})))?,
        None => SplitUnit::Byte,
    };
    let split_mode = match body.get("split_mode").and_then(|v| v.as_str()) {
        Some(value) => parse_split_mode(value)
            .map_err(|e| HttpResponse::BadRequest().json(serde_json::json!({"error": e})))?,
        None => SplitMode::Word,
    };

    Ok((chunk_size, overlap, unit, split_mode, None))
}

fn parse_split_unit(value: &str) -> std::result::Result<SplitUnit, String> {
    match value.to_ascii_lowercase().as_str() {
        "byte" | "bytes" | "b" => Ok(SplitUnit::Byte),
        "word" | "words" | "w" => Ok(SplitUnit::Word),
        "token" | "tokens" | "tok" => Ok(SplitUnit::Token),
        _ => Err(format!("unknown unit: {}", value)),
    }
}

fn parse_split_mode(value: &str) -> std::result::Result<SplitMode, String> {
    match value.to_ascii_lowercase().as_str() {
        "line" | "newline" => Ok(SplitMode::Line),
        "word" | "word-boundary" => Ok(SplitMode::Word),
        "exact" => Ok(SplitMode::Exact),
        _ => Err(format!("unknown split_mode: {}", value)),
    }
}

// ── Helpers ─────────────────────────────────────────────────────────

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn format_size(size: u64) -> String {
    if size > 1024 * 1024 * 1024 {
        format!("{:.2} GiB", size as f64 / (1024.0 * 1024.0 * 1024.0))
    } else if size > 1024 * 1024 {
        format!("{:.2} MiB", size as f64 / (1024.0 * 1024.0))
    } else if size > 1024 {
        format!("{:.2} KiB", size as f64 / 1024.0)
    } else {
        format!("{} B", size)
    }
}

// ─── Nix Skill Handlers ────────────────────────────────────────────────

/// POST /api/nix-skill/analyze — Analyze a flake.nix file
/// Body: {"path": "/path/to/flake.nix"}
pub async fn nix_skill_analyze(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let path = match body.get("path").and_then(|v| v.as_str()) {
        Some(p) => p.to_string(),
        None => {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Missing 'path' parameter"
            })))
        }
    };

    match crate::nix_skill::analyze_flake(&path) {
        Ok(analysis) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "status": "ok",
            "analysis": analysis,
        }))),
        Err(e) => Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": e,
            "path": path,
        }))),
    }
}

/// POST /api/nix-skill/find — Find and analyze all flake.nix files in a directory
/// Body: {"directory": "~/dasl", "max_depth": 4}
pub async fn nix_skill_find(body: web::Json<serde_json::Value>) -> Result<HttpResponse> {
    let directory = body
        .get("directory")
        .and_then(|v| v.as_str())
        .unwrap_or("~/dasl")
        .to_string();
    let max_depth: usize = body.get("max_depth").and_then(|v| v.as_i64()).unwrap_or(4) as usize;

    let dir = directory.replace(
        "~",
        &env::var("HOME").unwrap_or_else(|_| "/home/mdupont".to_string()),
    );

    // Find all flake.nix files up to max_depth
    let mut paths = Vec::new();
    let mut dirs_to_check = vec![(dir.clone(), 0)];

    while let Some((current_dir, depth)) = dirs_to_check.pop() {
        if depth > max_depth {
            continue;
        }
        let entries = match std::fs::read_dir(&current_dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let entry_path = entry.path();
            if entry_path.is_dir() && depth < max_depth {
                dirs_to_check.push((entry_path.display().to_string(), depth + 1));
            } else if entry_path.is_file()
                && entry_path.file_name().map_or(false, |n| n == "flake.nix")
            {
                paths.push(entry_path.display().to_string());
            }
        }
    }

    let analyses = crate::nix_skill::analyze_flakes(&paths);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "directory": directory,
        "max_depth": max_depth,
        "total_flakes": analyses.len(),
        "flakes": analyses,
    })))
}

// ─── Split Profile API ────────────────────────────────────────────────

/// GET /api/split-profiles — list all split profiles (built-in + custom)
pub async fn list_split_profiles() -> Result<HttpResponse> {
    let presets = SplitProfile::presets();
    // TODO: load custom profiles from a config file
    let custom: Vec<SplitProfile> = Vec::new();
    let all: Vec<&SplitProfile> = presets.iter().chain(custom.iter()).collect();
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "profiles": all,
    })))
}

/// GET /api/split-profiles/{name} — get a specific profile
pub async fn get_split_profile(path: web::Path<String>) -> Result<HttpResponse> {
    let name = path.into_inner();
    if let Some(profile) = SplitProfile::find_preset(&name) {
        Ok(HttpResponse::Ok().json(profile))
    } else {
        Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": format!("profile '{}' not found", name),
            "available": SplitProfile::presets().iter().map(|p| p.name.clone()).collect::<Vec<_>>()
        })))
    }
}

/// POST /api/split-profiles — create a custom profile
pub async fn create_split_profile(body: web::Json<SplitProfileRequest>) -> Result<HttpResponse> {
    // Don't allow overwriting built-in profiles
    if SplitProfile::find_preset(&body.name).is_some() {
        return Ok(HttpResponse::Conflict().json(serde_json::json!({
            "error": format!("cannot overwrite built-in profile '{}'", body.name)
        })));
    }

    let profile = SplitProfile {
        name: body.name.clone(),
        label: body.label.clone().unwrap_or_else(|| body.name.clone()),
        context_window: body.context_window.unwrap_or(body.chunk_size * 2),
        chunk_size: body.chunk_size,
        unit: body.unit.clone().unwrap_or(SplitUnit::Byte),
        overlap: body.overlap.unwrap_or(0),
        max_output_tokens: body.max_output_tokens.unwrap_or(4096),
        split_mode: body.split_mode.clone().unwrap_or(SplitMode::Word),
        builtin: false,
        description: body.description.clone(),
    };

    // TODO: persist custom profiles to a config file
    Ok(HttpResponse::Created().json(profile))
}

// ─── Git Mount Handlers ──────────────────────────────────────────────

/// GET /git-browse — list all mounted git repos
pub async fn git_browse() -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let mut cache = crate::git_mount::get_cache();

    let mount_cards: String = cache.mounts.values().map(|m| {
        let commit_short = m.head_commit.as_deref()
            .map(|c| &c[..7.min(c.len())])
            .unwrap_or("n/a");
        let branch = m.branch.as_deref().unwrap_or("detached");

        format!(r#"<div class="mount-card" style="background:#111;border:1px solid #0f0;border-radius:8px;padding:15px;margin:10px 0">
<h3><a href="{}/git-browse/{}">📁 {}</a></h3>
<p style="color:#666;font-size:12px">🔀 {} · {}</p>
</div>"#, base_path, m.id, m.name, branch, commit_short)
    }).collect();

    let stats = cache.stats();

    let html = format!(
        r##"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Git Mounts — Kant Pastebin</title>
<style>
body{{font-family:monospace;max-width:900px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
h1{{color:#0f0;border-bottom:1px solid #333}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
.mount-card:hover{{border-color:#0ff}}
</style>
</head><body>
<div class="nav"><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/git-browse">📁 Git</a></div>
<h1>📁 Git Mounts</h1>
<p style="color:#888">Mounted git repositories — demand-cached, LRU-evicted</p>
<p style="color:#666;font-size:12px">Cache: {} files · {} dirs · {} total accesses</p>
<div>{}</div>
</body></html>"##,
        base_path,
        base_path,
        base_path,
        stats["cached_files"],
        stats["cached_dirs"],
        stats["total_accesses"],
        mount_cards
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// GET /git-browse/{mount_id} — browse a mounted repo
pub async fn git_browse_mount(
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let mount_id = path.into_inner();
    let sub_path = query.get("path").map(|s| s.as_str()).unwrap_or("");

    let (entries, mount_name, commit_short, branch) = {
        let mut cache = crate::git_mount::get_cache();
        let entries = cache.list_dir(&mount_id, sub_path);

        if entries.is_empty() && !sub_path.is_empty() {
            // Maybe it's a file, not a directory — read and return view
            if let Some(content) = cache.read_file(&mount_id, sub_path) {
                // Drop lock before calling git_view_file_content (which acquires it)
                drop(cache);
                return git_view_file_content(&mount_id, sub_path, &content, &base_path);
            }
        }

        let mount_info = cache.mounts.get(&mount_id);
        let mount_name = mount_info
            .map(|m| m.name.clone())
            .unwrap_or_else(|| mount_id.clone());
        let commit_short = mount_info
            .and_then(|m| m.head_commit.as_deref())
            .map(|c| c[..7.min(c.len())].to_string())
            .unwrap_or_else(|| "n/a".to_string());
        let branch = mount_info
            .and_then(|m| m.branch.clone())
            .unwrap_or_else(|| "detached".to_string());

        (entries, mount_name, commit_short, branch)
    };

    // Breadcrumb
    let mut breadcrumb = format!(
        r#"<a href="{}/git-browse">📁 Mounts</a> / <a href="{}/git-browse/{}">{}</a>"#,
        base_path, base_path, mount_id, mount_name
    );
    if !sub_path.is_empty() {
        let parts: Vec<&str> = sub_path.split('/').filter(|s| !s.is_empty()).collect();
        let mut accumulated = String::new();
        for (i, part) in parts.iter().enumerate() {
            if i > 0 {
                accumulated.push('/');
            }
            accumulated.push_str(part);
            if i < parts.len() - 1 {
                breadcrumb.push_str(&format!(
                    r#" / <a href="{}/git-browse/{}?path={}">{}</a>"#,
                    base_path, mount_id, accumulated, part
                ));
            } else {
                breadcrumb.push_str(&format!(" / {}", part));
            }
        }
    }

    let items: String = entries.iter().map(|e| {
        let icon = if e.is_submodule { "🔗" } else if e.is_dir { "📁" } else { "📄" };
        let link = if e.is_dir {
            format!(r#"<a href="{}/git-browse/{}?path={}">{} {}</a>"#, base_path, mount_id, e.rel_path, icon, e.name)
        } else {
            format!(r#"<a href="{}/git-view/{}/{}">{} {}</a>"#, base_path, mount_id, e.rel_path, icon, e.name)
        };
        let size_str = if e.size > 0 {
            if e.size > 1_000_000 { format!("{:.1}M", e.size as f64 / 1_000_000.0) }
            else if e.size > 1_000 { format!("{:.0}K", e.size as f64 / 1_000.0) }
            else { format!("{}B", e.size) }
        } else { String::new() };
        let badge = if e.is_submodule { r#"<span style="color:#f90;font-size:11px">submodule</span>"# } else { "" };
        format!(r#"<div style="border-bottom:1px solid #222;padding:6px 0">{} {} <span style="color:#666;font-size:12px">{}</span></div>"#, link, badge, size_str)
    }).collect();

    let html = format!(
        r##"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>{} — Git Browse</title>
<style>
body{{font-family:monospace;max-width:900px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
h1{{color:#0f0;border-bottom:1px solid #333}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
.breadcrumb{{color:#888;font-size:13px;margin-bottom:10px}}
</style>
</head><body>
<div class="nav"><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/git-browse">📁 Git</a></div>
<div class="breadcrumb">{}</div>
<h1>📁 {}</h1>
<p style="color:#666;font-size:12px">🔀 {} · {}</p>
<div style="margin-top:15px">{}</div>
</body></html>"##,
        mount_name,
        base_path,
        base_path,
        base_path,
        breadcrumb,
        mount_name,
        branch,
        commit_short,
        items
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// GET /git-view/{mount_id}/{path:.*} — view a file from a git mount
pub async fn git_view_file(path: web::Path<(String, String)>) -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let (mount_id, sub_path) = path.into_inner();

    let content = {
        let mut cache = crate::git_mount::get_cache();
        match cache.read_file(&mount_id, &sub_path) {
            Some(c) => c,
            None => return Ok(HttpResponse::NotFound().body("File not found")),
        }
    };

    git_view_file_content(&mount_id, &sub_path, &content, &base_path)
}

/// Render a file view page (shared between browse and direct view).
fn git_view_file_content(
    mount_id: &str,
    sub_path: &str,
    content: &str,
    base_path: &str,
) -> Result<HttpResponse> {
    let mount_name = {
        let cache = crate::git_mount::get_cache();
        cache
            .mounts
            .get(mount_id)
            .map(|m| m.name.clone())
            .unwrap_or_else(|| mount_id.to_string())
    };

    let ext = Path::new(sub_path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("txt")
        .to_string();

    let fname = Path::new(sub_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file")
        .to_string();

    let commit_short = {
        let cache = crate::git_mount::get_cache();
        cache
            .get_file_entry(mount_id, sub_path)
            .and_then(|f| {
                f.head_commit
                    .as_deref()
                    .map(|c| c[..7.min(c.len())].to_string())
            })
            .unwrap_or_else(|| "n/a".to_string())
    };

    // Breadcrumb
    let parts: Vec<&str> = sub_path.split('/').filter(|s| !s.is_empty()).collect();
    let mut breadcrumb = format!(
        r#"<a href="{}/git-browse">📁 Mounts</a> / <a href="{}/git-browse/{}">{}</a>"#,
        base_path, base_path, mount_id, mount_name
    );
    let mut accumulated = String::new();
    for (i, part) in parts.iter().enumerate() {
        if i > 0 {
            accumulated.push('/');
        }
        accumulated.push_str(part);
        if i < parts.len() - 1 {
            breadcrumb.push_str(&format!(
                r#" / <a href="{}/git-browse/{}?path={}">{}</a>"#,
                base_path, mount_id, accumulated, part
            ));
        } else {
            breadcrumb.push_str(&format!(" / {}", part));
        }
    }

    // Syntax class for common languages
    let lang_class = match ext.as_str() {
        "rs" => "language-rust",
        "py" => "language-python",
        "js" | "ts" => "language-javascript",
        "go" => "language-go",
        "java" => "language-java",
        "c" | "h" => "language-c",
        "cpp" | "hpp" => "language-cpp",
        "html" => "language-html",
        "css" => "language-css",
        "json" => "language-json",
        "toml" | "nix" => "language-toml",
        "yaml" | "yml" => "language-yaml",
        "md" => "language-markdown",
        "sh" | "bash" => "language-bash",
        "org" => "language-org",
        "lean" => "language-lean",
        _ => "",
    };

    // Escape HTML in content
    let escaped = html_escape(content);

    let html = format!(
        r##"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>{} — Git View</title>
<style>
body{{font-family:monospace;max-width:1100px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
h1{{color:#0f0;border-bottom:1px solid #333}}
pre{{background:#111;padding:20px;border:1px solid #333;overflow-x:auto;white-space:pre;tab-size:4}}
.nav{{background:#111;padding:10px;margin-bottom:20px;border:1px solid #0f0}}
.breadcrumb{{color:#888;font-size:13px;margin-bottom:10px}}
.meta{{color:#888;font-size:0.9em}}
.line-numbers{{color:#555;text-align:right;padding-right:10px;border-right:1px solid #333;user-select:none}}
code{{font-family:monospace;font-size:13px}}
</style>
</head><body>
<div class="nav"><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/git-browse">📁 Git</a></div>
<div class="breadcrumb">{}</div>
<h1>📄 {}</h1>
<p class="meta">📁 {} · {} · 🔀 {}</p>
<hr>
<pre><code class="{}">{}</code></pre>
</body></html>"##,
        fname,
        base_path,
        base_path,
        base_path,
        breadcrumb,
        fname,
        sub_path,
        ext,
        commit_short,
        lang_class,
        escaped
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// GET /api/git-search?q=... — search git-mounted files
pub async fn api_git_search(req: HttpRequest) -> Result<HttpResponse> {
    let uri = req.uri().to_string();
    let query = match parse_query_param(&uri, "q") {
        Some(q) if !q.is_empty() => q,
        _ => {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Missing query parameter: q",
                "usage": "curl 'http://localhost:8090/api/git-search?q=cbor'"
            })))
        }
    };

    let limit: usize = parse_query_param(&uri, "limit")
        .and_then(|s| s.parse().ok())
        .unwrap_or(20);

    let search_content = parse_query_param(&uri, "content")
        .map(|s| s != "0")
        .unwrap_or(true);

    let mut cache = crate::git_mount::get_cache();

    // Filename/path matches
    let file_results: Vec<serde_json::Value> = cache
        .search_names(&query, limit)
        .iter()
        .map(|e| {
            serde_json::json!({
                "type": "file",
                "mount_id": e.mount_id,
                "path": e.rel_path,
                "name": e.name,
                "ext": e.ext,
                "size": e.size,
                "url": format!("/git-view/{}/{}", e.mount_id, e.rel_path),
                "is_submodule": e.is_submodule,
                "head_commit": e.head_commit,
            })
        })
        .collect();

    let mut results = file_results;

    // Content matches
    if search_content && results.len() < limit {
        let remaining = limit - results.len();
        let content_results = cache.search_content(&query, remaining);
        for (entry, excerpt) in content_results {
            results.push(serde_json::json!({
                "type": "content",
                "mount_id": entry.mount_id,
                "path": entry.rel_path,
                "name": entry.name,
                "ext": entry.ext,
                "size": entry.size,
                "url": format!("/git-view/{}/{}", entry.mount_id, entry.rel_path),
                "excerpt": excerpt,
                "is_submodule": entry.is_submodule,
                "head_commit": entry.head_commit,
            }));
        }
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "query": query,
        "total": results.len(),
        "results": results,
    })))
}

/// GET /api/git-index — return cache info
pub async fn api_git_index() -> Result<HttpResponse> {
    let mut cache = crate::git_mount::get_cache();
    let mounts: Vec<serde_json::Value> = cache
        .mounts
        .values()
        .map(|m| {
            serde_json::json!({
                "id": m.id,
                "root": m.root,
                "name": m.name,
                "head_commit": m.head_commit,
                "branch": m.branch,
            })
        })
        .collect();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "mounts": mounts,
        "stats": cache.stats(),
    })))
}

/// POST /api/git-reindex — flush cache to disk
pub async fn api_git_reindex() -> Result<HttpResponse> {
    let mut cache = crate::git_mount::get_cache();
    cache.flush_to_disk();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "stats": cache.stats(),
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn similarity_score_prefers_shared_keywords_and_content_terms() {
        let source_terms = vec!["rust".to_string(), "nix".to_string(), "flake".to_string()];
        let source_keywords = vec!["rust".to_string(), "nix".to_string()];
        let source_ngrams = vec![("nix rust flake".to_string(), 2)];

        let shared = PasteIndex {
            id: "shared".to_string(),
            title: "Rust Nix Flake".to_string(),
            description: Some("nix rust flake notes".to_string()),
            keywords: vec!["rust".to_string(), "nix".to_string()],
            ngrams: vec![("nix rust flake".to_string(), 2)],
            timestamp: "2".to_string(),
            ..PasteIndex::default()
        };
        let unrelated = PasteIndex {
            id: "unrelated".to_string(),
            title: "Unrelated Paste".to_string(),
            description: Some("different topic".to_string()),
            keywords: vec!["other".to_string()],
            ngrams: vec![("other topic".to_string(), 2)],
            timestamp: "1".to_string(),
            ..PasteIndex::default()
        };

        let shared_score = similarity_score(
            &source_terms,
            &source_keywords,
            &source_ngrams,
            &shared,
            Some("this paste also discusses nix rust flake"),
        );
        let unrelated_score = similarity_score(
            &source_terms,
            &source_keywords,
            &source_ngrams,
            &unrelated,
            Some("this paste discusses unrelated topics"),
        );

        assert!(shared_score > unrelated_score);
    }

    #[test]
    fn split_export_text_respects_max_bytes_on_line_boundaries() {
        let content = "alpha\nbeta\ngamma\n";
        let parts = split_export_text("abc/123", content, 8);

        assert_eq!(parts.len(), 3);
        assert_eq!(parts[0].0, "thread-abc-123-part-001.txt");
        assert_eq!(parts[0].1, "alpha\n");
        assert_eq!(parts[1].1, "beta\n");
        assert_eq!(parts[2].1, "gamma\n");
    }
}
