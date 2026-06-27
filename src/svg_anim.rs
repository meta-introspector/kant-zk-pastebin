// SVG animation — calls external svg2anim binary to generate animated GIF.
use actix_web::{web, HttpResponse, Result};
use chrono::Utc;
use log::{error, info, warn};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::process::Command;
use std::{env, fs, path::PathBuf};

/// POST /svg2anim/{id} — generate animated GIF from uploaded SVG
pub async fn svg2anim(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let svg2anim = env::var("SVG2ANIM_BIN").unwrap_or_else(|_| {
        "/home/mdupont/2026/06/26/svg2anim/target/release/svg2anim".to_string()
    });

    let svg_path = find_svg(&uucp_dir, &id).ok_or_else(|| {
        actix_web::error::ErrorNotFound("SVG not found")
    })?;

    info!("[svg2anim] Generating animation from: {}", svg_path.display());

    // Get SVG dimensions using resvg CLI for aspect-ratio-correct output
    let dims = get_svg_dimensions(&svg_path)?;

    // Generate a simple animation by rendering the SVG at different rotation angles
    // We use a temp directory with multiple copies and use svg2anim on them
    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let tmp_dir = format!("/tmp/svg2anim_{}", ts);
    fs::create_dir_all(&tmp_dir).map_err(|e| {
        error!("[svg2anim] mkdir: {}", e);
        actix_web::error::ErrorInternalServerError(e)
    })?;

    // Create multiple SVG files with different transforms via sed manipulation
    // For a subtle animation: scale pulse + rotation
    let mut frame_svgs: Vec<PathBuf> = Vec::new();
    let num_frames = 16;

    for i in 0..num_frames {
        let angle = i as f64 * 360.0 / num_frames as f64;
        let scale = 1.0 + 0.05 * (i as f64 * 2.0 * std::f64::consts::PI / num_frames as f64).sin();
        let frame_path = format!("{}/frame_{:02}.svg", tmp_dir, i);

        // Read the original SVG and add a transform group
        let svg_content = fs::read_to_string(&svg_path).map_err(|e| {
            error!("[svg2anim] read: {}", e);
            actix_web::error::ErrorInternalServerError(e)
        })?;

        // Inject a transform into the first <svg> tag
        let transformed = if let Some(pos) = svg_content.find("<svg") {
            let after_tag = &svg_content[pos..];
            if let Some(gt) = after_tag.find('>') {
                let before = &svg_content[..pos + gt + 1];
                let after = &svg_content[pos + gt + 1..];
                format!(
                    r##"{}<g transform="translate({cx},{cy}) rotate({angle}) scale({scale}) translate({ncx},{ncy})">{}</g>"##,
                    before,
                    after,
                    cx = dims.0 as f64 / 2.0,
                    cy = dims.1 as f64 / 2.0,
                    angle = angle,
                    scale = scale,
                    ncx = -(dims.0 as f64) / 2.0,
                    ncy = -(dims.1 as f64) / 2.0,
                )
            } else {
                svg_content.clone()
            }
        } else {
            svg_content.clone()
        };

        fs::write(&frame_path, &transformed).map_err(|e| {
            error!("[svg2anim] write frame: {}", e);
            actix_web::error::ErrorInternalServerError(e)
        })?;
        frame_svgs.push(frame_path.into());
    }

    let out_gif = format!("/tmp/anim_out_{}.gif", ts);

    // Call svg2anim with all frame files
    info!("[svg2anim] Running: {} {} frames -> {}", svg2anim, num_frames, out_gif);
    let mut cmd = Command::new(&svg2anim);
    cmd.arg("-o").arg(&out_gif);
    cmd.arg("-W").arg(&dims.0.to_string());
    cmd.arg("-H").arg(&dims.1.to_string());
    cmd.arg("-d").arg("100"); // 100ms per frame
    for f in &frame_svgs {
        cmd.arg(f);
    }

    let output = cmd.output().map_err(|e| {
        error!("[svg2anim] execute: {}", e);
        actix_web::error::ErrorInternalServerError(e)
    })?;

    // Clean up temp files
    fs::remove_dir_all(&tmp_dir).ok();

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        warn!("[svg2anim] svg2anim failed: {}", stderr);
        return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": format!("svg2anim failed: {}", stderr)})));
    }

    let gif_data = fs::read(&out_gif).map_err(|e| {
        error!("[svg2anim] read output: {}", e);
        actix_web::error::ErrorInternalServerError(e)
    })?;
    let gif_size = gif_data.len();

    // Save to pastebin spool
    let safe_id = id.replace('.', "_");
    let gif_filename = format!("{}_{}.gif", ts, safe_id);
    let gif_path = format!("{}/{}", uucp_dir, gif_filename);
    fs::write(&gif_path, &gif_data).map_err(|e| {
        error!("[svg2anim] save: {}", e);
        actix_web::error::ErrorInternalServerError(e)
    })?;

    let mut hasher = Sha256::new();
    hasher.update(&gif_data);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);
    let gif_id = gif_filename.rsplit_once('.').map(|(s, _)| s).unwrap_or(&gif_filename).to_string();

    let entry = serde_json::json!({
        "id": gif_id,
        "title": format!("{} (animated)", id),
        "description": format!("Animated GIF from SVG ({} frames {}x{})", num_frames, dims.0, dims.1),
        "keywords": ["svg", "animation", "gif"],
        "cid": local_cid, "witness": witness,
        "timestamp": ts, "filename": gif_filename,
        "size": gif_size,
        "ipfs_cid": null, "reply_to": null, "root": null, "uucp_path": gif_path,
    });

    let idx = format!("{}/index.jsonl", uucp_dir);
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(&idx) {
        writeln!(f, "{}", serde_json::to_string(&entry).unwrap()).ok();
    }

    fs::remove_file(&out_gif).ok();
    info!("[svg2anim] Done: {} ({} bytes)", gif_id, gif_size);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": gif_id,
        "title": format!("{} (animated)", id),
        "mime": "image/gif",
        "size": gif_size,
        "frames": num_frames,
        "width": dims.0, "height": dims.1,
        "url": format!("/paste/{}", gif_id),
    })))
}

fn find_svg(uucp_dir: &str, id: &str) -> Option<PathBuf> {
    fs::read_dir(uucp_dir).ok().and_then(|entries| {
        entries.filter_map(|e| e.ok()).find(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            e.path().extension().map(|x| x == "svg").unwrap_or(false)
                && name.rsplit_once('.').map(|(s, _)| s).unwrap_or(&name) == id
        }).map(|e| e.path())
    })
}

fn get_svg_dimensions(path: &PathBuf) -> Result<(u32, u32), actix_web::Error> {
    let content = fs::read_to_string(path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
    // Try to extract viewBox or width/height from SVG
    if let Some(vb) = content.find("viewBox=\"") {
        let rest = &content[vb + 9..];
        if let Some(end) = rest.find('"') {
            let parts: Vec<&str> = rest[..end].split_whitespace().collect();
            if parts.len() >= 4 {
                if let (Ok(w), Ok(h)) = (parts[2].parse::<f64>(), parts[3].parse::<f64>()) {
                    let w = (w as u32).min(800).max(100);
                    let h = (h as u32).min(800).max(100);
                    return Ok((w, h));
                }
            }
        }
    }
    // Fallback: try width/height attributes
    if let Some(w) = extract_attr(&content, "width") {
        if let Some(h) = extract_attr(&content, "height") {
            let w = (w as u32).min(800).max(100);
            let h = (h as u32).min(800).max(100);
            return Ok((w, h));
        }
    }
    Ok((400, 400)) // Default fallback
}

fn extract_attr(content: &str, attr: &str) -> Option<f64> {
    let pat = format!(r#"{}="""#, attr);
    if let Some(pos) = content.find(&pat) {
        let rest = &content[pos + pat.len()..];
        if let Some(end) = rest.find('"') {
            let val: String = rest[..end].chars().filter(|c| c.is_digit(10) || *c == '.').collect();
            return val.parse::<f64>().ok();
        }
    }
    None
}
