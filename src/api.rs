// API - JSON endpoints for kant-pastebin
use actix_web::{web, HttpResponse};
use crate::model::{Paste, Response, PasteIndex};
use chrono::Utc;
use sha2::{Sha256, Digest};

fn slugify(s: &str) -> String {
    s.chars()
        .map(|c| if c.is_alphanumeric() { c.to_ascii_lowercase() } else { '_' })
        .collect::<String>()
        .split('_')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("_")
}

/// POST /api/paste - Create new paste
pub async fn create_paste(data: web::Json<Paste>) -> HttpResponse {
    let content = data.content.as_ref().map(|s| s.as_str()).unwrap_or("");
    let title = data.title.as_ref().map(|s| s.as_str()).unwrap_or("untitled");
    
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let hash = hasher.finalize();
    let cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    
    let slug_title = slugify(title);
    let filename = format!("{}_{}.txt", ts, slug_title);
    let id = filename.trim_end_matches(".txt").to_string();
    
    HttpResponse::Ok().json(Response {
        id: id.clone(),
        cid,
        ipfs_cid: None,
        witness,
        url: format!("/paste/{}", id),
        permalink: format!("/paste/{}", id),
        uucp_path: format!("/var/spool/uucp/{}", filename),
        reply_to: data.reply_to.clone(),
    })
}

/// GET /api/paste/{id} - Get paste as JSON
pub async fn get_paste_json(path: web::Path<String>) -> HttpResponse {
    HttpResponse::Ok().json(PasteIndex {
        id: path.to_string(),
        title: "".to_string(),
        keywords: vec![],
        cid: "".to_string(),
        witness: "".to_string(),
        timestamp: Utc::now().to_rfc3339(),
        filename: "".to_string(),
        ngrams: vec![],
        ipfs_cid: None,
        reply_to: None,
        size: 0,
        uucp_path: "".to_string(),
    })
}
