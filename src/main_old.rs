use actix_web::{web, App, HttpResponse, HttpServer};
use sha2::{Sha256, Digest};
use std::fs;
use std::env;
use std::process::Command;
use std::collections::HashMap;
use chrono::Utc;

mod model;
mod view;
mod api;
mod handlers;
mod storage;

use model::{Paste, Response, PasteIndex};

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

fn extract_github_repo(url: &str) -> Option<String> {
    // Extract github.com/owner/repo from URL
    if let Some(start) = url.find("github.com/") {
        let path = &url[start + 11..];
        let parts: Vec<&str> = path.split('/').take(2).collect();
        if parts.len() == 2 {
            return Some(format!("github.com/{}/{}", parts[0], parts[1].trim_end_matches(".git")));
        }
    }
    None
}

fn fetch_url_content(url: &str) -> Option<String> {
    Command::new("curl")
        .args(&["-sL", url])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
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
    let paste = data.into_inner();
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let title = paste.title.as_deref().unwrap_or("untitled");
    let keywords = paste.keywords.clone().unwrap_or_default();
    
    // Get content: either from CID (P2P) or direct (HTTP)
    let mut content = if let Some(cid) = &paste.cid {
        // TRUE P2P: Fetch from IPFS network!
        match ipfs_cat(cid) {
            Some(c) => c,
            None => return HttpResponse::BadRequest().body("Failed to fetch CID from IPFS"),
        }
    } else if let Some(c) = &paste.content {
        c.clone()
    } else {
        return HttpResponse::BadRequest().body("Either content or cid required");
    };
    
    // If content is a GitHub Gist URL, fetch the raw content
    if content.starts_with("https://gist.github.com/") || content.starts_with("https://gistpreview.github.io/") {
        let gist_url = content.trim();
        if let Some(gist_id) = gist_url.split('/').last().and_then(|s| s.split('?').last()) {
            let raw_url = format!("https://gist.githubusercontent.com/raw/{}", gist_id);
            if let Some(gist_content) = fetch_url_content(&raw_url) {
                content = format!("Source: {}\n\n{}", gist_url, gist_content);
            }
        }
    }
    // If content is a GitHub repo URL, clone it
    else if content.contains("github.com") && !content.contains("/gist/") && (content.starts_with("http://") || content.starts_with("https://")) {
        let url = content.trim();
        if let Some(repo_path) = extract_github_repo(url) {
            let git_dir = format!("/mnt/data1/git/{}.git", repo_path);
            if !std::path::Path::new(&git_dir).exists() {
                Command::new("git")
                    .args(&["clone", "--mirror", url, &git_dir])
                    .output()
                    .ok();
            }
            content = format!("Source: {}\nArchived: {}\n\n[Repository cloned to {}]", url, git_dir, git_dir);
        }
    }
    // If content is any other URL, fetch it
    else if content.trim().starts_with("http://") || content.trim().starts_with("https://") {
        let url = content.trim();
        if let Some(fetched) = fetch_url_content(url) {
            content = format!("Source: {}\n\n{}", url, fetched);
        }
    }
    
    // Calculate CID
    let mut hasher = Sha256::new();
    hasher.update(&content);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let base_url = env::var("BASE_URL").unwrap_or_else(|_| "https://solana.solfunmeme.com".to_string());
    let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "/pastebin".to_string());
    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);
    
    // Check if CID exists
    if std::path::Path::new(&cid_file).exists() {
        let existing_id = fs::read_to_string(&cid_file).unwrap_or_else(|_| format!("paste_{}", ts));
        let url = format!("{}{}/{}", base_url, base_path, existing_id);
        let permalink = format!("{}{}/paste/{}", base_url, base_path, local_cid);
        return HttpResponse::Ok().json(Response { id: existing_id, cid: local_cid, ipfs_cid: None, witness, url, permalink, uucp_path: "".to_string(), reply_to: paste.reply_to.clone() });
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
    
    let url = format!("{}{}/{}", base_url, base_path, id);
    let permalink = format!("{}{}/paste/{}", base_url, base_path, local_cid);
    HttpResponse::Ok().json(Response { id, cid: local_cid, ipfs_cid, witness, url, permalink, uucp_path: uucp, reply_to: paste.reply_to })
}

async fn old_index() -> HttpResponse {
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
<div class="ipfs-status" id="status">⚠️ IPFS unavailable (server only)</div>
<a href="openapi.yaml" style="color:#0ff;font-size:11px">📋 API Spec</a>
<div id="reply-info" style="display:none;background:#111;border-left:3px solid #0ff;padding:10px;margin:10px 0;color:#0ff"></div>
<input id="t" placeholder="Title" aria-label="Title">
<input id="k" placeholder="Keywords (comma-separated, or leave blank for auto)" aria-label="Keywords">
<input id="reply_to" type="hidden">
<textarea id="c" placeholder="Paste content here..." aria-label="Paste content"></textarea>
<div class="meta">Ctrl+Enter to submit • CID dedup • P2P IPFS</div>
<div id="similar" style="margin-top:10px;padding:10px;background:#111;border-left:3px solid #ff0;display:none"></div>
</div>
<div class="right">
<button id="b" aria-label="Submit paste">📤 Paste</button>
<a href="browse" style="background:#0f0;color:#000;border:none;padding:10px 20px;cursor:pointer;font-weight:bold;text-decoration:none;display:block;text-align:center;margin-bottom:10px">📚 Browse</a>
<button id="load" aria-label="Load from IPFS">📥 Load CID</button>
<div id="recent" style="font-size:11px;color:#888"></div>
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

// Check for reply_to parameter
const urlParams=new URLSearchParams(window.location.search);
const replyTo=urlParams.get('reply_to');
if(replyTo){
reply_to.value=replyTo;
document.getElementById('reply-info').style.display='block';
document.getElementById('reply-info').innerHTML='💬 Replying to: <a href="paste/'+replyTo+'" style="color:#0ff">'+replyTo+'</a>';
}

const submit=async()=>{
const content=c.value.trim();
if(!content)return;
let keywords=k.value.split(',').map(s=>s.trim()).filter(s=>s);

// Auto-generate keywords if empty
if(keywords.length===0){
const words=content.toLowerCase().match(/\b[a-z]{4,}\b/g)||[];
const freq={};
words.forEach(w=>freq[w]=(freq[w]||0)+1);
keywords=Object.entries(freq).sort((a,b)=>b[1]-a[1]).slice(0,5).map(e=>e[0]);
}

const replyToVal=reply_to.value||null;

// Try client IPFS first
if(ipfs){
try{
const{cid}=await ipfs.add(content);
const clientCid=cid.toString();
r.innerHTML=`<div style="color:#0ff">⏳ Sending CID to server...</div><div style="font-size:11px">Client CID: ${clientCid}</div>`;

// Send ONLY CID to server (true P2P!)
const d=await(await fetch('paste',{method:'POST',headers:{'Content-Type':'application/json'},
body:JSON.stringify({title:t.value||'untitled',keywords,cid:clientCid,reply_to:replyToVal})})).json();

showResult(d,clientCid,content);
return;
}catch(e){
r.innerHTML=`<div style="color:#f80">⚠️ Client IPFS failed, using HTTP...</div>`;
}
}

// Fallback: traditional HTTP
const d=await(await fetch('paste',{method:'POST',headers:{'Content-Type':'application/json'},
body:JSON.stringify({title:t.value||'untitled',content,keywords,reply_to:replyToVal})})).json();

showResult(d,null,content);
};

const showResult=(d,clientCid,content)=>{
c.value='';t.value='';k.value='';
qr.style.display='block';
qr.innerHTML=`<img src="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encodeURIComponent(content)}" alt="QR Code">`;
r.innerHTML=`<div style="color:#0f0">✅ ${d.id}</div>
<div style="font-size:11px">Server CID: ${d.cid}</div>
${clientCid?`<div style="font-size:11px">Client: ${clientCid}</div>`:''}
<div style="font-size:11px">IPFS: ${d.ipfs_cid||'N/A'}</div>
<div style="font-size:11px">Witness: ${d.witness.slice(0,16)}...</div>
<div style="margin-top:10px"><a href="${d.permalink}" target="_blank" style="color:#0ff">🔗 Permalink</a></div>`;

// Show similar posts
fetch('index.jsonl').then(r=>r.text()).then(text=>{
const pastes=text.split('\n').filter(Boolean).map(JSON.parse);
const latest=pastes.slice(-4,-1).reverse();
similar.style.display='block';
similar.innerHTML='<strong>🔗 Similar/Recent:</strong><br>'+latest.map(p=>
`<a href="paste/${p.id}" style="color:#0ff">${p.title}</a>`).join('<br>');
});
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

// Load recent posts on page load
fetch('index.jsonl').then(r=>r.text()).then(text=>{
const pastes=text.split('\n').filter(Boolean).map(JSON.parse);
const latest=pastes.slice(-3).reverse();
recent.innerHTML='<strong>Recent:</strong><br>'+latest.map(p=>
`<a href="paste/${p.id}" style="color:#0ff;font-size:10px">${p.title.slice(0,30)}</a>`).join('<br>');
});

b.onclick=submit;
c.onkeydown=e=>{if(e.ctrlKey&&e.key==='Enter'){e.preventDefault();submit();}};

// FRACTRAN A11y Fix
const FRACTRAN={encode:(p,a,f,s)=>2n**BigInt(p)*3n**BigInt(a)*5n**BigInt(f)*7n**BigInt(s),decode:(n)=>{n=BigInt(n);const e=p=>{let w=0;while(n%p===0n){n/=p;w++;}return w;};return{page:e(2n),action:e(3n),filter:e(5n),sort:e(7n)};},toText:(s)=>{const d=FRACTRAN.decode(s),pages=['home','browse','paste'],actions=['view','edit','delete'],filters=['all','deletable','large'],sorts=['newest','oldest'];return`Page:${pages[d.page]||'?'},Filter:${filters[d.filter]||'all'}`;}}
document.querySelectorAll('button').forEach((b,i)=>{b.setAttribute('role','button');b.setAttribute('aria-label',b.textContent.trim()||'Button');b.setAttribute('tabindex','0');b.setAttribute('data-fractran-state',FRACTRAN.encode(0,0,i,0));b.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();b.click();}}});
const live=document.createElement('div');live.id='a11y-live';live.setAttribute('aria-live','polite');live.style.cssText='position:absolute;left:-10000px;width:1px;height:1px;overflow:hidden';document.body.appendChild(live);
const skip=document.createElement('a');skip.href='#main';skip.textContent='Skip to content';skip.style.cssText='position:absolute;left:-10000px';skip.onfocus=()=>skip.style.position='static';skip.onblur=()=>skip.style.cssText='position:absolute;left:-10000px';document.body.insertBefore(skip,document.body.firstChild);
const main=document.querySelector('body>div')||document.body;main.id='main';main.setAttribute('role','main');
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
<a href="javascript:history.back()">← Back to Pastebin</a>
<input id="search" placeholder="Search by title, keywords, or ID..." aria-label="Search">
<div id="results"></div>
<script>
let allPastes=[];
const basePath=window.location.pathname.split('/browse')[0]||'';

// FRACTRAN navigation trail - encode URL as prime orbit
const primes=[2,3,5,7,11,13,17,19,23,29,31,37,41,43,47];
const encodeUrl=(url)=>{
  let state=2n;
  for(let c of url)state*=BigInt(primes[c.charCodeAt(0)%15]);
  return state;
};
const trail=localStorage.getItem('fractran_trail')||'2';
const currentUrl=window.location.pathname;
const newTrail=String(BigInt(trail)*encodeUrl(currentUrl));
localStorage.setItem('fractran_trail',newTrail);

fetch(basePath+'/index.jsonl').then(r=>r.text()).then(text=>{
allPastes=text.split('\n').filter(Boolean).map(JSON.parse).reverse();
showResults(allPastes);
});

function showResults(pastes){
results.innerHTML=pastes.map(p=>`
<div class="paste" onclick="window.open('${basePath}/paste/${p.id}','_blank')">
<div class="title">${p.title}</div>
<div class="meta">ID: ${p.id}</div>
<div class="meta">Local CID: ${p.cid}</div>
${p.ipfs_cid?`<div class="meta">IPFS CID: <a href="https://ipfs.io/ipfs/${p.ipfs_cid}" target="_blank" onclick="event.stopPropagation()">${p.ipfs_cid}</a></div>`:''}
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
p.cid.toLowerCase().includes(q)||
(p.ipfs_cid&&p.ipfs_cid.toLowerCase().includes(q))||
(p.ngrams&&p.ngrams.some(n=>n[0].includes(q)))
);
showResults(filtered);
};
// FRACTRAN A11y
const FRACTRAN={encode:(p,a,f,s)=>2n**BigInt(p)*3n**BigInt(a)*5n**BigInt(f)*7n**BigInt(s)};
document.querySelectorAll('.filter-btn').forEach((b,i)=>{b.setAttribute('role','button');b.setAttribute('aria-label',`Filter: ${b.dataset.filter||'all'}`);b.setAttribute('data-fractran-state',FRACTRAN.encode(1,0,i,0));b.setAttribute('tabindex','0');b.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();b.click();}}});
document.querySelectorAll('.paste').forEach((p,i)=>{p.setAttribute('tabindex','0');p.setAttribute('role','article');p.onkeydown=e=>{if(e.key==='Enter')p.click();else if(e.key==='ArrowDown'){e.preventDefault();p.nextElementSibling?.focus();}else if(e.key==='ArrowUp'){e.preventDefault();p.previousElementSibling?.focus();}}});
const live=document.createElement('div');live.id='a11y-live';live.setAttribute('aria-live','polite');live.style.cssText='position:absolute;left:-10000px;width:1px;height:1px';document.body.appendChild(live);
document.querySelectorAll('.filter-btn').forEach(b=>b.onclick=()=>live.textContent=`Filter: ${b.textContent}`);
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
    let (content, ipfs_cid) = if std::path::Path::new(&paste_file).exists() {
        let content = fs::read_to_string(&paste_file).ok();
        // Try to get IPFS CID from headers
        let ipfs_cid = content.as_ref().and_then(|c| {
            c.lines().find(|l| l.starts_with("IPFS-CID:"))
                .map(|l| l.trim_start_matches("IPFS-CID:").trim().to_string())
        });
        (content, ipfs_cid)
    } else {
        // Try as CID - look up in .cid file
        let cid_file = format!("{}/{}.cid", uucp_dir, id);
        if let Ok(filename) = fs::read_to_string(&cid_file) {
            let paste_file = format!("{}/{}.txt", uucp_dir, filename.trim());
            let content = fs::read_to_string(&paste_file).ok();
            let ipfs_cid = content.as_ref().and_then(|c| {
                c.lines().find(|l| l.starts_with("IPFS-CID:"))
                    .map(|l| l.trim_start_matches("IPFS-CID:").trim().to_string())
            });
            (content, ipfs_cid)
        } else {
            // Don't try IPFS for short IDs
            (None, None)
        }
    };
    
    match content {
        Some(content) => {
            // Extract title
            let title = content.lines()
                .find(|l| l.starts_with("Title:"))
                .map(|l| l.trim_start_matches("Title:").trim())
                .unwrap_or(&id);
            
            // Extract just the content after headers
            let body = if let Some(pos) = content.find("\n\n") {
                &content[pos + 2..]
            } else {
                &content
            };
            
            // Build CLI command
            let base_url = env::var("BASE_URL").unwrap_or_else(|_| "https://solana.solfunmeme.com".to_string());
            let base_path = env::var("BASE_PATH").unwrap_or_else(|_| "/pastebin".to_string());
            let cli_cmd = if let Some(cid) = &ipfs_cid {
                format!("ipfs cat {}", cid)
            } else {
                format!("curl {}{}/paste/{}", base_url, base_path, id)
            };
            
            // Find similar pastes
            let similar = find_similar_pastes(&id, &uucp_dir);
            let similar_html = if !similar.is_empty() {
                let links: Vec<String> = similar.iter().map(|(sid, score)| {
                    format!("<a href=\"{}/paste/{}\" style=\"color:#0ff\">{} ({:.0}%)</a>", base_path, sid, sid, score * 100.0)
                }).collect();
                format!("<div style=\"margin-top:20px;padding:10px;background:#111;border-left:3px solid #ff0\"><strong>🔗 Similar Pastes:</strong><br>{}</div>", links.join("<br>"))
            } else {
                String::new()
            };
            
            // Return HTML with proper UTF-8 encoding
            let html = format!(r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{}</title>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0;white-space:pre-wrap;word-wrap:break-word}}
a{{color:#0ff;text-decoration:none}}
a:hover{{text-decoration:underline}}
.header{{margin-bottom:20px;padding:10px;background:#111;border-left:3px solid #0ff}}
.cli{{background:#111;padding:10px;margin:10px 0;border-radius:4px;color:#ff0;cursor:pointer;position:relative}}
.cli:hover{{background:#222}}
.cli::after{{content:'📋 Click to copy';position:absolute;right:10px;font-size:10px;color:#888}}
.search{{width:100%;background:#1a1a1a;color:#0f0;border:1px solid #0f0;padding:10px;font-family:monospace;margin:10px 0}}
.reply-btn{{background:#0f0;color:#000;border:none;padding:5px 10px;cursor:pointer;font-weight:bold;margin:10px 0}}
.reply-btn:hover{{background:#0ff}}
.header{{display:flex;gap:10px;align-items:center;margin-bottom:10px}}
</style>
</head><body>
<div class="header">
<a href="/">🏠 Home</a>
<a href="/browse">← Browse</a>
<input class="search" id="search" placeholder="Search pastes..." onkeypress="if(event.key==='Enter'){{window.location.href='/browse?q='+encodeURIComponent(this.value)}}">
</div>
<a class="reply-btn" href="/?reply_to={id}">💬 Reply to this paste</a>
<button class="reply-btn" onclick="shareExternal('{id}');return false;">🌐 Share Externally</button>
<button class="reply-btn" onclick="shareTwitter('{id}','{title}');return false;">🐦 Tweet</button>
<button class="reply-btn" onclick="toggleSharePalette();return false;">📤 More...</button>
<div id="share-palette" style="display:none;margin:10px 0;padding:10px;background:#111;border:1px solid #0f0">
<div style="margin-bottom:10px;color:#0ff;font-weight:bold">Share Options:</div>
<button class="reply-btn" onclick="shareReddit('{id}','{title}');return false;">🔴 Reddit</button>
<button class="reply-btn" onclick="shareHN('{id}','{title}');return false;">🟠 Hacker News</button>
<button class="reply-btn" onclick="shareLinkedIn('{id}','{title}');return false;">💼 LinkedIn</button>
<button class="reply-btn" onclick="shareMastodon('{id}','{title}');return false;">🐘 Mastodon</button>
<button class="reply-btn" onclick="copyLink();return false;">📋 Copy Link</button>
<button class="reply-btn" onclick="shareEmail('{id}','{title}');return false;">📧 Email</button>
</div>
<div id="share-result" style="margin:10px 0;padding:10px;background:#111;display:none"></div>
<div class="cli" onclick="navigator.clipboard.writeText('{cli_cmd}').then(()=>{{this.style.background='#0f0';this.style.color='#000';setTimeout(()=>{{this.style.background='#111';this.style.color='#ff0'}},500)}})">$ {cli_cmd}</div>
{similar_html}
<hr style="border-color:#333">
{body}<script>
// Save history as FRACTRAN (prime-encoded)
const primes=[2,3,5,7,11,13,17,19,23,29,31,37,41,43,47];
let hist=localStorage.getItem('fractran_hist')||'2';
const id='{}';
const idx=primes.indexOf(parseInt(id.charCodeAt(0)%15));
if(idx>=0)hist=String(BigInt(hist)*BigInt(primes[idx]));
localStorage.setItem('fractran_hist',hist);

// Encode URL in FRACTRAN orbit
const encodeUrl=(url)=>{{let s=2n;for(let c of url)s*=BigInt(primes[c.charCodeAt(0)%15]);return s}};
const trail=localStorage.getItem('fractran_trail')||'2';
const newTrail=String(BigInt(trail)*encodeUrl(window.location.pathname));
localStorage.setItem('fractran_trail',newTrail);

// Share externally
const shareExternal=async(id)=>{{
const result=document.getElementById('share-result');
result.style.display='block';
result.innerHTML='<div style="color:#ff0">⏳ Sharing to external services...</div>';
try{{
const resp=await fetch('/share/'+id,{{method:'POST'}});
const data=await resp.json();
const urls=data.urls.map(u=>`<a href="${{u.url}}" target="_blank" style="color:#0ff">${{u.service}}</a>`).join(' • ');
result.innerHTML=`<div style="color:#0f0">✅ Shared to ${{data.urls.length}} services</div><div style="margin-top:5px">${{urls}}</div><div style="margin-top:5px;font-size:11px">Summary: <a href="${{data.summary_url}}" target="_blank" style="color:#0ff">${{data.summary_url}}</a></div>`;
}}catch(e){{
result.innerHTML='<div style="color:#f00">❌ Share failed: '+e.message+'</div>';
}}
}};

// Share on Twitter
const shareTwitter=(id,title)=>{{
const url=window.location.href;
const text=title.length>200?title.substring(0,197)+'...':title;
const tweetUrl=`https://twitter.com/intent/tweet?text=${{encodeURIComponent(text)}}&url=${{encodeURIComponent(url)}}&hashtags=pastebin,zkTLS,IPFS,FRACTRAN`;
window.open(tweetUrl,'_blank','width=550,height=420');
}};

// Toggle share palette
const toggleSharePalette=()=>{{
const p=document.getElementById('share-palette');
p.style.display=p.style.display==='none'?'block':'none';
}};

// Share on Reddit
const shareReddit=(id,title)=>{{
const url=window.location.href;
window.open(`https://reddit.com/submit?url=${{encodeURIComponent(url)}}&title=${{encodeURIComponent(title)}}`,'_blank');
}};

// Share on Hacker News
const shareHN=(id,title)=>{{
const url=window.location.href;
window.open(`https://news.ycombinator.com/submitlink?u=${{encodeURIComponent(url)}}&t=${{encodeURIComponent(title)}}`,'_blank');
}};

// Share on LinkedIn
const shareLinkedIn=(id,title)=>{{
const url=window.location.href;
window.open(`https://www.linkedin.com/sharing/share-offsite/?url=${{encodeURIComponent(url)}}`,'_blank');
}};

// Share on Mastodon
const shareMastodon=(id,title)=>{{
const url=window.location.href;
const text=`${{title}} ${{url}}`;
window.open(`https://mastodon.social/share?text=${{encodeURIComponent(text)}}`,'_blank');
}};

// Copy link
const copyLink=()=>{{
navigator.clipboard.writeText(window.location.href).then(()=>{{
const r=document.getElementById('share-result');
r.style.display='block';
r.innerHTML='<div style="color:#0f0">✅ Link copied to clipboard!</div>';
setTimeout(()=>r.style.display='none',2000);
}});
}};

// Share via email
const shareEmail=(id,title)=>{{
const url=window.location.href;
const subject=encodeURIComponent(title);
const body=encodeURIComponent(`Check out this paste: ${{url}}`);
window.location.href=`mailto:?subject=${{subject}}&body=${{body}}`;
}};
// FRACTRAN A11y for paste page
document.querySelectorAll('.reply-btn').forEach((b,i)=>{{b.setAttribute('role','button');b.setAttribute('aria-label',b.textContent.trim());b.setAttribute('tabindex','0');b.onkeydown=e=>{{if(e.key==='Enter'||e.key===' '){{e.preventDefault();b.click();}}}}}});
const live=document.createElement('div');live.id='a11y-live';live.setAttribute('aria-live','polite');live.style.cssText='position:absolute;left:-10000px;width:1px;height:1px';document.body.appendChild(live);
</script></body></html>"#, title, title, id, title, id, title, id, title, id, title, id, title, id, title, id, title, cli_cmd, cli_cmd, similar_html, body, id);
            
            HttpResponse::Ok().content_type("text/html; charset=utf-8").body(html)
        }
        None => HttpResponse::NotFound().body("Paste not found"),
    }
}

async fn share_external(path: web::Path<String>) -> HttpResponse {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    
    // Try to find paste file
    let content = if let Ok(entries) = fs::read_dir(&uucp_dir) {
        entries
            .filter_map(Result::ok)
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
            // Extract title and body
            let title = content.lines()
                .find(|l| l.starts_with("Title:"))
                .map(|l| l.trim_start_matches("Title:").trim())
                .unwrap_or("Untitled");
            
            let body = if let Some(pos) = content.find("\n\n") {
                &content[pos + 2..]
            } else {
                &content
            };
            
            // Call multi-poster script
            let script_path = "/home/mdupont/02-february/28/rovo/headless_browsers_test/multi-poster.sh";
            
            let output = std::process::Command::new(script_path)
                .arg(title)
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn()
                .and_then(|mut child| {
                    use std::io::Write;
                    if let Some(mut stdin) = child.stdin.take() {
                        stdin.write_all(body.as_bytes()).ok();
                    }
                    child.wait_with_output()
                });
            
            match output {
                Ok(output) if output.status.success() => {
                    // Parse JSON from last line
                    let json_str = String::from_utf8_lossy(&output.stdout).to_string();
                    if let Some(json_line) = json_str.lines().rev().find(|l| l.trim().starts_with("{")) {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(json_line.to_string())
                    } else {
                        HttpResponse::Ok().json(serde_json::json!({
                            "urls": [],
                            "error": "No JSON output"
                        }))
                    }
                }
                Ok(output) => {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    HttpResponse::InternalServerError().json(serde_json::json!({
                        "error": "Script failed",
                        "details": stderr.to_string()
                    }))
                }
                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                    "error": "Failed to execute script",
                    "details": e.to_string()
                }))
            }
        }
        None => HttpResponse::NotFound().json(serde_json::json!({
            "error": "Paste not found"
        }))
    }
}

async fn get_raw(path: web::Path<String>) -> HttpResponse {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    
    // Find paste file
    let content = if let Ok(entries) = fs::read_dir(&uucp_dir) {
        entries
            .filter_map(Result::ok)
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
            // Extract body only
            let body = if let Some(pos) = content.find("\n\n") {
                &content[pos + 2..]
            } else {
                &content
            };
            HttpResponse::Ok()
                .content_type("text/plain; charset=utf-8")
                .body(body.to_string())
        }
        None => HttpResponse::NotFound().body("Paste not found")
    }
}

async fn get_cat(path: web::Path<String>) -> HttpResponse {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    
    // Find paste file and return full path
    if let Ok(entries) = fs::read_dir(&uucp_dir) {
        if let Some(entry) = entries
            .filter_map(Result::ok)
            .find(|e| {
                let name = e.file_name();
                let name_str = name.to_string_lossy();
                name_str.contains(&id) && name_str.ends_with(".txt")
            })
        {
            let path = entry.path();
            let path_str = path.to_string_lossy();
            return HttpResponse::Ok()
                .content_type("text/plain")
                .body(format!("# Copy and paste:\ncat {}\n\n# Or:\ncurl https://solana.solfunmeme.com/pastebin/raw/{}\n", path_str, id));
        }
    }
    HttpResponse::NotFound().body("Paste not found")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8090".to_string());
    println!("🚀 Starting kant-pastebin on {}", bind);
    
    HttpServer::new(|| App::new()
        .route("/", web::get().to(old_index))
        .route("/browse", web::get().to(old_browse))
        .route("/paste", web::post().to(handlers::create_paste))
        .route("/index.jsonl", web::get().to(get_index))
        .route("/paste/{id}", web::get().to(handlers::get_paste))
        .route("/preview/{id}", web::get().to(handlers::preview_paste))
        .route("/raw/{id}", web::get().to(handlers::get_raw))
        .route("/cat/{id}", web::get().to(get_cat))
        .route("/share/{id}", web::post().to(share_external))
    )
    .bind(&bind)?
    .run()
    .await
}

fn find_similar_pastes(id: &str, uucp_dir: &str) -> Vec<(String, f64)> {
    let index_file = format!("{}/index.jsonl", uucp_dir);
    let index_content = match fs::read_to_string(&index_file) {
        Ok(c) => c,
        Err(_) => return vec![],
    };
    
    // Find current paste
    let current: PasteIndex = match index_content.lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .find(|p: &PasteIndex| p.id == id) {
        Some(p) => p,
        None => return vec![],
    };
    
    // Calculate similarity with all other pastes
    let mut similarities: Vec<(String, f64)> = index_content.lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .filter(|p| p.id != id)
        .map(|p| {
            let score = calculate_similarity(&current, &p);
            (p.id.clone(), score)
        })
        .filter(|(_, score)| *score > 0.1)
        .collect();
    
    similarities.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
    similarities.truncate(5);
    similarities
}

fn calculate_similarity(a: &PasteIndex, b: &PasteIndex) -> f64 {
    let mut score = 0.0;
    
    // Keyword overlap
    let common_keywords: usize = a.keywords.iter()
        .filter(|k| b.keywords.contains(k))
        .count();
    if !a.keywords.is_empty() && !b.keywords.is_empty() {
        score += (common_keywords as f64) / (a.keywords.len().max(b.keywords.len()) as f64) * 0.4;
    }
    
    // N-gram overlap
    let a_ngrams: std::collections::HashSet<_> = a.ngrams.iter().map(|(s, _)| s).collect();
    let b_ngrams: std::collections::HashSet<_> = b.ngrams.iter().map(|(s, _)| s).collect();
    let common_ngrams = a_ngrams.intersection(&b_ngrams).count();
    if !a_ngrams.is_empty() && !b_ngrams.is_empty() {
        score += (common_ngrams as f64) / (a_ngrams.len().max(b_ngrams.len()) as f64) * 0.6;
    }
    
    score
}
