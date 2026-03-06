use actix_web::{web, App, HttpResponse, HttpServer};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::fs;
use std::env;
use chrono::Utc;

#[derive(Deserialize)]
struct Paste {
    content: String,
    title: Option<String>,
}

#[derive(Serialize)]
struct Response {
    id: String,
    witness: String,
    uucp: String,
}

async fn paste(data: web::Json<Paste>) -> HttpResponse {
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let id = format!("paste_{}", ts);
    
    let mut hasher = Sha256::new();
    hasher.update(&data.content);
    let witness = hex::encode(hasher.finalize());
    
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let uucp = format!("{}/{}.txt", uucp_dir, id);
    let content = format!("--- {} ---\nTitle: {}\nWitness: {}\n\n{}\n",
        id, data.title.as_deref().unwrap_or("untitled"), witness, data.content);
    
    fs::write(&uucp, content).ok();
    
    HttpResponse::Ok().json(Response { id, witness, uucp })
}

async fn index() -> HttpResponse {
    HttpResponse::Ok().content_type("text/html; charset=utf-8").body(r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Kant Pastebin - UUCP + zkTLS</title>
</head><body>
<main role="main">
<h1>Pastebin → UUCP + zkTLS</h1>
<form id="f" aria-label="Paste submission form">
<label for="t">Title:</label>
<input id="t" type="text" placeholder="Title" aria-label="Paste title"><br>
<label for="c">Content:</label>
<textarea id="c" rows="20" cols="80" aria-label="Paste content" required></textarea><br>
<button type="submit" aria-label="Submit paste">Submit</button>
</form>
<div id="r" role="status" aria-live="polite"></div>
</main>
<script>
f.onsubmit=async e=>{e.preventDefault();
const d=await(await fetch('/paste',{method:'POST',headers:{'Content-Type':'application/json'},
body:JSON.stringify({title:t.value,content:c.value})})).json();
r.innerHTML=`✅ ${d.id}<br>Witness: ${d.witness}<br>UUCP: ${d.uucp}`;};
</script></body></html>"#)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    HttpServer::new(|| App::new().route("/", web::get().to(index)).route("/paste", web::post().to(paste)))
        .bind(&bind)?.run().await
}
