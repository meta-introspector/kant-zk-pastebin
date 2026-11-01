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

fn find_bytes(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || hay.len() < needle.len() { return None; }
    hay.windows(needle.len()).position(|w| w == needle)
}

fn parse_multipart_bytes(body: &[u8], boundary: &str) -> std::result::Result<Vec<(String, Option<String>, Vec<u8>)>, String> {
    let crlf_delim = format!("\r\n--{}", boundary).into_bytes();
    let mut norm = Vec::with_capacity(body.len() + 2);
    norm.extend_from_slice(b"\r\n");
    norm.extend_from_slice(body);
    let mut out = Vec::new();
    let mut pos = match find_bytes(&norm, &crlf_delim) { Some(p) => p + crlf_delim.len(), None => return Ok(out) };
    loop {
        if pos + 2 <= norm.len() && &norm[pos..pos + 2] == b"--" { break; }
        let hdr_start = if norm[pos..].starts_with(b"\r\n") { pos + 2 } else { pos };
        let hdr_end = match find_bytes(&norm[hdr_start..], b"\r\n\r\n") { Some(h) => hdr_start + h, None => break };
        let data_start = hdr_end + 4;
        let next = match find_bytes(&norm[data_start..], &crlf_delim) { Some(n) => data_start + n, None => break };
        let data_end = next;
        let hdr = std::str::from_utf8(&norm[hdr_start..hdr_end]).map_err(|_| "header not UTF-8".to_string())?;
        let mut name = String::new();
        let mut filename: Option<String> = None;
        for line in hdr.lines() {
            let l = line.to_ascii_lowercase();
            if l.starts_with("content-disposition:") {
                for part in line.split(';') {
                    let p = part.trim();
                    if let Some(v) = p.strip_prefix("name=\"") { name = v.trim_end_matches('"').to_string(); }
                    else if let Some(v) = p.strip_prefix("filename=\"") { filename = Some(v.trim_end_matches('"').to_string()); }
                }
            }
        }
        out.push((name, filename, norm[data_start..data_end].to_vec()));
        pos = next + crlf_delim.len();
    }
    Ok(out)
}


/// POST /upload - Upload file (multipart or raw body)

#[cfg(target_os = "linux")]
fn safe_unlink(file: &std::fs::File) -> std::io::Result<()> {
    use std::os::unix::io::AsRawFd;
    let fd = file.as_raw_fd();
    let ret = unsafe { libc::unlinkat(fd, b"\0".as_ptr() as *const _, libc::AT_EMPTY_PATH) };
    if ret == -1 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

pub async fn upload_file(req: HttpRequest, body: web::Bytes) -> Result<HttpResponse> {
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let mut file_data: Vec<u8> = Vec::new();
    let mut orig_name = String::new();
    let mut user_title = String::new();
    let mut user_description = String::new();
    let mut content_text = String::new();

    let ct = req.headers().get("Content-Type").and_then(|v| v.to_str().ok()).unwrap_or("").to_string();

    if ct.starts_with("multipart/form-data") {
        let boundary = ct.split(';').filter_map(|p| p.trim().strip_prefix("boundary=").map(|s| s.trim().to_string())).next();
        if let Some(ref b) = boundary {
            let parts = parse_multipart_bytes(&body, b).map_err(|e| actix_web::error::ErrorBadRequest(e))?;
            for (name, filename, data) in parts {
                match name.as_str() {
                    "file" => { orig_name = filename.unwrap_or_else(|| "upload".to_string()); file_data = data; }
                    "content" => content_text = String::from_utf8(data).unwrap_or_default(),
                    "title" => user_title = clean_field(&String::from_utf8_lossy(&data)),
                    "description" => user_description = clean_field(&String::from_utf8_lossy(&data)),
                    _ => {}
                }
            }
        } else {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "missing boundary"})));
        }
    } else {
        let bod = String::from_utf8_lossy(&body).to_string();
        if let Ok(j) = serde_json::from_str::<serde_json::Value>(&bod) {
            content_text = j.get("content").and_then(|v| v.as_str()).unwrap_or("").to_string();
            user_title = j.get("title").and_then(|v| v.as_str()).unwrap_or("").to_string();
            user_description = j.get("description").and_then(|v| v.as_str()).unwrap_or("").to_string();
        }
    }

    if file_data.is_empty() && content_text.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({"error": "no file or content"})));
    }

    if file_data.is_empty() && !content_text.is_empty() {
        file_data = content_text.clone().into_bytes();
        orig_name = if user_title.is_empty() { "content.txt".to_string() } else { user_title.clone() };
    }

    let ext = orig_name.rsplit('.').next().unwrap_or("bin");
    let mime = if orig_name.to_lowercase().ends_with(".mth") || orig_name.to_lowercase().ends_with(".mht") || orig_name.to_lowercase().ends_with(".html") {
        "text/html".parse::<mime_guess::Mime>().unwrap_or_else(|_| mime_guess::from_ext(ext).first_or_octet_stream())
    } else { mime_guess::from_ext(ext).first_or_octet_stream() };
    let mime_str = mime.to_string();

    let save_title = if user_title.is_empty() { archive_name_title(&orig_name) } else { user_title.clone() };
    let save_slug = tagging::slugify(&save_title);
    let filename = format!("{}_{}.{}", ts, save_slug, ext);
    let id = filename.rsplit_once('.').map(|(s, _)| s).unwrap_or(&filename).to_string();
    let uucp = format!("{}/{}", uucp_dir, filename);

    // Stage upload in the spool filesystem and publish without overwriting.
    let mut staged = match tempfile::NamedTempFile::new_in(&uucp_dir) {
        Ok(f) => f,
        Err(e) => return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": format!("staging failed: {}", e)}))),
    };
    if let Err(e) = std::io::Write::write_all(&mut staged, &file_data) {
        return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": format!("write failed: {}", e)})));
    }
    let published = match staged.persist_noclobber(&uucp) {
        Ok(f) => f,
        Err(e) => return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": format!("publish failed: {}", e.error)}))),
    };

    let mut hasher = Sha256::new();
    hasher.update(&file_data);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    let ipfs_cid = ipfs::ipfs_add_bytes(&file_data);

    let final_title = save_title.clone();
    let final_description = if user_description.is_empty() { file_description(&orig_name, &mime_str, file_data.len(), &file_data) } else { user_description.clone() };

    let cid_file = format!("{}/{}.cid", uucp_dir, local_cid);

    // C13: Defer CID alias publication until after successful indexing.
    // Never delete an alias belonging to another operation.

    // 1. Write to index
    if let Err(e) = write_index_entry(&uucp_dir, &id, &final_title, Some(&final_description), vec!["upload".to_string(), ext.to_string()], &local_cid, &witness, &filename, file_data.len(), ipfs_cid.clone(), None, None) {
        error!("[upload] index failed; spool retained for reconciliation: {}", uucp);

        // C13-RUST-05: Never unlink a published pathname on this error path.
        // This prevents deletion of a concurrently substituted entry.
        // The unindexed spool object remains a separate OPEN defect.
        #[cfg(test)]
        c13_rollback_probe::run(&uucp);
        #[cfg(test)]
        c13_after_check_probe::run(&uucp);

        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({"error": format!("index failed: {}", e)})));
    }

    // 2. Publish alias only after the index append succeeds.
    // Alias publication failures still require separate reconciliation.
    crate::handlers::publish_cid_alias("upload", &cid_file, &id);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id, "filename": filename, "title": final_title, "description": final_description,
        "cid": local_cid, "ipfs_cid": ipfs_cid, "witness": witness, "mime": mime_str,
        "size": file_data.len(), "url": format!("/paste/{}", id),
    })))
}

// F5-DS11/C13: negative regression test, isolated copy only.
#[cfg(test)]
mod c13_rollback_security_tests {
    use super::*;

    #[actix_web::test]
    async fn c13_preexisting_alias_is_preserved_on_index_failure() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs_dir = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs_dir).unwrap();

        // Make the real index writer fail with EISDIR.
        fs::create_dir(spool.join("index.jsonl")).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs_dir);

        let title = "c13-preexisting.txt";
        let content = "C13_PREEXISTING_ALIAS_TEST";
        let hash = Sha256::digest(content.as_bytes());
        let cid = format!("bafk{}", hex::encode(&hash[..16]));
        let alias = spool.join(format!("{}.cid", cid));

        // Start at a fresh UTC second to predict the handler ID.
        let previous_second = Utc::now().timestamp();
        while Utc::now().timestamp() == previous_second {
            std::thread::sleep(std::time::Duration::from_millis(2));
        }

        let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
        let expected_id = format!("{}_{}", ts, tagging::slugify(title));

        // This alias exists BEFORE the upload.
        fs::write(&alias, &expected_id).unwrap();
        let original_metadata = fs::metadata(&alias).unwrap();

        let req = actix_web::test::TestRequest::default()
            .insert_header(("Content-Type", "application/json"))
            .to_http_request();

        let payload = serde_json::json!({
            "title": title,
            "content": content
        });

        let response = upload_file(
            req,
            web::Bytes::from(payload.to_string())
        ).await.unwrap();

        let status = response.status();
        let bytes = actix_web::body::to_bytes(
            response.into_body()
        ).await.unwrap();

        let result: serde_json::Value =
            serde_json::from_slice(&bytes).unwrap();

        assert_eq!(
            status,
            actix_web::http::StatusCode::INTERNAL_SERVER_ERROR
        );

        let error = result["error"].as_str().unwrap_or("");

        assert!(
            error.starts_with("index failed:"),
            "Wrong failure branch: {}",
            error
        );

        eprintln!("C13_INDEX_FAILURE_BRANCH_CONFIRMED");
        eprintln!("C13_ALIAS_EXISTS={}", alias.exists());

        assert!(
            alias.exists(),
            "C13 VULNERABILITY: rollback deleted a preexisting CID alias"
        );

        assert_eq!(
            fs::read_to_string(&alias).unwrap(),
            expected_id,
            "Preexisting alias content was changed"
        );

        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            let after = fs::metadata(&alias).unwrap();

            assert_eq!(after.dev(), original_metadata.dev());
            assert_eq!(after.ino(), original_metadata.ino());
        }
    }
}

#[cfg(test)]
mod c13_rollback_probe {
    use std::sync::Mutex;

    static HOOK: Mutex<Option<fn(&str)>> = Mutex::new(None);

    pub(super) fn set(hook: Option<fn(&str)>) {
        *HOOK.lock().unwrap() = hook;
    }

    pub(super) fn run(path: &str) {
        let hook = *HOOK.lock().unwrap();
        if let Some(callback) = hook {
            callback(path);
        }
    }
}

#[cfg(test)]
mod c13_spool_substitution_tests {
    use super::*;
    use std::path::Path;

    const VICTIM: &[u8] = b"C13_PREEXISTING_VICTIM";

    fn substitute_spool(path: &str) {
        let published = Path::new(path);
        let dir = published.parent().unwrap();

        let retained = published.with_extension("saved-c13");
        let victim = dir.join("c13-preexisting-victim");

        fs::rename(published, &retained).unwrap();
        fs::rename(&victim, published).unwrap();

        eprintln!("C13_SUBSTITUTION_INJECTED");
    }

    #[actix_web::test]
    async fn c13_spool_substitution_must_not_delete_victim() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        // Force the actual index writer to fail.
        fs::create_dir(spool.join("index.jsonl")).unwrap();

        // A preexisting file owned by another operation.
        fs::write(spool.join("c13-preexisting-victim"), VICTIM)
            .unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let req = actix_web::test::TestRequest::default()
            .insert_header(("Content-Type", "application/json"))
            .to_http_request();

        let payload = serde_json::json!({
            "title": "c13-spool-substitution",
            "content": "C13_SPOOL_ROLLBACK_CASE"
        });

        c13_rollback_probe::set(Some(substitute_spool));

        let response = upload_file(
            req,
            web::Bytes::from(payload.to_string())
        ).await.unwrap();

        c13_rollback_probe::set(None);

        let status = response.status();
        let bytes = actix_web::body::to_bytes(
            response.into_body()
        ).await.unwrap();

        let result: serde_json::Value =
            serde_json::from_slice(&bytes).unwrap();

        assert_eq!(
            status,
            actix_web::http::StatusCode::INTERNAL_SERVER_ERROR
        );

        assert!(
            result["error"]
                .as_str()
                .unwrap_or("")
                .starts_with("index failed:"),
            "Unexpected failure branch: {}",
            result
        );

        eprintln!("C13_INDEX_FAILURE_BRANCH_CONFIRMED");

        assert!(
            fs::read_dir(&spool).unwrap().flatten().any(|entry| {
                entry.path().extension().and_then(|e| e.to_str())
                    == Some("saved-c13")
            }),
            "C13_TEST_INVALID: substitution hook did not execute"
        );

        let victim_survived = fs::read_dir(&spool)
            .unwrap()
            .flatten()
            .any(|entry| {
                fs::read(entry.path())
                    .map(|bytes| bytes == VICTIM)
                    .unwrap_or(false)
            });

        eprintln!("C13_VICTIM_SURVIVED={}", victim_survived);

        assert!(
            victim_survived,
            "C13 VULNERABILITY: rollback deleted substituted spool file"
        );
    }
}

#[cfg(test)]
mod c13_after_check_probe {
    use std::sync::Mutex;

    static HOOK: Mutex<Option<fn(&str)>> = Mutex::new(None);

    pub(super) fn set(hook: Option<fn(&str)>) {
        *HOOK.lock().unwrap() = hook;
    }

    pub(super) fn run(path: &str) {
        let callback = *HOOK.lock().unwrap();
        if let Some(f) = callback {
            f(path);
        }
    }
}

#[cfg(test)]
mod c13_after_identity_check_tests {
    use super::*;
    use std::path::Path;

    const VICTIM: &[u8] = b"C13_AFTERCHECK_PREEXISTING_VICTIM";

    fn substitute_after_check(path: &str) {
        let published = Path::new(path);
        let spool = published.parent().unwrap();

        let saved = published.with_extension("c13-saved");
        let victim = spool.join("c13-aftercheck-victim");

        // Preserve the originally published inode.
        fs::rename(published, &saved).unwrap();

        // Replace pathname with an unrelated existing file.
        fs::rename(&victim, published).unwrap();

        eprintln!("C13_AFTERCHECK_SUBSTITUTION_INJECTED");
    }

    #[actix_web::test]
    async fn c13_spool_after_identity_check_must_preserve_victim() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        // Force the actual index writer to fail.
        fs::create_dir(spool.join("index.jsonl")).unwrap();

        fs::write(spool.join("c13-aftercheck-victim"), VICTIM)
            .unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let req = actix_web::test::TestRequest::default()
            .insert_header(("Content-Type", "application/json"))
            .to_http_request();

        let payload = serde_json::json!({
            "title": "c13-aftercheck",
            "content": "C13_AFTERCHECK_UPLOAD"
        });

        c13_after_check_probe::set(Some(substitute_after_check));

        let response = upload_file(
            req,
            web::Bytes::from(payload.to_string())
        ).await.unwrap();

        c13_after_check_probe::set(None);

        assert_eq!(
            response.status(),
            actix_web::http::StatusCode::INTERNAL_SERVER_ERROR
        );

        let bytes = actix_web::body::to_bytes(
            response.into_body()
        ).await.unwrap();

        let result: serde_json::Value =
            serde_json::from_slice(&bytes).unwrap();

        assert!(
            result["error"].as_str().unwrap_or("")
                .starts_with("index failed:"),
            "Unexpected failure branch: {}",
            result
        );

        eprintln!("C13_INDEX_FAILURE_BRANCH_CONFIRMED");

        assert!(
            fs::read_dir(&spool).unwrap().flatten().any(|entry| {
                entry.path().extension().and_then(|e| e.to_str())
                    == Some("c13-saved")
            }),
            "C13_TEST_INVALID: substitution hook did not execute"
        );

        let survived = fs::read_dir(&spool)
            .unwrap()
            .flatten()
            .any(|entry| {
                fs::read(entry.path())
                    .map(|data| data == VICTIM)
                    .unwrap_or(false)
            });

        eprintln!("C13_AFTERCHECK_VICTIM_SURVIVED={}", survived);

        assert!(
            survived,
            "C13 TOCTOU: substituted file deleted after inode verification"
        );
    }
}


#[cfg(test)]
mod c13_orphan_spool_tests {
    use super::*;

    #[actix_web::test]
    async fn c13_index_failure_must_not_leave_unindexed_spool() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        // Force index failure.
        fs::create_dir(spool.join("index.jsonl")).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let req = actix_web::test::TestRequest::default()
            .insert_header(("Content-Type", "application/json"))
            .to_http_request();

        let content = "C13_ORPHAN_SPOOL_TEST";
        let payload = serde_json::json!({
            "title": "c13-orphan.txt",
            "content": content
        });

        let response = upload_file(
            req,
            web::Bytes::from(payload.to_string())
        ).await.unwrap();

        assert_eq!(
            response.status(),
            actix_web::http::StatusCode::INTERNAL_SERVER_ERROR
        );

        let body = actix_web::body::to_bytes(
            response.into_body()
        ).await.unwrap();

        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert!(
            result["error"].as_str().unwrap_or("")
                .starts_with("index failed:")
        );

        eprintln!("C13_INDEX_FAILURE_CONFIRMED");

        let orphans: Vec<_> = fs::read_dir(&spool)
            .unwrap()
            .flatten()
            .filter(|entry| {
                entry.file_type()
                    .map(|kind| kind.is_file())
                    .unwrap_or(false)
            })
            .filter(|entry| {
                fs::read(entry.path())
                    .map(|data| data == content.as_bytes())
                    .unwrap_or(false)
            })
            .map(|entry| entry.path())
            .collect();

        eprintln!("C13_UNINDEXED_SPOOL_COUNT={}", orphans.len());

        assert!(
            orphans.is_empty(),
            "C13 VULNERABILITY: unindexed spool left after index failure"
        );
    }
}


#[cfg(test)]
mod c13_http_orphan_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_failed_upload_must_not_be_http_accessible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        // Force a real index write failure.
        fs::create_dir(spool.join("index.jsonl")).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route(
                    "/file/{id}",
                    web::get().to(crate::handlers::get_file)
                )
        ).await;

        let content = "C13_HTTP_ORPHAN_VISIBILITY_PROBE";

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-http-orphan.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;

        assert_eq!(
            response.status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );

        let body = test::read_body(response).await;
        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert!(
            result["error"].as_str().unwrap_or("")
                .starts_with("index failed:"),
            "Unexpected failure: {}",
            result
        );

        eprintln!("C13_HTTP_INDEX_FAILURE_CONFIRMED");

        let files: Vec<_> = fs::read_dir(&spool)
            .unwrap()
            .flatten()
            .filter(|entry| {
                entry.file_type()
                    .map(|t| t.is_file())
                    .unwrap_or(false)
            })
            .filter(|entry| {
                fs::read(entry.path())
                    .map(|bytes| bytes == content.as_bytes())
                    .unwrap_or(false)
            })
            .collect();

        assert_eq!(
            files.len(), 1,
            "Expected exactly one orphan spool file"
        );

        let filename = files[0]
            .file_name()
            .to_string_lossy()
            .to_string();

        let url = format!("/file/{}", filename);

        let request = test::TestRequest::get()
            .uri(&url)
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;

        let exposed =
            status == StatusCode::OK &&
            body.as_ref() == content.as_bytes();

        eprintln!("C13_HTTP_GET_STATUS={}", status);
        eprintln!("C13_HTTP_UNINDEXED_FILE_EXPOSED={}", exposed);

        assert!(
            !exposed,
            "C13 VULNERABILITY: failed upload accessible via HTTP"
        );
    }
}
