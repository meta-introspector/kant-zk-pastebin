// Upload file handler — split from 5895-line handlers.rs to avoid edit tool issues.
// Parses multipart/form-data manually (actix-multipart rejects MHT files with
// "Nested multipart is not supported").

use crate::handlers::capture_error_case;
use crate::handlers::{archive_name_title, clean_field, file_description, write_index_entry};
use crate::ipfs;
use crate::tagging;
use actix_web::{web, HttpRequest, HttpResponse, Result};
use chrono::Utc;
use log::{error, info};
use sha2::{Digest, Sha256};
use std::{collections::HashMap, env, fs};

/// POST /upload - Upload file (multipart or raw body)
pub async fn upload_file(req: HttpRequest, body: web::Bytes) -> Result<HttpResponse> {
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let mut file_data: Vec<u8> = Vec::new();
    let mut orig_name = String::new();
    let mut user_title = String::new();
    let mut user_description = String::new();
    let mut content_text = String::new();

    // Parse multipart manually — actix-multipart streaming parser rejects
    // MHT files (internal multipart/* headers) with "Nested multipart".
    let ct = req
        .headers()
        .get("Content-Type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    if ct.starts_with("multipart/form-data") {
        let boundary = ct
            .split(';')
            .filter_map(|p| p.trim().strip_prefix("boundary=").map(|s| s.trim().to_string()))
            .next();

        if let Some(ref b) = boundary {
            let open = format!("--{}", b);
            let bod = String::from_utf8_lossy(&body);
            for raw in bod.split(&open) {
                let raw = raw.trim();
                if raw.is_empty() || raw == "--" {
                    continue;
                }
                let (hdr, dat) = match raw.split_once("\r\n\r\n") {
                    Some((h, d)) => (
                        h,
                        d.trim_end_matches('\n')
                            .trim_end_matches('\r')
                            .trim_end_matches("--")
                            .trim_end_matches('\n')
                            .trim_end_matches('\r'),
                    ),
                    None => continue,
                };
                let disp = hdr
                    .lines()
                    .find(|l| l.to_lowercase().contains("content-disposition"))
                    .unwrap_or("");
                let fname = disp
                    .split(';')
                    .filter_map(|s| {
                        s.trim()
                            .strip_prefix("name=\"")
                            .and_then(|s| s.strip_suffix('"'))
                    })
                    .next()
                    .unwrap_or("");
                let bts = dat.as_bytes().to_vec();
                match fname {
                    "file" => {
                        orig_name = disp
                            .split(';')
                            .filter_map(|s| {
                                s.trim()
                                    .strip_prefix("filename=\"")
                                    .and_then(|s| s.strip_suffix('"'))
                            })
                            .next()
                            .unwrap_or("upload")
                            .to_string();
                        file_data = bts;
                    }
                    "content" => content_text = String::from_utf8_lossy(&bts).to_string(),
                    "title" => user_title = clean_field(&String::from_utf8_lossy(&bts)),
                    "description" => {
                        user_description = clean_field(&String::from_utf8_lossy(&bts))
                    }
                    _ => {}
                }
            }
        } else {
            // Content-Type is multipart/form-data but has no boundary
            error!("[upload] missing boundary in multipart Content-Type: {}", ct);
            return Ok(HttpResponse::BadRequest().json(
                serde_json::json!({"error": "missing boundary in multipart Content-Type"}),
            ));
        }
    } else {
        // Not multipart — try JSON body
        let bod = String::from_utf8_lossy(&body).to_string();
        if let Ok(j) = serde_json::from_str::<serde_json::Value>(&bod) {
            content_text = j
                .get("content")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            user_title = j
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            user_description = j
                .get("description")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
        }
    }

    if file_data.is_empty() && content_text.is_empty() {
        let resp = serde_json::json!({"error": "no file or content"});
        return Ok(HttpResponse::BadRequest().json(resp));
    }

    if file_data.is_empty() && !content_text.is_empty() {
        file_data = content_text.clone().into_bytes();
        orig_name = if user_title.is_empty() {
            "content.txt".to_string()
        } else {
            user_title.clone()
        };
    }

    let ext = orig_name.rsplit('.').next().unwrap_or("bin");
    let mime = if orig_name.to_lowercase().ends_with(".mth")
        || orig_name.to_lowercase().ends_with(".mht")
        || orig_name.to_lowercase().ends_with(".html")
    {
        "text/html"
            .parse::<mime_guess::Mime>()
            .unwrap_or_else(|_| mime_guess::from_ext(ext).first_or_octet_stream())
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

    if let Err(e) = fs::write(&uucp, &file_data) {
        error!("[upload] failed to write {}: {}", uucp, e);
        return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": format!("write failed: {}", e)})));
    }
    info!("[upload] saved file: {} ({} bytes)", uucp, file_data.len());

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

    info!(
        "[upload] completed: id={} title='{}'",
        id, final_title
    );

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id,
        "filename": filename,
        "title": final_title,
        "description": final_description,
        "cid": local_cid,
        "ipfs_cid": ipfs_cid,
        "witness": witness,
        "mime": mime_str,
        "size": file_data.len(),
        "url": format!("/paste/{}", id),
    })))
}
