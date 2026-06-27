// SVG animation — async: writes job file for svg2anim-worker systemd service.
use actix_web::{web, HttpResponse, Result};
use log::{error, info};
use std::{env, fs, path::Path};

/// POST /svg2anim/{id} — submit SVG for animation (async, worker processes)
pub async fn svg2anim(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let jobs_dir = format!("{}/svg2anim-jobs", uucp_dir);

    // Verify SVG exists
    let svg_dir = Path::new(&uucp_dir);
    let found = svg_dir.read_dir().ok().map_or(false, |entries| {
        entries.filter_map(|e| e.ok()).any(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            let stem = name.rsplit_once('.').map(|(s,_)| s).unwrap_or(&name).to_string();
            stem == id && e.path().extension() == Some(std::ffi::OsStr::new("svg"))
        })
    });

    if !found {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({"error": "SVG not found"})));
    }

    // Create jobs directory and write job file
    fs::create_dir_all(&jobs_dir).map_err(|e| {
        error!("[svg2anim] mkdir: {}", e);
        actix_web::error::ErrorInternalServerError(e)
    })?;

    let job_path = format!("{}/{}", jobs_dir, id);
    if let Err(e) = fs::write(&job_path, "") {
        error!("[svg2anim] write job: {}", e);
        return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": "failed to submit job"})));
    }

    info!("[svg2anim] Job submitted: {} (wait for svg2anim-worker)", id);

    Ok(HttpResponse::Accepted().json(serde_json::json!({
        "status": "submitted",
        "id": id,
        "message": "Animation job submitted. The svg2anim-worker service will process it shortly.",
        "job_file": job_path,
    })))
}
