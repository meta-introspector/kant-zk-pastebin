// SVG animation — async: writes job file for svg2anim-worker systemd service.
use actix_web::{web, HttpResponse, Result};
use log::{error, info};
use std::{env, fs, path::Path};


/// POST /svg2anim/{id} -- submit SVG for animation (async, worker processes)
///
/// The `id` may be either:
///   - The full filename stem (e.g. `20260710_191143_download_svg`)
///   - A short UUID fragment (e.g. `3654b8d7_2246_4a39_ba36_bf19d80174ee`)
///
/// We mirror `get_file`'s two-pass lookup:
///   1. Exact stem match: `stem == id`
///   2. Suffix match:     `stem.ends_with(&format!("_{}", id))`
/// The resolved full stem is written into the job file so the worker
/// can find the SVG without re-doing the lookup.
pub async fn svg2anim(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let jobs_dir = format!("{}/svg2anim-jobs", uucp_dir);

    // Verify SVG exists (mirrors get_file lookup in handlers.rs)
    let svg_dir = Path::new(&uucp_dir);
    let svg_path = svg_dir.read_dir().ok().and_then(|entries| {
        entries.filter_map(|e| e.ok()).find(|e| {
            if e.path().extension() != Some(std::ffi::OsStr::new("svg")) {
                return false;
            }
            let name = e.file_name().to_string_lossy().to_string();
            let stem = name.rsplit_once('.').map(|(s,_)| s).unwrap_or(&name).to_string();
            stem == id || stem.ends_with(&format!("_{}", id))
        })
    });

    let Some(svg_entry) = svg_path else {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({"error": "SVG not found"})));
    };

    // Resolve the actual paste id (full filename stem) for the worker
    let svg_name = svg_entry.file_name().to_string_lossy().to_string();
    let resolved_id = svg_name.rsplit_once('.').map(|(s,_)| s).unwrap_or(&svg_name).to_string();

    // Create jobs directory and write job file
    fs::create_dir_all(&jobs_dir).map_err(|e| {
        error!("[svg2anim] mkdir: {}", e);
        actix_web::error::ErrorInternalServerError(e)
    })?;

    let job_path = format!("{}/{}", jobs_dir, resolved_id);
    if let Err(e) = fs::write(&job_path, "") {
        error!("[svg2anim] write job: {}", e);
        return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": "failed to submit job"})));
    }

    info!("[svg2anim] Job submitted: {} (wait for svg2anim-worker)", resolved_id);

    Ok(HttpResponse::Accepted().json(serde_json::json!({
        "status": "submitted",
        "id": resolved_id,
        "message": "Animation job submitted. The svg2anim-worker service will process it shortly.",
        "job_file": job_path,
    })))
}
