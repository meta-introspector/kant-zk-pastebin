// Handlers - Request handlers for kant-pastebin microservice
use crate::model::{Paste, PasteIndex, Response};
use crate::{ipfs, plugin, storage, tagging, view};
use actix_web::{web, HttpResponse, Result};
use chrono::Utc;
use sha2::{Digest, Sha256};
use std::{env, fs};

struct AccessCommands {
    ipfs: String,
    raw: String,
    reply: String,
    cat: String,
    data_url: String,
}

fn normalized_base_url(req: &actix_web::HttpRequest, base_path: &str) -> String {
    let normalized_base_path = if base_path.is_empty() {
        String::new()
    } else if base_path.starts_with('/') {
        base_path.to_string()
    } else {
        format!("/{}", base_path)
    };

    match env::var("BASE_URL") {
        Ok(base_url) if !base_url.trim().is_empty() => {
            let base_url = base_url.trim_end_matches('/');
            if normalized_base_path.is_empty() || base_url.ends_with(&normalized_base_path) {
                base_url.to_string()
            } else {
                format!("{}{}", base_url, normalized_base_path)
            }
        }
        _ => {
            let connection = req.connection_info();
            format!(
                "{}://{}{}",
                connection.scheme(),
                connection.host(),
                normalized_base_path
            )
        }
    }
}

fn access_commands(base_url: &str, id: &str, ipfs_cid: Option<&str>, uucp_path: &str, content: &str) -> AccessCommands {
    let ipfs = if let Some(cid) = ipfs_cid {
        format!("curl {}/ipfs/{}", base_url, cid)
    } else {
        "# No IPFS CID available".to_string()
    };

    let cat = if !uucp_path.is_empty() {
        format!("cat {}", uucp_path)
    } else {
        format!("cat /var/spool/uucp/pastebin/{}.txt", id)
    };

    // Compressed base64 data URL for inline copy
    let data_url = {
        use std::io::Write;
        let mut encoder = flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::best());
        let _ = encoder.write_all(content.as_bytes());
        let compressed = encoder.finish().unwrap_or_default();
        let b64 = base64::Engine::encode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, &compressed);
        format!("{}/paste/{}#z={}", base_url, id, b64)
    };

    AccessCommands {
        ipfs,
        raw: format!("curl {}/raw/{}", base_url, id),
        reply: format!(
            "curl -X POST {}/paste -H 'Content-Type: application/json' -d '{{\"content\":\"...\",\"reply_to\":\"{}\"}}'",
            base_url, id
        ),
        cat,
        data_url,
    }
}

/// GET / - Home page
pub async fn index(
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let reply_to = query.get("reply_to").map(|s| s.as_str()).unwrap_or("");
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());

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
<a href="{}/">🏠 Home</a>
<a href="{}/browse">📚 Browse</a>
<a href="{}/gallery">🖼️ Gallery</a>
<a href="/splitter/">✂️ Splitter</a>
<a href="{}/openapi.json">📖 API</a>
</div>
<h1>📋 Kant Pastebin</h1>
<p>UUCP + zkTLS + IPFS</p>
<form id="form">
<input type="text" id="title" placeholder="Title" value=""><br><br>
<textarea id="content" placeholder="Paste content here..."></textarea><br><br>
<input type="file" id="file" accept="image/*,.html,.json,.svg"><br><br>
<input type="text" id="keywords" placeholder="Keywords (comma separated)"><br><br>
<input type="hidden" id="reply_to" value="{}">
<button type="submit">📤 Share</button>
<button type="button" onclick="preview()">👁️ Preview</button>
<button type="button" onclick="sendToSplitter()">✂️ Split</button>
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

function preview() {{
  const div = document.createElement('div');
  div.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:#0a0a0a;z-index:1000;overflow:auto;padding:20px;box-sizing:border-box';
  div.innerHTML = '<button onclick=\"this.parentElement.remove()\" style=\"position:sticky;top:10px;float:right\">✕ Close</button><pre style=\"white-space:pre-wrap;word-wrap:break-word\">' + content.value + '</pre>';
  document.body.appendChild(div);
}}

function sendToSplitter() {{
  localStorage.setItem('splitter-text', content.value);
  window.open('/splitter/', '_blank');
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
      fd.append('file', fileInput.files[0]);
      fd.append('title', document.getElementById('title').value || fileInput.files[0].name);
      res = await fetch(basePath + '/upload', {{ method: 'POST', body: fd }});
    }} else {{
      const data = {{
        content: content.value,
        title: document.getElementById('title').value || undefined,
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
</body></html>"#,
        base_path,
        base_path,
        base_path,
        base_path,
        reply_to,
        base_path,
        base_path,
        base_path,
        base_path
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
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
    let title_owned = paste.title.clone().unwrap_or_else(|| {
        html_title.unwrap_or_else(|| {
            if !auto_tags.is_empty() {
                auto_desc
            } else {
                "untitled".to_string()
            }
        })
    });
    let title = title_owned.as_str();
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
    let section = crate::sheaf::Section::new(content.as_bytes(), crate::sheaf::Encoding::Raw);
    let paste_content = format!("--- {} ---\nTitle: {}\nKeywords: {}\nCID: {}\nWitness: {}\nIPFS: {}\nDASL: {}\nReply-To: {}\n{}\n\n{}\n\n{}\n",
        id, title, keywords.join(", "), local_cid, witness, ipfs_cid.as_deref().unwrap_or(""), dasl_cid, reply_to_str,
        crate::sheaf::sheaf_header(&section),
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
        description: Some(tagging::auto_describe(content)),
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

/// POST /upload - Upload file (multipart)
pub async fn upload_file(mut payload: actix_multipart::Multipart) -> Result<HttpResponse> {
    use futures_util::StreamExt as _;

    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let mut file_data: Vec<u8> = Vec::new();
    let mut orig_name = String::new();
    let mut title = String::new();

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
            "title" => {
                title = String::from_utf8_lossy(&buf).to_string();
            }
            _ => {}
        }
    }

    if file_data.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "no file"})));
    }

    let ext = orig_name.rsplit('.').next().unwrap_or("bin");
    let mime = mime_guess::from_ext(ext).first_or_octet_stream();
    if title.is_empty() {
        title = orig_name.clone();
    }
    let slug = tagging::slugify(&title);

    let mut hasher = Sha256::new();
    hasher.update(&file_data);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    let ipfs_cid = ipfs::ipfs_add_bytes(&file_data);

    let filename = format!("{}_{}.{}", ts, slug, ext);
    let id = filename
        .rsplit_once('.')
        .map(|(s, _)| s)
        .unwrap_or(&filename)
        .to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);

    fs::write(&uucp, &file_data).ok();

    // Write metadata sidecar
    let meta = format!(
        "--- {} ---\nTitle: {}\nMime: {}\nCID: {}\nWitness: {}\nIPFS: {}\nSize: {}\n",
        id,
        title,
        mime,
        local_cid,
        witness,
        ipfs_cid.as_deref().unwrap_or(""),
        file_data.len()
    );
    fs::write(format!("{}.meta", uucp), &meta).ok();

    // CID dedup file
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    fs::write(&cid_file, &id).ok();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id,
        "filename": filename,
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
            let mime = mime_guess::from_ext(&ext).first_or_octet_stream();
            Ok(HttpResponse::Ok().content_type(mime.to_string()).body(data))
        }
        None => Ok(HttpResponse::NotFound().body("File not found")),
    }
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
pub async fn get_paste(
    path: web::Path<String>,
    req: actix_web::HttpRequest,
) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let base_url = normalized_base_url(&req, &base_path);

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
            let uucp_path = format!("{}/{}.txt", uucp_dir, id);
            let commands = access_commands(&base_url, &id, ipfs_cid, &uucp_path, body);

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

            let html = format!(
                r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<title>{}</title>
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}
.nav{{background:#111;padding:10px;margin:10px 0;border:1px solid #0f0}}
pre{{background:#111;padding:20px;border:1px solid #0f0;overflow:auto;max-height:600px;word-wrap:break-word;white-space:pre-wrap}}
.reply-btn{{background:#0f0;color:#000;border:none;padding:5px 10px;cursor:pointer;margin:5px;display:inline-block}}
.cmd{{background:#111;padding:10px;margin:5px 0;border-left:3px solid #ff0;cursor:pointer;font-size:12px}}
.cmd:hover{{background:#222}}
.qr-modal{{position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#fff;padding:20px;border:3px solid #0f0;z-index:1000;display:none}}
.qr-modal h3{{color:#000}}
.preview-modal{{position:fixed;top:0;left:0;width:100%;height:100%;background:#fff;z-index:2000;overflow:auto;display:none}}
.preview-modal iframe{{width:100%;height:100%;border:none}}
</style>
</head><body>
<div class="nav"><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/raw/{}">📄 Raw</a> | {} {}</div>
<h1>{}</h1>
<a class="reply-btn" href="{}/?reply_to={}">💬 Reply</a>
<button class="reply-btn" onclick="navigator.clipboard.writeText(document.querySelector('pre').textContent);this.textContent='✅ Copied'">📋 Copy</button>
<button class="reply-btn" onclick="navigator.share({{title:'{}',text:document.querySelector('pre').textContent,url:window.location.href}})">🔗 Share</button>
<button class="reply-btn" onclick="showQR()">📱 QR Code</button>
<button class="reply-btn" onclick="shareRDFa()">🔗 RDFa URL</button>
<button class="reply-btn" onclick="showPreview()">👁️ Preview</button>
<button class="reply-btn" onclick="localStorage.setItem('splitter-text',document.querySelector('pre').textContent);window.open('/splitter/','_blank')">✂️ Split</button>

<h3>Access Commands:</h3>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'">$ {}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'">$ {}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'">$ {}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'">$ {}</div>
<div class="cmd" onclick="navigator.clipboard.writeText('{}');this.style.borderColor='#0f0'" title="Compressed inline URL">🔗 {}</div>

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
</script>
<script src="/static/a11y.js"></script>
</body></html>"#,
                title,
                base_path,
                base_path,
                base_path,
                id,
                prev_link,
                next_link,
                title,
                base_path,
                id,
                title,
                commands.ipfs,
                commands.ipfs,
                commands.raw,
                commands.raw,
                commands.reply,
                commands.reply,
                commands.cat,
                commands.cat,
                commands.data_url,
                commands.data_url,
                body,
                related_html,
                title,
                ipfs_cid.unwrap_or(""),
                title
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
        None => Ok(HttpResponse::NotFound().body("Paste not found")),
    }
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
    let content = storage::load_content(&id).unwrap_or_else(|| "Paste not found".to_string());
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

/// GET /thread/{id} - Get paste and all replies
pub async fn get_thread(path: web::Path<String>) -> Result<HttpResponse> {
    let parent_id = path.into_inner();
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());

    let mut thread = Vec::new();

    if let Ok(entries) = fs::read_dir(&uucp_dir) {
        for entry in entries.flatten() {
            let fname = entry.file_name().to_string_lossy().to_string();
            if !fname.ends_with(".txt") {
                continue;
            }
            if let Ok(content) = fs::read_to_string(entry.path()) {
                let lines: Vec<&str> = content.lines().collect();
                if lines.is_empty() {
                    continue;
                }

                // Parse header
                let file_id = fname.trim_end_matches(".txt");
                let mut title = String::new();
                let mut reply_to = String::new();
                let mut body_start = 0;

                for (i, line) in lines.iter().enumerate() {
                    if line.is_empty() && i > 0 {
                        body_start = i + 1;
                        break;
                    }
                    if let Some(t) = line.strip_prefix("Title: ") {
                        title = t.to_string();
                    }
                    if let Some(r) = line.strip_prefix("Reply-To: ") {
                        reply_to = r.to_string();
                    }
                }

                // Include if this IS the parent or replies TO the parent
                if file_id == parent_id || reply_to == parent_id {
                    let body = if body_start < lines.len() {
                        lines[body_start..].join("\n")
                    } else {
                        String::new()
                    };
                    thread.push(serde_json::json!({
                        "id": file_id,
                        "title": title,
                        "reply_to": reply_to,
                        "content": body,
                    }));
                }
            }
        }
    }

    // Sort: parent first, then replies by id (chronological)
    thread.sort_by(|a, b| {
        let a_id = a["id"].as_str().unwrap_or("");
        let b_id = b["id"].as_str().unwrap_or("");
        if a_id == parent_id {
            std::cmp::Ordering::Less
        } else if b_id == parent_id {
            std::cmp::Ordering::Greater
        } else {
            a_id.cmp(b_id)
        }
    });

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "thread_id": parent_id,
        "count": thread.len(),
        "posts": thread,
    })))
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
pub async fn browse(
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "".to_string());
    let index_file = format!("{}/index.jsonl", uucp_dir);

    let search = query.get("q").map(|s| s.to_lowercase());

    let entries: Vec<PasteIndex> = fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .filter(|entry| {
            if let Some(ref q) = search {
                entry.title.to_lowercase().contains(q)
                    || entry.keywords.iter().any(|k| k.to_lowercase().contains(q))
            } else {
                true
            }
        })
        .collect();

    let search_box = if let Some(q) = search {
        format!(
            r#"<form method="get"><input type="text" name="q" value="{}" placeholder="Search..." style="padding:5px;width:300px"><button type="submit">🔍</button></form>"#,
            q
        )
    } else {
        r#"<form method="get"><input type="text" name="q" placeholder="Search..." style="padding:5px;width:300px"><button type="submit">🔍</button></form>"#.to_string()
    };

    let items: String = entries.iter().rev().take(50).map(|e| {
        let display_title = if e.title == "untitled" || e.title.is_empty() {
            e.description.as_deref().unwrap_or("untitled")
        } else {
            &e.title
        };
        let tags = if !e.keywords.is_empty() {
            format!(" <span style=\"color:#666;font-size:11px\">[{}]</span>", e.keywords.join(", "))
        } else {
            String::new()
        };
        format!(r#"<div style="border-bottom:1px solid #333;padding:10px"><a href="{}/paste/{}">{}</a>{} <span style="color:#666">{}</span></div>"#, 
            base_path, e.id, display_title, tags, e.timestamp)
    }).collect();

    let html = format!(
        r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Browse Pastes</title>
<style>body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
a{{color:#0ff;text-decoration:none}}</style>
</head><body>
<div><a href="{}/">🏠 Home</a></div>
<h1>Browse Pastes</h1>
{}
<div style="margin-top:20px">{}</div>
</body></html>"#,
        base_path, search_box, items
    );

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(html))
}

/// GET /ipfs/{cid} - Proxy IPFS content
pub async fn ipfs_proxy(path: web::Path<String>) -> Result<HttpResponse> {
    let cid = path.into_inner();

    // Try ipfs cat CLI (handles both CIDv0 Qm... and CIDv1)
    if let Ok(output) = std::process::Command::new("ipfs")
        .args(["cat", &cid])
        .output()
    {
        if output.status.success() && !output.stdout.is_empty() {
            let data = output.stdout;
            let ct = match &data[..4.min(data.len())] {
                [0x89, 0x50, 0x4E, 0x47] => "image/png",
                [0xFF, 0xD8, ..] => "image/jpeg",
                [0x3C, ..] => "text/html; charset=utf-8",
                [0x7B, ..] => "application/json",
                _ if data.starts_with(b"<!") || data.starts_with(b"<html") => {
                    "text/html; charset=utf-8"
                }
                _ => "application/octet-stream",
            };
            return Ok(HttpResponse::Ok().content_type(ct).body(data));
        }
    }

    // Fallback: try local flatfs
    if let Some(block) = ipfs::ipfs_cat(&cid) {
        return Ok(HttpResponse::Ok()
            .content_type("application/octet-stream")
            .body(block));
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

/// Enrich a Wikidata QID via the enrich-qid.sh pipeline
async fn enrich_qid(qid: &str) -> Result<HttpResponse> {
    let pipeline = env::var("ENRICH_PIPELINE").unwrap_or_else(|_| {
        "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh".to_string()
    });
    let nft_dir = env::var("NFT_DIR")
        .unwrap_or_else(|_| "/mnt/data1/time-2026/03-march/13/nft_enriched".to_string());

    log::info!("🔮 QID detected: {} — running enrichment pipeline", qid);

    let output = std::process::Command::new("bash")
        .args([&pipeline, qid])
        .output();

    match output {
        Ok(out) if out.status.success() => {
            // Read metadata from enriched dir
            let meta_path = format!("{}/{}/metadata.rdfa", nft_dir, qid);
            let mut meta = std::collections::HashMap::new();
            if let Ok(content) = fs::read_to_string(&meta_path) {
                for line in content.lines() {
                    if let Some((k, v)) = line.split_once('=') {
                        meta.insert(k.to_string(), v.to_string());
                    }
                }
            }

            let name = meta.get("name").cloned().unwrap_or_else(|| qid.to_string());
            let html_cid = meta.get("ipfs_html_cid").cloned().unwrap_or_default();
            let nft_cid = meta.get("ipfs_nft_cid").cloned().unwrap_or_default();
            let dir_cid = meta.get("ipfs_dir_cid").cloned().unwrap_or_default();
            let witness = meta.get("witness").cloned().unwrap_or_default();

            Ok(HttpResponse::Ok().json(serde_json::json!({
                "id": qid,
                "name": name,
                "qid": qid,
                "enriched": true,
                "html_cid": html_cid,
                "nft_cid": nft_cid,
                "dir_cid": dir_cid,
                "witness": witness,
                "url": format!("/ipfs/{}", html_cid),
                "nft_url": format!("/ipfs/{}", nft_cid),
                "gallery": "/gallery",
            })))
        }
        Ok(out) => {
            let stderr = String::from_utf8_lossy(&out.stderr);
            log::error!("Enrichment failed for {}: {}", qid, stderr);
            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("Enrichment failed for {}", qid),
                "detail": stderr.to_string(),
            })))
        }
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("Pipeline not found: {}", e),
        }))),
    }
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
    req: actix_web::HttpRequest,
    registry: web::Data<std::sync::Mutex<plugin::PluginRegistry>>,
    body: web::Json<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let (plugin_name, paste_id) = path.into_inner();
    let base_path = env::var("BASE_PATH").unwrap_or_default();
    let base_url = normalized_base_url(&req, &base_path);

    // Load paste content
    let content = storage::load_content(&paste_id).unwrap_or_default();
    let url = format!("{}/paste/{}", base_url, paste_id);

    let input = plugin::PluginInput {
        id: paste_id.clone(),
        content: content.into_bytes(),
        mime: "text/plain".into(),
        url,
        extra: body.into_inner(),
    };

    let reg = registry.lock().unwrap();
    match reg.execute(&plugin_name, &input) {
        Ok(result) => Ok(HttpResponse::Ok().json(result)),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({"error": e}))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{body, http::StatusCode, test};
    use std::path::{Path, PathBuf};
    use std::sync::{Mutex, OnceLock};
    use std::time::{SystemTime, UNIX_EPOCH};

    struct EnvVarGuard {
        name: &'static str,
        original: Option<String>,
    }

    impl EnvVarGuard {
        fn set(name: &'static str, value: Option<&str>) -> Self {
            let original = env::var(name).ok();
            match value {
                Some(value) => env::set_var(name, value),
                None => env::remove_var(name),
            }
            Self { name, original }
        }
    }

    impl Drop for EnvVarGuard {
        fn drop(&mut self) {
            match &self.original {
                Some(value) => env::set_var(self.name, value),
                None => env::remove_var(self.name),
            }
        }
    }

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn temp_spool() -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let spool = env::temp_dir().join(format!(
            "kant-pastebin-handlers-{}-{}",
            std::process::id(),
            unique
        ));
        fs::create_dir_all(&spool).unwrap();
        spool
    }

    fn write_text_paste_fixture(spool: &Path, id: &str, ipfs_cid: &str) {
        let entry = PasteIndex {
            id: id.to_string(),
            title: "Fixture".to_string(),
            description: Some("Fixture description".to_string()),
            keywords: vec!["fixture".to_string()],
            cid: "bafkfixture".to_string(),
            witness: "deadbeef".repeat(8),
            timestamp: "2026-03-17T21:18:12Z".to_string(),
            filename: format!("{}.txt", id),
            ngrams: vec![],
            ipfs_cid: Some(ipfs_cid.to_string()),
            reply_to: None,
            size: 2,
            uucp_path: spool.join(format!("{}.txt", id)).display().to_string(),
        };

        fs::write(
            spool.join(format!("{}.txt", id)),
            format!("Title: Fixture\nIPFS: {}\n\nhi", ipfs_cid),
        )
        .unwrap();
        fs::write(
            spool.join("index.jsonl"),
            format!("{}\n", serde_json::to_string(&entry).unwrap()),
        )
        .unwrap();
    }

    #[actix_web::test]
    async fn get_paste_uses_forwarded_origin_for_access_commands() {
        let _guard = env_lock().lock().unwrap();
        let spool = temp_spool();
        let paste_id = "20260317_211812_untitled";
        let ipfs_cid = "QmdckCoPuhEtiNzREtqpYn8dBgY8ifcG82Q4eyEdGCLEiu";
        let _spool_env = EnvVarGuard::set("UUCP_SPOOL", Some(spool.to_str().unwrap()));
        let _base_url_env = EnvVarGuard::set("BASE_URL", None);
        let _base_path_env = EnvVarGuard::set("BASE_PATH", None);

        write_text_paste_fixture(&spool, paste_id, ipfs_cid);

        let req = test::TestRequest::default()
            .insert_header(("Host", "pastebin.xware.online"))
            .insert_header(("X-Forwarded-Host", "pastebin.xware.online"))
            .insert_header(("X-Forwarded-Proto", "https"))
            .to_http_request();

        let response = get_paste(web::Path::from(paste_id.to_string()), req)
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let html = String::from_utf8(body::to_bytes(response.into_body()).await.unwrap().to_vec())
            .unwrap();

        assert!(html.contains(&format!(
            "$ curl https://pastebin.xware.online/ipfs/{}",
            ipfs_cid
        )));
        assert!(html.contains(&format!(
            "$ curl https://pastebin.xware.online/raw/{}",
            paste_id
        )));
        assert!(html.contains("curl -X POST https://pastebin.xware.online/paste"));
        assert!(!html.contains("localhost:8090"));
        assert!(!html.contains("/data/pastebin"));
        assert!(!html.contains("$ ipfs cat "));

        fs::remove_dir_all(spool).unwrap();
    }

    #[actix_web::test]
    async fn get_paste_prefers_base_url_override() {
        let _guard = env_lock().lock().unwrap();
        let spool = temp_spool();
        let paste_id = "20260317_211812_untitled";
        let ipfs_cid = "QmdckCoPuhEtiNzREtqpYn8dBgY8ifcG82Q4eyEdGCLEiu";
        let _spool_env = EnvVarGuard::set("UUCP_SPOOL", Some(spool.to_str().unwrap()));
        let _base_url_env = EnvVarGuard::set("BASE_URL", Some("https://public.example"));
        let _base_path_env = EnvVarGuard::set("BASE_PATH", Some("/pastebin"));

        write_text_paste_fixture(&spool, paste_id, ipfs_cid);

        let req = test::TestRequest::default()
            .insert_header(("Host", "internal.local"))
            .insert_header(("X-Forwarded-Host", "internal.local"))
            .insert_header(("X-Forwarded-Proto", "http"))
            .to_http_request();

        let response = get_paste(web::Path::from(paste_id.to_string()), req)
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let html = String::from_utf8(body::to_bytes(response.into_body()).await.unwrap().to_vec())
            .unwrap();

        assert!(html.contains(&format!(
            "$ curl https://public.example/pastebin/raw/{}",
            paste_id
        )));
        assert!(html.contains(&format!(
            "$ curl https://public.example/pastebin/ipfs/{}",
            ipfs_cid
        )));
        assert!(!html.contains("internal.local"));

        fs::remove_dir_all(spool).unwrap();
    }
}
