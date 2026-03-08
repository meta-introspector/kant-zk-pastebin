use actix_web::{web, App, HttpResponse, HttpServer};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::fs;
use std::env;
use std::process::Command;
use std::collections::HashMap;
use chrono::Utc;

#[derive(Deserialize)]
struct Paste {
    content: Option<String>,
    cid: Option<String>,
    title: Option<String>,
    keywords: Option<Vec<String>>,
}

#[derive(Serialize)]
struct Response {
    id: String,
    cid: String,
    ipfs_cid: Option<String>,
    witness: String,
    url: String,
}

#[derive(Serialize)]
struct PasteIndex {
    id: String,
    title: String,
    keywords: Vec<String>,
    cid: String,
    witness: String,
    timestamp: String,
    filename: String,
    ngrams: Vec<(String, usize)>,
}

fn extract_ngrams(text: &str, n: usize, top: usize) -> Vec<(String, usize)> {
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

fn slugify(s: &str) -> String {
    s.chars()
        .filter_map(|c| if c.is_alphanumeric() || c == '-' { Some(c.to_ascii_lowercase()) } else if c.is_whitespace() { Some('-') } else { None })
        .collect::<String>()
        .split('-')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

fn ipfs_add(content: &str) -> Option<String> {
    use std::io::Write;
    
    let mut child = Command::new("ipfs")
        .args(&["add", "-Q"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .ok()?;
    
    child.stdin.as_mut()?.write_all(content.as_bytes()).ok()?;
    let output = child.wait_with_output().ok()?;
    
    String::from_utf8(output.stdout).ok().map(|s| s.trim().to_string())
}

fn ipfs_cat(cid: &str) -> Option<String> {
    let output = Command::new("ipfs")
        .args(&["cat", cid])
        .stdout(std::process::Stdio::piped())
        .spawn()
        .ok()?
        .wait_with_output()
        .ok()?;
    
    String::from_utf8(output.stdout).ok()
}

async fn paste(data: web::Json<Paste>) -> HttpResponse {
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let title = data.title.as_deref().unwrap_or("untitled");
    let keywords = data.keywords.clone().unwrap_or_default();
    
    // Get content: either from CID (P2P) or direct (HTTP)
    let content = if let Some(cid) = &data.cid {
        // TRUE P2P: Fetch from IPFS network!
        match ipfs_cat(cid) {
            Some(c) => c,
            None => return HttpResponse::BadRequest().body("Failed to fetch CID from IPFS"),
        }
    } else if let Some(c) = &data.content {
        c.clone()
    } else {
        return HttpResponse::BadRequest().body("Either content or cid required");
    };
    
    // Calculate CID
    let mut hasher = Sha256::new();
    hasher.update(&content);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    
    // Check if CID exists
    if std::path::Path::new(&cid_file).exists() {
        let existing_id = fs::read_to_string(&cid_file).unwrap_or_else(|_| format!("paste_{}", ts));
        let url = format!("https://solana.solfunmeme.com/pastebin/{}", existing_id);
        return HttpResponse::Ok().json(Response { id: existing_id, cid: local_cid, ipfs_cid: None, witness, url });
    }
    
    // Push to IPFS
    let ipfs_cid = ipfs_add(&content);
    
    // Build filename
    let slug_title = slugify(title);
    let slug_keywords = keywords.iter().map(|k| slugify(k)).collect::<Vec<_>>().join("_");
    let filename = if slug_keywords.is_empty() {
        format!("{}_{}.txt", ts, slug_title)
    } else {
        format!("{}_{}_{}.txt", ts, slug_title, slug_keywords)
    };
    
    let id = filename.trim_end_matches(".txt").to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);
    
    // Save paste
    let paste_content = format!("--- {} ---\nTitle: {}\nKeywords: {}\nCID: {}\nWitness: {}\n\n{}\n",
        id, title, keywords.join(", "), local_cid, witness, content);
    fs::write(&uucp, paste_content).ok();
    fs::write(&cid_file, &id).ok();
    
    // Update index
    let ngrams = extract_ngrams(&content, 3, 10); // Top 10 trigrams
    
    let index_entry = PasteIndex {
        id: id.clone(),
        title: title.to_string(),
        keywords,
        cid: local_cid.clone(),
        witness: witness.clone(),
        timestamp: ts,
        filename: filename.clone(),
        ngrams,
    };
    
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let index_line = format!("{}\n", serde_json::to_string(&index_entry).unwrap());
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&index_file)
        .and_then(|mut f| std::io::Write::write_all(&mut f, index_line.as_bytes()))
        .ok();
    
    let url = format!("https://solana.solfunmeme.com/pastebin/{}", id);
    HttpResponse::Ok().json(Response { id, cid: local_cid, ipfs_cid, witness, url })
}

async fn index() -> HttpResponse {
    HttpResponse::Ok().content_type("text/html; charset=utf-8").body(r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Kant Pastebin - UUCP + zkTLS + IPFS</title>
<script src="https://cdn.jsdelivr.net/npm/ipfs-core@0.18.1/dist/index.min.js"></script>
<style>
body{font-family:monospace;max-width:1200px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0;display:flex;gap:20px}
.left{flex:1}
.right{width:300px;display:flex;flex-direction:column;gap:10px}
h1{color:#0ff;margin:0 0 20px 0}
input,textarea{width:100%;background:#1a1a1a;color:#0f0;border:1px solid #0f0;padding:10px;font-family:monospace;margin-bottom:10px}
textarea{min-height:400px}
button{background:#0f0;color:#000;border:none;padding:10px 20px;cursor:pointer;font-weight:bold}
button:hover{background:#0ff}
#qr{border:1px solid #0f0;padding:10px;display:none}
#qr img{width:100%;height:auto}
.meta{color:#888;font-size:12px;margin-top:10px}
.ipfs-status{color:#ff0;font-size:11px;margin-bottom:10px}
</style>
</head><body>
<div class="left">
<h1>Pastebin → UUCP + zkTLS + IPFS</h1>
<div class="ipfs-status" id="status">⏳ Starting IPFS...</div>
<input id="t" placeholder="Title" aria-label="Title">
<input id="k" placeholder="Keywords (comma-separated)" aria-label="Keywords">
<textarea id="c" placeholder="Paste content here..." aria-label="Paste content"></textarea>
<div class="meta">Ctrl+Enter to submit • CID dedup • P2P IPFS</div>
</div>
<div class="right">
<button id="b" aria-label="Submit paste">📤 Paste</button>
<a href="/browse" style="background:#0f0;color:#000;border:none;padding:10px 20px;cursor:pointer;font-weight:bold;text-decoration:none;display:block;text-align:center;margin-bottom:10px">📚 Browse</a>
<button id="load" aria-label="Load from IPFS">📥 Load CID</button>
<div id="qr"></div>
<div id="r" role="status" aria-live="polite"></div>
</div>
<script>
let ipfs;
(async()=>{
try{
ipfs=await Ipfs.create({repo:'kant-pastebin-'+Math.random()});
status.textContent='✅ IPFS Ready (P2P)';
status.style.color='#0f0';
}catch(e){
status.textContent='⚠️ IPFS unavailable (server only)';
status.style.color='#f80';
}
})();

const submit=async()=>{
const content=c.value.trim();
if(!content)return;
const keywords=k.value.split(',').map(s=>s.trim()).filter(s=>s);

// Try client IPFS first
if(ipfs){
try{
const{cid}=await ipfs.add(content);
const clientCid=cid.toString();
r.innerHTML=`<div style="color:#0ff">⏳ Sending CID to server...</div><div style="font-size:11px">Client CID: ${clientCid}</div>`;

// Send ONLY CID to server (true P2P!)
const d=await(await fetch('paste',{method:'POST',headers:{'Content-Type':'application/json'},
body:JSON.stringify({title:t.value||'untitled',keywords,cid:clientCid})})).json();

c.value='';t.value='';k.value='';
qr.style.display='block';
qr.innerHTML=`<img src="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encodeURIComponent(content)}" alt="QR Code">`;
r.innerHTML=`<div style="color:#0f0">✅ ${d.id}</div>
<div style="font-size:11px">P2P Transfer via CID!</div>
<div style="font-size:11px">Client: ${clientCid}</div>
<div style="font-size:11px">Server: ${d.ipfs_cid||'N/A'}</div>`;
return;
}catch(e){
r.innerHTML=`<div style="color:#f80">⚠️ Client IPFS failed, using HTTP...</div>`;
}
}

// Fallback: traditional HTTP
const d=await(await fetch('paste',{method:'POST',headers:{'Content-Type':'application/json'},
body:JSON.stringify({title:t.value||'untitled',content,keywords})})).json();

c.value='';t.value='';k.value='';
qr.style.display='block';
qr.innerHTML=`<img src="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encodeURIComponent(content)}" alt="QR Code">`;
r.innerHTML=`<div style="color:#0ff">✅ ${d.id}</div>
<div style="font-size:11px">Server CID: ${d.cid}</div>
<div style="font-size:11px">IPFS: ${d.ipfs_cid||'N/A'}</div>
<div style="font-size:11px">Witness: ${d.witness.slice(0,16)}...</div>`;
};

load.onclick=async()=>{
const cid=prompt('Enter IPFS CID:');
if(!cid||!ipfs)return;
try{
const chunks=[];
for await(const chunk of ipfs.cat(cid)){
chunks.push(chunk);
}
const content=new TextDecoder().decode(new Uint8Array(chunks.flat()));
c.value=content;
r.innerHTML=`<div style="color:#0f0">✅ Loaded from IPFS</div><div style="font-size:11px">${cid}</div>`;
}catch(e){
r.innerHTML=`<div style="color:#f00">❌ Failed: ${e.message}</div>`;
}
};

b.onclick=submit;
c.onkeydown=e=>{if(e.ctrlKey&&e.key==='Enter'){e.preventDefault();submit();}};
</script></body></html>"#)
}

async fn browse() -> HttpResponse {
    HttpResponse::Ok().content_type("text/html; charset=utf-8").body(r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Browse Pastes - Kant Pastebin</title>
<style>
body{font-family:monospace;max-width:1200px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}
h1{color:#0ff}
input{width:100%;background:#1a1a1a;color:#0f0;border:1px solid #0f0;padding:10px;font-family:monospace;margin-bottom:20px}
.paste{border:1px solid #333;padding:15px;margin-bottom:10px;cursor:pointer}
.paste:hover{border-color:#0f0;background:#1a1a1a}
.title{color:#0ff;font-size:14px;margin-bottom:5px}
.meta{color:#888;font-size:11px}
.keywords{color:#0f0;font-size:10px;margin-top:5px}
a{color:#0ff;text-decoration:none}
a:hover{text-decoration:underline}
</style>
</head><body>
<h1>📚 Browse Pastes</h1>
<a href="./">← Back to Pastebin</a>
<input id="search" placeholder="Search by title, keywords, or ID..." aria-label="Search">
<div id="results"></div>
<script>
let allPastes=[];
const basePath=window.location.pathname.includes('/pastebin/')?'/pastebin':'';
fetch(basePath+'/index.jsonl').then(r=>r.text()).then(text=>{
allPastes=text.split('\n').filter(Boolean).map(JSON.parse).reverse();
showResults(allPastes);
});

function showResults(pastes){
results.innerHTML=pastes.map(p=>`
<div class="paste" onclick="window.open('${basePath}/paste/${p.id}','_blank')">
<div class="title">${p.title}</div>
<div class="meta">ID: ${p.id}</div>
<div class="meta">CID: ${p.cid}</div>
<div class="meta">IPFS: <a href="https://ipfs.io/ipfs/${p.cid}" target="_blank">${p.cid}</a></div>
<div class="meta">Time: ${p.timestamp}</div>
<div class="keywords">🏷️ ${p.keywords.join(', ')}</div>
${p.ngrams?`<div class="meta" style="color:#666;font-size:10px">Top phrases: ${p.ngrams.slice(0,3).map(n=>n[0]).join(', ')}</div>`:''}
</div>`).join('');
}

search.oninput=()=>{
const q=search.value.toLowerCase().trim();
if(!q){showResults(allPastes);return;}
const filtered=allPastes.filter(p=>
p.title.toLowerCase().includes(q)||
p.keywords.some(k=>k.toLowerCase().includes(q))||
p.id.toLowerCase().includes(q)||
(p.ngrams&&p.ngrams.some(n=>n[0].includes(q)))
);
showResults(filtered);
};
</script></body></html>"#)
}

async fn get_index() -> HttpResponse {
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let index_file = format!("{}/index.jsonl", uucp_dir);
    match fs::read_to_string(&index_file) {
        Ok(content) => HttpResponse::Ok().content_type("application/x-ndjson").body(content),
        Err(_) => HttpResponse::Ok().body(""),
    }
}

async fn get_paste(path: web::Path<String>) -> HttpResponse {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    
    // Try as filename first
    let paste_file = format!("{}/{}.txt", uucp_dir, id);
    let content = if std::path::Path::new(&paste_file).exists() {
        fs::read_to_string(&paste_file).ok()
    } else {
        // Try as CID - look up in .cid file
        let cid_file = format!("{}/{}.cid", uucp_dir, id);
        if let Ok(filename) = fs::read_to_string(&cid_file) {
            let paste_file = format!("{}/{}.txt", uucp_dir, filename.trim());
            fs::read_to_string(&paste_file).ok()
        } else {
            // Try fetching from IPFS
            ipfs_cat(&id)
        }
    };
    
    match content {
        Some(content) => {
            // Extract just the content after headers
            let parts: Vec<&str> = content.split("\n\n").collect();
            let body = if parts.len() > 1 { parts[1] } else { &content };
            
            // Return HTML with proper UTF-8 encoding
            let html = format!(r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{}</title>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0;white-space:pre-wrap;word-wrap:break-word}}
a{{color:#0ff}}
</style>
</head><body>{}</body></html>"#, id, body);
            
            HttpResponse::Ok().content_type("text/html; charset=utf-8").body(html)
        }
        None => HttpResponse::NotFound().body("Paste not found"),
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    HttpServer::new(|| App::new()
        .route("/", web::get().to(index))
        .route("/browse", web::get().to(browse))
        .route("/paste", web::post().to(paste))
        .route("/index.jsonl", web::get().to(get_index))
        .route("/paste/{id}", web::get().to(get_paste)))
        .bind(&bind)?.run().await
}
