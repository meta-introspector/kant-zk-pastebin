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

    let mut hasher = Sha256::new();
    hasher.update(&file_data);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);

    // C13-RUST-55: register PREPARED before spool publication.
    if let Err(e) = crate::handlers::c13_sqlite_prepare(
        &uucp_dir, &id, &filename, &witness, &local_cid
    ) {
        error!("[upload] SQLite prepare failed: {}", e);
        return Ok(HttpResponse::InternalServerError().json(
            serde_json::json!({
                "error": format!("transaction prepare failed: {}", e)
            })
        ));
    }

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
    if let Err(e) =
        crate::handlers::publish_cid_alias_checked(&cid_file, &id)
    {
        error!("[upload] CID alias publication failed: {}", e);
        return Ok(HttpResponse::InternalServerError().json(
            serde_json::json!({
                "error": format!("CID alias publication failed: {}", e)
            })
        ));
    }


    // C13-RUST-31: publish commit only after index and alias succeed.
    match crate::handlers::c13_publish_upload_commit(
        &uucp_dir, &id, &filename, &witness, &local_cid
    ) {
        crate::handlers::C13CommitOutcome::PublishedDurable => {}
        crate::handlers::C13CommitOutcome::NotPublished(e) => {
            error!("[upload] commit not published: {}", e);
            return Ok(HttpResponse::InternalServerError().json(
                serde_json::json!({
                    "error": format!("commit not published: {}", e)
                })
            ));
        }
        crate::handlers::C13CommitOutcome::DurabilityUncertain(e) => {
            error!("[upload] commit durability uncertain: {}", e);
            return Ok(HttpResponse::Accepted().json(
                serde_json::json!({
                    "id": id,
                    "status": "durability_uncertain",
                    "warning": "commit marker published, durability not confirmed"
                })
            ));
        }
    }

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

// C13-RUST-08: positive HTTP regression.
#[cfg(test)]
mod c13_http_committed_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_indexed_upload_remains_http_accessible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

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

        let content = "C13_VALID_COMMITTED_UPLOAD";

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-indexed.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;

        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        let filename = result["filename"]
            .as_str()
            .expect("missing filename");

        let request = test::TestRequest::get()
            .uri(&format!("/file/{}", filename))
            .to_request();

        let response = test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        assert_eq!(body.as_ref(), content.as_bytes());

        eprintln!("C13_HTTP_INDEXED_UPLOAD_VISIBLE=true");
    }
}


#[cfg(test)]
mod c13_raw_orphan_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_failed_upload_must_not_be_raw_accessible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        // Inject real index failure.
        fs::create_dir(spool.join("index.jsonl")).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route(
                    "/raw/{id}",
                    web::get().to(crate::handlers::get_raw)
                )
        ).await;

        let content = "C13_RAW_ORPHAN_SECRET";

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-raw-orphan.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;

        assert_eq!(
            response.status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );

        let body = test::read_body(response).await;
        let error: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert!(
            error["error"].as_str().unwrap_or("")
                .starts_with("index failed:"),
            "Wrong failure branch: {}",
            error
        );

        eprintln!("C13_RAW_INDEX_FAILURE_CONFIRMED");

        let files: Vec<_> = fs::read_dir(&spool)
            .unwrap()
            .flatten()
            .filter(|entry| {
                entry.path().extension()
                    .and_then(|e| e.to_str()) == Some("txt")
            })
            .filter(|entry| {
                fs::read(entry.path())
                    .map(|v| v == content.as_bytes())
                    .unwrap_or(false)
            })
            .collect();

        assert_eq!(
            files.len(), 1,
            "Expected exactly one unindexed upload"
        );

        let id = files[0].path()
            .file_stem()
            .unwrap()
            .to_string_lossy()
            .to_string();

        let request = test::TestRequest::get()
            .uri(&format!("/raw/{}", id))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;

        let exposed = body.as_ref() == content.as_bytes();

        eprintln!("C13_RAW_HTTP_STATUS={}", status);
        eprintln!("C13_RAW_ORPHAN_EXPOSED={}", exposed);

        assert!(
            !exposed,
            "C13 VULNERABILITY: failed upload exposed via /raw"
        );
    }
}

#[cfg(test)]
mod c13_raw_committed_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_indexed_upload_remains_raw_accessible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route(
                    "/raw/{id}",
                    web::get().to(crate::handlers::get_raw)
                )
        ).await;

        let content = "C13_VALID_INDEXED_RAW_CONTENT";

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-raw-indexed.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;

        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        let id = result["id"]
            .as_str()
            .expect("missing id");

        let request = test::TestRequest::get()
            .uri(&format!("/raw/{}", id))
            .to_request();

        let response = test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        assert_eq!(body.as_ref(), content.as_bytes());

        eprintln!("C13_VALID_INDEXED_RAW_ACCESSIBLE=true");
    }
}


#[cfg(test)]
mod c13_paste_orphan_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_failed_upload_must_not_be_paste_accessible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        // Force index failure without mocking the writer.
        fs::create_dir(spool.join("index.jsonl")).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route(
                    "/paste/{id}",
                    web::get().to(crate::handlers::get_paste)
                )
        ).await;

        let content = "C13_PASTE_ORPHAN_SECRET";

        let upload = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-paste-orphan.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, upload).await;

        assert_eq!(
            response.status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );

        let body = test::read_body(response).await;
        let error: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert!(
            error["error"].as_str().unwrap_or("")
                .starts_with("index failed:"),
            "Wrong failure branch: {}",
            error
        );

        eprintln!("C13_PASTE_INDEX_FAILURE_CONFIRMED");

        let files: Vec<_> = fs::read_dir(&spool)
            .unwrap()
            .flatten()
            .filter(|entry| {
                entry.path().extension()
                    .and_then(|e| e.to_str()) == Some("txt")
            })
            .filter(|entry| {
                fs::read(entry.path())
                    .map(|bytes| bytes == content.as_bytes())
                    .unwrap_or(false)
            })
            .collect();

        assert_eq!(files.len(), 1);

        let id = files[0]
            .path()
            .file_stem()
            .unwrap()
            .to_string_lossy()
            .to_string();

        let request = test::TestRequest::get()
            .uri(&format!("/paste/{}", id))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;

        let exposed = String::from_utf8_lossy(&body)
            .contains(content);

        eprintln!("C13_PASTE_HTTP_STATUS={}", status);
        eprintln!("C13_PASTE_ORPHAN_EXPOSED={}", exposed);

        assert!(
            !exposed,
            "C13 VULNERABILITY: failed upload exposed via /paste"
        );

        assert_eq!(
            status,
            StatusCode::NOT_FOUND,
            "Unindexed upload must return HTTP 404"
        );
    }
}


#[cfg(test)]
mod c13_paste_committed_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_indexed_uploads_remain_paste_accessible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route(
                    "/paste/{id}",
                    web::get().to(crate::handlers::get_paste)
                )
        ).await;

        let cases = [
            ("c13-committed-plain.txt", "C13_VALID_PASTE_TEXT"),
            ("c13-committed-binary.bin", "C13_VALID_PASTE_BINARY"),
        ];

        for (title, content) in cases {
            let request = test::TestRequest::post()
                .uri("/upload")
                .set_json(serde_json::json!({
                    "title": title,
                    "content": content
                }))
                .to_request();

            let response = test::call_service(&app, request).await;
            assert_eq!(
                response.status(),
                StatusCode::OK,
                "Upload failed for {}",
                title
            );

            let body = test::read_body(response).await;
            let result: serde_json::Value =
                serde_json::from_slice(&body).unwrap();

            let id = result["id"].as_str().unwrap();

            let request = test::TestRequest::get()
                .uri(&format!("/paste/{}", id))
                .to_request();

            let response = test::call_service(&app, request).await;

            assert_eq!(
                response.status(),
                StatusCode::OK,
                "Indexed paste not accessible: {}",
                title
            );

            let body = test::read_body(response).await;

            if title.ends_with(".txt") {
                assert!(
                    String::from_utf8_lossy(&body).contains(content),
                    "Indexed text upload content missing"
                );
            }
        }

        eprintln!("C13_PASTE_COMMITTED_TXT_AND_BIN_VISIBLE=true");
    }
}


#[cfg(test)]
mod c13_index_witness_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_paste_must_reject_invalid_index_witness() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route(
                    "/paste/{id}",
                    web::get().to(crate::handlers::get_paste)
                )
        ).await;

        let content = "C13_INVALID_WITNESS_PROBE";

        let upload = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-invalid-witness.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, upload).await;
        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        let id = result["id"].as_str().unwrap();

        // Tamper with the witness after successful indexing.
        let index_path = spool.join("index.jsonl");
        let original = fs::read_to_string(&index_path).unwrap();

        let mut entry: serde_json::Value =
            serde_json::from_str(original.trim()).unwrap();

        entry["witness"] = serde_json::json!("0".repeat(64));

        fs::write(
            &index_path,
            format!("{}\n", serde_json::to_string(&entry).unwrap())
        ).unwrap();

        let request = test::TestRequest::get()
            .uri(&format!("/paste/{}", id))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;

        let exposed =
            String::from_utf8_lossy(&body).contains(content);

        eprintln!("C13_INVALID_WITNESS_STATUS={}", status);
        eprintln!("C13_INVALID_WITNESS_EXPOSED={}", exposed);

        assert!(
            !exposed,
            "C13 VULNERABILITY: /paste trusts an invalid index witness"
        );
    }
}


#[cfg(test)]
mod c13_read_race_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};
    use std::path::Path;

    const ORIGINAL: &str = "C13_VERIFIED_ORIGINAL_CONTENT";
    const REPLACEMENT: &str = "C13_UNVERIFIED_REPLACEMENT_CONTENT";

    fn replace_after_verification(path: &Path) {
        let saved = path.with_extension("c13-original");

        fs::rename(path, &saved).unwrap();
        fs::write(path, REPLACEMENT).unwrap();

        eprintln!("C13_READ_SUBSTITUTION_INJECTED");
    }

    #[actix_web::test]
    async fn c13_verified_bytes_survive_path_replacement() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route(
                    "/paste/{id}",
                    web::get().to(crate::handlers::get_paste)
                )
        ).await;

        let upload = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-read-race.txt",
                "content": ORIGINAL
            }))
            .to_request();

        let response = test::call_service(&app, upload).await;
        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        let id = result["id"].as_str().unwrap();

        crate::handlers::c13_read_race_probe::set(
            Some(replace_after_verification)
        );

        let request = test::TestRequest::get()
            .uri(&format!("/paste/{}", id))
            .to_request();

        let response = test::call_service(&app, request).await;

        crate::handlers::c13_read_race_probe::set(None);

        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        let html = String::from_utf8_lossy(&body);

        let original_visible = html.contains(ORIGINAL);
        let replacement_visible = html.contains(REPLACEMENT);

        eprintln!("C13_VERIFIED_CONTENT_VISIBLE={}", original_visible);
        eprintln!("C13_UNVERIFIED_CONTENT_VISIBLE={}", replacement_visible);

        assert!(original_visible, "Verified content disappeared");
        assert!(
            !replacement_visible,
            "C13 TOCTOU: unverified replacement was served"
        );
    }
}


#[cfg(test)]
mod c13_private_staging_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};
    use std::io::Write;

    #[actix_web::test]
    async fn c13_private_stage_remains_invisible_until_indexed() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("public-spool");
        let staging = tmp.path().join("private-staging");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&staging).unwrap();

        env::set_var("UUCP_SPOOL", &spool);

        let filename = "c13-stage-gate.txt";
        let content = b"C13_PRIVATE_STAGING_PROBE";

        let mut staged =
            tempfile::NamedTempFile::new_in(&staging).unwrap();

        staged.write_all(content).unwrap();
        staged.as_file_mut().sync_all().unwrap();

        let app = test::init_service(
            App::new().route(
                "/file/{id}",
                web::get().to(crate::handlers::get_file)
            )
        ).await;

        let request = test::TestRequest::get()
            .uri(&format!("/file/{}", filename))
            .to_request();

        let response = test::call_service(&app, request).await;

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        eprintln!("C13_PRIVATE_STAGE_INVISIBLE=true");

        // Simulate publishing the staged object without an index commit.
        let destination = spool.join(filename);
        staged.persist_noclobber(&destination).unwrap();

        let request = test::TestRequest::get()
            .uri(&format!("/file/{}", filename))
            .to_request();

        let response = test::call_service(&app, request).await;

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        eprintln!("C13_UNINDEXED_PUBLISHED_OBJECT_INVISIBLE=true");
    }
}


#[cfg(test)]
mod c13_alias_commit_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_alias_publication_failure_must_not_report_success() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_ALIAS_COMMIT_FAILURE";
        let hash = Sha256::digest(content.as_bytes());
        let cid = format!("bafk{}", hex::encode(&hash[..16]));
        let alias = spool.join(format!("{}.cid", cid));

        // Simulate an unusable preexisting alias.
        fs::create_dir(&alias).unwrap();

        let app = test::init_service(
            App::new().route(
                "/upload",
                web::post().to(upload_file)
            )
        ).await;

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-alias-commit.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;

        eprintln!("C13_ALIAS_COMMIT_HTTP_STATUS={}", status);

        assert!(
            alias.is_dir(),
            "Existing alias object was overwritten"
        );

        assert_ne!(
            status,
            StatusCode::OK,
            "C13 VULNERABILITY: upload reported success with unusable CID alias"
        );
    }
}


#[cfg(test)]
mod c13_partial_commit_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_alias_failure_must_not_leave_committed_index() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_PARTIAL_COMMIT_UNIQUE_PAYLOAD";
        let hash = Sha256::digest(content.as_bytes());
        let cid = format!("bafk{}", hex::encode(&hash[..16]));
        let alias = spool.join(format!("{}.cid", cid));

        // Make CID alias publication fail after indexing.
        fs::create_dir(&alias).unwrap();

        let app = test::init_service(
            App::new().route(
                "/upload",
                web::post().to(upload_file)
            )
        ).await;

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-partial-commit.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();

        let body = test::read_body(response).await;
        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);

        assert!(
            result["error"].as_str().unwrap_or("")
                .starts_with("CID alias publication failed:"),
            "Unexpected error branch: {}",
            result
        );

        eprintln!("C13_ALIAS_FAILURE_CONFIRMED");

        let index_path = spool.join("index.jsonl");
        let index = fs::read_to_string(&index_path)
            .unwrap_or_default();

        let matching: Vec<serde_json::Value> = index
            .lines()
            .filter_map(|line| {
                serde_json::from_str::<serde_json::Value>(line).ok()
            })
            .filter(|entry| {
                entry["cid"].as_str() == Some(cid.as_str())
                    && entry["witness"].as_str()
                        == Some(hex::encode(&hash).as_str())
            })
            .collect();

        eprintln!(
            "C13_FAILED_UPLOAD_INDEX_ENTRIES={}",
            matching.len()
        );

        let spool_count = fs::read_dir(&spool)
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
            .count();

        eprintln!("C13_FAILED_UPLOAD_SPOOL_FILES={}", spool_count);

        assert!(
            matching.is_empty(),
            "C13 PARTIAL COMMIT: failed upload remains indexed"
        );
    }
}


#[cfg(test)]
mod c13_failed_alias_visibility_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_failed_alias_commit_must_not_be_http_visible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_FAILED_ALIAS_VISIBILITY";
        let hash = Sha256::digest(content.as_bytes());
        let cid = format!("bafk{}", hex::encode(&hash[..16]));

        // Force alias publication failure after indexing.
        fs::create_dir(spool.join(format!("{}.cid", cid))).unwrap();

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}",
                    web::get().to(crate::handlers::get_file))
        ).await;

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-failed-alias.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        assert_eq!(
            response.status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );

        let body = test::read_body(response).await;
        let error: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert!(
            error["error"].as_str().unwrap_or("")
                .starts_with("CID alias publication failed:"),
            "Wrong failure branch: {}",
            error
        );

        eprintln!("C13_ALIAS_FAILURE_CONFIRMED");

        let index = fs::read_to_string(
            spool.join("index.jsonl")
        ).unwrap();

        let records: Vec<serde_json::Value> = index.lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .filter(|v: &serde_json::Value| {
                v["cid"].as_str() == Some(cid.as_str())
            })
            .collect();

        assert_eq!(records.len(), 1,
            "Expected one partial-commit index record");

        let filename = records[0]["filename"]
            .as_str().unwrap();

        let request = test::TestRequest::get()
            .uri(&format!("/file/{}", filename))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;

        let exposed = status == StatusCode::OK
            && body.as_ref() == content.as_bytes();

        eprintln!("C13_PARTIAL_COMMIT_HTTP_STATUS={}", status);
        eprintln!("C13_PARTIAL_COMMIT_EXPOSED={}", exposed);

        assert!(
            !exposed,
            "C13 PARTIAL COMMIT: failed upload exposed via /file"
        );

        assert_eq!(
            status, StatusCode::NOT_FOUND,
            "Failed transaction must not be HTTP-visible"
        );
    }
}


#[cfg(test)]
mod c13_all_routes_commit_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_failed_transaction_hidden_on_all_three_routes() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_ALL_ROUTES_FAILED_COMMIT_PROBE";
        let hash = Sha256::digest(content.as_bytes());
        let cid = format!("bafk{}", hex::encode(&hash[..16]));

        // Force alias failure after index append.
        let alias = spool.join(format!("{}.cid", cid));
        fs::create_dir(&alias).unwrap();

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}",
                    web::get().to(crate::handlers::get_file))
                .route("/paste/{id}",
                    web::get().to(crate::handlers::get_paste))
                .route("/raw/{id}",
                    web::get().to(crate::handlers::get_raw))
        ).await;

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-all-routes.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        assert_eq!(
            response.status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );

        let body = test::read_body(response).await;
        let error: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert!(
            error["error"].as_str().unwrap_or("")
                .starts_with("CID alias publication failed:"),
            "Wrong failure branch: {}", error
        );

        let index = fs::read_to_string(
            spool.join("index.jsonl")
        ).unwrap();

        let matching: Vec<serde_json::Value> = index.lines()
            .filter_map(|line| serde_json::from_str(line).ok())
            .filter(|entry: &serde_json::Value| {
                entry["cid"].as_str() == Some(cid.as_str())
            })
            .collect();

        assert_eq!(
            matching.len(), 1,
            "Expected exactly one partially indexed upload"
        );

        let id = matching[0]["id"].as_str().unwrap();
        let filename = matching[0]["filename"].as_str().unwrap();

        assert!(
            !spool.join(format!("{}.c13-committed", id)).exists(),
            "Unexpected commit marker on failed upload"
        );

        for (route, uri) in [
            ("FILE", format!("/file/{}", filename)),
            ("PASTE", format!("/paste/{}", id)),
            ("RAW", format!("/raw/{}", id)),
        ] {
            let request = test::TestRequest::get()
                .uri(&uri)
                .to_request();

            let response = test::call_service(&app, request).await;
            let status = response.status();
            let body = test::read_body(response).await;

            let exposed = String::from_utf8_lossy(&body)
                .contains(content);

            eprintln!(
                "C13_FAILED_COMMIT_{}_STATUS={}",
                route, status
            );
            eprintln!(
                "C13_FAILED_COMMIT_{}_EXPOSED={}",
                route, exposed
            );

            assert_eq!(
                status,
                StatusCode::NOT_FOUND,
                "Failed transaction accessible through {}", route
            );
            assert!(
                !exposed,
                "Failed transaction content exposed through {}", route
            );
        }
    }
}


#[cfg(test)]
mod c13_post_marker_failure_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_post_marker_failure_must_not_expose_failed_upload() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_POST_MARKER_FAILURE_PAYLOAD";

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}", web::get().to(crate::handlers::get_file))
                .route("/paste/{id}", web::get().to(crate::handlers::get_paste))
                .route("/raw/{id}", web::get().to(crate::handlers::get_raw))
        ).await;

        crate::handlers::c13_commit_fault_probe::enable();

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-post-marker-failure.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;
        let result: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        eprintln!("C13_POST_MARKER_UPLOAD_STATUS={}", status);

        assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(
            result["error"].as_str().unwrap_or("")
                .starts_with("commit publication failed:"),
            "Wrong failure branch: {}", result
        );

        let index = fs::read_to_string(spool.join("index.jsonl")).unwrap();
        let entries: Vec<serde_json::Value> = index.lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();

        assert_eq!(entries.len(), 1);
        let id = entries[0]["id"].as_str().unwrap();
        let filename = entries[0]["filename"].as_str().unwrap();

        let marker_exists =
            spool.join(format!("{}.c13-committed", id)).exists();

        eprintln!("C13_POST_MARKER_VISIBLE={}", marker_exists);
        assert!(marker_exists, "Fault injection did not publish marker");

        let mut exposed_any = false;

        for (route, uri) in [
            ("FILE", format!("/file/{}", filename)),
            ("PASTE", format!("/paste/{}", id)),
            ("RAW", format!("/raw/{}", id)),
        ] {
            let request = test::TestRequest::get()
                .uri(&uri)
                .to_request();

            let response = test::call_service(&app, request).await;
            let status = response.status();
            let body = test::read_body(response).await;

            let exposed = String::from_utf8_lossy(&body).contains(content);
            eprintln!("C13_POST_MARKER_{}_STATUS={}", route, status);
            eprintln!("C13_POST_MARKER_{}_EXPOSED={}", route, exposed);

            exposed_any |= exposed;
        }

        assert!(
            !exposed_any,
            "C13 PARTIAL COMMIT: HTTP 500 but marker authorizes content"
        );
    }
}


#[cfg(test)]
mod c13_uncertain_commit_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};

    #[actix_web::test]
    async fn c13_post_marker_failure_reports_uncertain_outcome() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");
        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new().route("/upload", web::post().to(upload_file))
        ).await;

        crate::handlers::c13_commit_fault_probe::enable();

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-uncertain-outcome.txt",
                "content": "C13_UNCERTAIN_OUTCOME_PROBE"
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        let body = test::read_body(response).await;
        let value: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        let id = value["id"].as_str().unwrap_or("");
        let marker_exists =
            spool.join(format!("{}.c13-committed", id)).exists();

        eprintln!("C13_UNCERTAIN_HTTP_STATUS={}", status);
        eprintln!("C13_UNCERTAIN_MARKER_VISIBLE={}", marker_exists);
        eprintln!("C13_UNCERTAIN_STATE={}", value["status"]);

        assert_eq!(status, StatusCode::ACCEPTED);
        assert_eq!(value["status"], "durability_uncertain");
        assert!(marker_exists);
    }
}


#[cfg(test)]
mod c13_uncertain_visibility_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_uncertain_transaction_must_remain_http_invisible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_UNCERTAIN_VISIBILITY_PAYLOAD";

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}", web::get().to(crate::handlers::get_file))
                .route("/paste/{id}", web::get().to(crate::handlers::get_paste))
                .route("/raw/{id}", web::get().to(crate::handlers::get_raw))
        ).await;

        crate::handlers::c13_commit_fault_probe::enable();

        let upload = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-uncertain-visibility.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, upload).await;
        assert_eq!(response.status(), StatusCode::ACCEPTED);

        let body = test::read_body(response).await;
        let value: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert_eq!(value["status"], "durability_uncertain");

        let id = value["id"].as_str().unwrap();
        let index = fs::read_to_string(spool.join("index.jsonl")).unwrap();
        let record: serde_json::Value =
            serde_json::from_str(index.trim()).unwrap();
        let filename = record["filename"].as_str().unwrap();

        assert_eq!(record["id"].as_str(), Some(id));

        let marker = spool.join(format!("{}.c13-committed", id));
        assert!(marker.exists());

        eprintln!("C13_UNCERTAIN_MARKER_PRESENT=true");

        let mut exposed_any = false;
        let mut unexpected_status = false;

        for (route, uri) in [
            ("FILE", format!("/file/{}", filename)),
            ("PASTE", format!("/paste/{}", id)),
            ("RAW", format!("/raw/{}", id)),
        ] {
            let request = test::TestRequest::get()
                .uri(&uri)
                .to_request();

            let response = test::call_service(&app, request).await;
            let status = response.status();
            let body = test::read_body(response).await;

            let exposed =
                String::from_utf8_lossy(&body).contains(content);

            eprintln!("C13_UNCERTAIN_{}_STATUS={}", route, status);
            eprintln!("C13_UNCERTAIN_{}_EXPOSED={}", route, exposed);

            exposed_any |= exposed;
            unexpected_status |= status != StatusCode::NOT_FOUND;
        }

        assert!(
            !exposed_any && !unexpected_status,
            "C13 VISIBILITY DEFECT: durability-uncertain transaction readable"
        );
    }
}

#[cfg(test)]
mod c13_post_seal_visibility_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_post_seal_failure_must_remain_http_invisible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_POST_SEAL_VISIBILITY_PAYLOAD";

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}", web::get().to(crate::handlers::get_file))
                .route("/paste/{id}", web::get().to(crate::handlers::get_paste))
                .route("/raw/{id}", web::get().to(crate::handlers::get_raw))
        ).await;

        crate::handlers::c13_seal_fault_probe::enable();

        let upload = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-uncertain-visibility.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, upload).await;
        assert_eq!(response.status(), StatusCode::ACCEPTED);

        let body = test::read_body(response).await;
        let value: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert_eq!(value["status"], "durability_uncertain");

        let id = value["id"].as_str().unwrap();
        let index = fs::read_to_string(spool.join("index.jsonl")).unwrap();
        let record: serde_json::Value =
            serde_json::from_str(index.trim()).unwrap();
        let filename = record["filename"].as_str().unwrap();

        assert_eq!(record["id"].as_str(), Some(id));

        let marker = spool.join(format!("{}.c13-committed", id));
        assert!(marker.exists());

        eprintln!("C13_POST_SEAL_MARKER_PRESENT=true");

        let mut exposed_any = false;
        let mut unexpected_status = false;

        for (route, uri) in [
            ("FILE", format!("/file/{}", filename)),
            ("PASTE", format!("/paste/{}", id)),
            ("RAW", format!("/raw/{}", id)),
        ] {
            let request = test::TestRequest::get()
                .uri(&uri)
                .to_request();

            let response = test::call_service(&app, request).await;
            let status = response.status();
            let body = test::read_body(response).await;

            let exposed =
                String::from_utf8_lossy(&body).contains(content);

            eprintln!("C13_POST_SEAL_{}_STATUS={}", route, status);
            eprintln!("C13_POST_SEAL_{}_EXPOSED={}", route, exposed);

            exposed_any |= exposed;
            unexpected_status |= status != StatusCode::NOT_FOUND;
        }

        assert!(
            !exposed_any && !unexpected_status,
            "C13 VISIBILITY DEFECT: durability-uncertain transaction readable"
        );
    }
}


#[cfg(test)]
mod c13_restart_visibility_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};
    use std::process::Command;

    #[actix_web::test]
    async fn c13_restart_child_reader() {
        let Ok(spool) = env::var("C13_RUST39_CHILD_SPOOL") else {
            return;
        };
        let filename = env::var("C13_RUST39_CHILD_FILENAME").unwrap();

        env::set_var("UUCP_SPOOL", spool);

        let app = test::init_service(
            App::new().route(
                "/file/{id}",
                web::get().to(crate::handlers::get_file)
            )
        ).await;

        let request = test::TestRequest::get()
            .uri(&format!("/file/{}", filename))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();

        eprintln!("C13_CHILD_READ_STATUS={}", status);

        // C13-RUST-58: select the expected restart visibility.
        let expected = if env::var_os("C13_RUST58_EXPECT_404").is_some() {
            StatusCode::NOT_FOUND
        } else {
            StatusCode::OK
        };

        assert_eq!(
            status,
            expected,
            "C13 restart visibility mismatch"
        );
    }

    #[actix_web::test]
    async fn c13_committed_upload_must_survive_new_process() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new().route("/upload", web::post().to(upload_file))
        ).await;

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-restart-check.txt",
                "content": "C13_RESTART_PERSISTENCE_PROBE"
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::OK);

        let body = test::read_body(response).await;
        let value: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        let filename = value["filename"].as_str().unwrap();

        let output = Command::new(std::env::current_exe().unwrap())
            .arg("--exact")
            .arg("upload_handler::c13_restart_visibility_tests::c13_restart_child_reader")
            .arg("--nocapture")
            .arg("--test-threads=1")
            .env("C13_RUST39_CHILD_SPOOL", &spool)
            .env("C13_RUST39_CHILD_FILENAME", filename)
            .output()
            .unwrap();

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);

        eprintln!("C13_CHILD_EXIT={:?}", output.status.code());
        eprintln!("C13_CHILD_STDOUT={}", stdout);
        eprintln!("C13_CHILD_STDERR={}", stderr);

        assert!(
            output.status.success(),
            "C13 RECOVERY DEFECT: committed upload unreadable in new process"
        );
    }
}


#[cfg(test)]
mod c13_sqlite_registry_tests {
    use rusqlite::{params, Connection, OptionalExtension};
    use std::path::Path;

    fn connect(path: &Path) -> rusqlite::Result<Connection> {
        let conn = Connection::open(path)?;
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=FULL;
             CREATE TABLE IF NOT EXISTS c13_transactions (
                 id TEXT PRIMARY KEY,
                 filename TEXT NOT NULL,
                 witness TEXT NOT NULL,
                 cid TEXT NOT NULL,
                 state TEXT NOT NULL
                     CHECK(state IN ('PREPARED','COMMITTED','UNCERTAIN'))
             );"
        )?;
        Ok(conn)
    }

    fn authorized(
        conn: &Connection,
        id: &str,
        filename: &str,
        witness: &str,
        cid: &str,
    ) -> rusqlite::Result<bool> {
        let state: Option<String> = conn.query_row(
            "SELECT state FROM c13_transactions
             WHERE id=?1 AND filename=?2 AND witness=?3 AND cid=?4",
            params![id, filename, witness, cid],
            |r| r.get(0),
        ).optional()?;
        Ok(state.as_deref() == Some("COMMITTED"))
    }

    #[test]
    fn c13_sqlite_registry_prepare_commit_authorization() -> rusqlite::Result<()> {
        let tmp = tempfile::tempdir().unwrap();
        let db = tmp.path().join("transactions.sqlite");

        let id = "c13-object";
        let filename = "c13-object.txt";
        let witness = "c13-test-witness";
        let cid = "c13-test-cid";

        {
            let writer = connect(&db)?;
            writer.execute(
                "INSERT INTO c13_transactions
                 (id,filename,witness,cid,state)
                 VALUES (?1,?2,?3,?4,'PREPARED')",
                params![id, filename, witness, cid],
            )?;
        }

        {
            let reader = connect(&db)?;
            let permitted = authorized(&reader, id, filename, witness, cid)?;
            eprintln!("C13_SQLITE_PREPARED_AUTHORIZED={}", permitted);
            assert!(!permitted);
        }

        {
            let writer = connect(&db)?;
            let changed = writer.execute(
                "UPDATE c13_transactions SET state='COMMITTED'
                 WHERE id=?1 AND filename=?2 AND witness=?3 AND cid=?4
                   AND state='PREPARED'",
                params![id, filename, witness, cid],
            )?;
            assert_eq!(changed, 1);
        }

        {
            let reader = connect(&db)?;
            let permitted = authorized(&reader, id, filename, witness, cid)?;
            let forged = authorized(
                &reader, id, filename, "forged-witness", cid
            )?;
            eprintln!("C13_SQLITE_COMMITTED_AUTHORIZED={}", permitted);
            eprintln!("C13_SQLITE_FORGED_WITNESS_AUTHORIZED={}", forged);
            assert!(permitted);
            assert!(!forged);
        }

        {
            let writer = connect(&db)?;
            let duplicate = writer.execute(
                "INSERT INTO c13_transactions
                 (id,filename,witness,cid,state)
                 VALUES (?1,?2,?3,?4,'PREPARED')",
                params![id, filename, witness, cid],
            );
            eprintln!("C13_SQLITE_DUPLICATE_REJECTED={}", duplicate.is_err());
            assert!(duplicate.is_err());
        }

        Ok(())
    }
}

#[cfg(test)]
mod c13_post_sqlite_commit_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_post_sqlite_commit_error_must_not_report_uncertain_visible() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_POST_SQLITE_VISIBILITY_PAYLOAD";

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}", web::get().to(crate::handlers::get_file))
                .route("/paste/{id}", web::get().to(crate::handlers::get_paste))
                .route("/raw/{id}", web::get().to(crate::handlers::get_raw))
        ).await;

        crate::handlers::c13_sqlite_commit_fault_probe::enable();

        let upload = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-uncertain-visibility.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, upload).await;
        assert_eq!(response.status(), StatusCode::ACCEPTED);

        let body = test::read_body(response).await;
        let value: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        assert_eq!(value["status"], "durability_uncertain");

        let id = value["id"].as_str().unwrap();
        let index = fs::read_to_string(spool.join("index.jsonl")).unwrap();
        let record: serde_json::Value =
            serde_json::from_str(index.trim()).unwrap();
        let filename = record["filename"].as_str().unwrap();

        assert_eq!(record["id"].as_str(), Some(id));

        let marker = spool.join(format!("{}.c13-committed", id));
        assert!(marker.exists());

        eprintln!("C13_POST_SQLITE_MARKER_PRESENT=true");

        let mut exposed_any = false;
        let mut unexpected_status = false;

        for (route, uri) in [
            ("FILE", format!("/file/{}", filename)),
            ("PASTE", format!("/paste/{}", id)),
            ("RAW", format!("/raw/{}", id)),
        ] {
            let request = test::TestRequest::get()
                .uri(&uri)
                .to_request();

            let response = test::call_service(&app, request).await;
            let status = response.status();
            let body = test::read_body(response).await;

            let exposed =
                String::from_utf8_lossy(&body).contains(content);

            eprintln!("C13_POST_SQLITE_{}_STATUS={}", route, status);
            eprintln!("C13_POST_SQLITE_{}_EXPOSED={}", route, exposed);

            exposed_any |= exposed;
            unexpected_status |= status != StatusCode::NOT_FOUND;
        }

        assert!(
            !exposed_any && !unexpected_status,
            "C13 VISIBILITY DEFECT: durability-uncertain transaction readable"
        );
    }
}


#[cfg(test)]
mod c13_sqlite_ack_recovery_tests {
    use super::*;
    use actix_web::{test, App, http::StatusCode};
    use std::process::Command;

    #[actix_web::test]
    async fn c13_lost_sqlite_ack_reconciles_across_processes() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}",
                    web::get().to(crate::handlers::get_file))
        ).await;

        crate::handlers::c13_sqlite_commit_fault_probe::enable();

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-lost-ack.txt",
                "content": "C13_LOST_ACK_RECOVERY_PAYLOAD"
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        let status = response.status();
        eprintln!("C13_RECONCILED_UPLOAD_STATUS={}", status);

        assert_eq!(status, StatusCode::OK);

        let body = test::read_body(response).await;
        let value: serde_json::Value =
            serde_json::from_slice(&body).unwrap();

        let filename = value["filename"].as_str().unwrap();

        let output = Command::new(std::env::current_exe().unwrap())
            .arg("--exact")
            .arg("upload_handler::c13_restart_visibility_tests::c13_restart_child_reader")
            .arg("--nocapture")
            .arg("--test-threads=1")
            .env("C13_RUST39_CHILD_SPOOL", &spool)
            .env("C13_RUST39_CHILD_FILENAME", filename)
            .output()
            .unwrap();

        let child_output = format!(
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );

        eprintln!("C13_RECONCILED_CHILD_EXIT={:?}",
            output.status.code());
        eprintln!("C13_RECONCILED_CHILD_OUTPUT={}",
            child_output);

        assert!(output.status.success());
        assert!(child_output.contains("C13_CHILD_READ_STATUS=200 OK"));
    }
}

#[cfg(test)]
mod c13_prepared_failure_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};
    use rusqlite::{Connection, params};

    #[actix_web::test]
    async fn c13_alias_failure_remains_prepared_and_hidden() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = tmp.path().join("spool");
        let ipfs = tmp.path().join("ipfs");

        fs::create_dir_all(&spool).unwrap();
        fs::create_dir_all(&ipfs).unwrap();

        env::set_var("UUCP_SPOOL", &spool);
        env::set_var("IPFS_PATH", &ipfs);

        let content = "C13_PREPARED_FAILURE_PROBE";
        let hash = Sha256::digest(content.as_bytes());
        let cid = format!("bafk{}", hex::encode(&hash[..16]));

        // Induce a CID alias failure after SQLite PREPARED and indexing.
        let alias = spool.join(format!("{}.cid", cid));
        fs::create_dir(&alias).unwrap();

        let app = test::init_service(
            App::new()
                .route("/upload", web::post().to(upload_file))
                .route("/file/{id}",
                    web::get().to(crate::handlers::get_file))
                .route("/paste/{id}",
                    web::get().to(crate::handlers::get_paste))
                .route("/raw/{id}",
                    web::get().to(crate::handlers::get_raw))
        ).await;

        let request = test::TestRequest::post()
            .uri("/upload")
            .set_json(serde_json::json!({
                "title": "c13-prepared-failure.txt",
                "content": content
            }))
            .to_request();

        let response = test::call_service(&app, request).await;
        assert_eq!(
            response.status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );

        let response_body = test::read_body(response).await;
        let error: serde_json::Value =
            serde_json::from_slice(&response_body).unwrap();

        assert!(
            error["error"].as_str().unwrap_or("")
                .starts_with("CID alias publication failed:"),
            "Unexpected failure branch: {}", error
        );

        let index = fs::read_to_string(
            spool.join("index.jsonl")
        ).unwrap();

        let matches: Vec<serde_json::Value> = index.lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .filter(|entry: &serde_json::Value| {
                entry["cid"].as_str() == Some(cid.as_str())
            })
            .collect();

        assert_eq!(matches.len(), 1);

        let id = matches[0]["id"].as_str().unwrap();
        let filename = matches[0]["filename"].as_str().unwrap();
        let witness = matches[0]["witness"].as_str().unwrap();

        let conn = Connection::open(
            spool.join(".c13-transactions.sqlite")
        ).unwrap();

        let state: String = conn.query_row(
            "SELECT state FROM c13_transactions
             WHERE id=?1 AND filename=?2 AND witness=?3 AND cid=?4",
            params![id, filename, witness, cid],
            |row| row.get(0),
        ).unwrap();

        eprintln!("C13_FAILED_ALIAS_SQLITE_STATE={}", state);

        assert_eq!(
            state, "PREPARED",
            "Failed upload must not be committed"
        );

        for (route, uri) in [
            ("FILE", format!("/file/{}", filename)),
            ("PASTE", format!("/paste/{}", id)),
            ("RAW", format!("/raw/{}", id)),
        ] {
            let request = test::TestRequest::get()
                .uri(&uri).to_request();

            let response = test::call_service(&app, request).await;
            let status = response.status();
            let body = test::read_body(response).await;

            let exposed =
                String::from_utf8_lossy(&body).contains(content);

            eprintln!("C13_PREPARED_{}_STATUS={}", route, status);
            eprintln!("C13_PREPARED_{}_EXPOSED={}", route, exposed);

            assert_eq!(status, StatusCode::NOT_FOUND);
            assert!(!exposed);
        }
    }
}


#[cfg(test)]
mod c13_rust59_restart_routes_tests {
    use super::*;
    use actix_web::{http::StatusCode, test, App};

    #[actix_web::test]
    async fn c13_prepared_restart_paste_raw_must_be_hidden() {
        let spool = std::env::var("C13_RUST59_SPOOL").unwrap();
        let id = std::env::var("C13_RUST59_ID").unwrap();

        std::env::set_var("UUCP_SPOOL", spool);

        let app = test::init_service(
            App::new()
                .route(
                    "/paste/{id}",
                    web::get().to(crate::handlers::get_paste)
                )
                .route(
                    "/raw/{id}",
                    web::get().to(crate::handlers::get_raw)
                )
        ).await;

        for (label, uri) in [
            ("PASTE", format!("/paste/{}", id)),
            ("RAW", format!("/raw/{}", id)),
        ] {
            let request = test::TestRequest::get()
                .uri(&uri)
                .to_request();

            let response = test::call_service(&app, request).await;
            let status = response.status();

            eprintln!("C13_RUST59_{}_STATUS={}", label, status);

            assert_eq!(
                status,
                StatusCode::NOT_FOUND,
                "PREPARED transaction exposed after restart"
            );
        }
    }
}
