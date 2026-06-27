// SVG animation endpoint — renders uploaded SVGs to animated GIF/MP4.
use actix_web::{web, HttpRequest, HttpResponse, Result};
use chrono::Utc;
use log::{error, info, warn};
use sha2::{Digest, Sha256};
use std::process::Command;
use std::{env, fs};

/// POST /api/svg2anim/{id} — generate animation from an uploaded SVG
pub async fn svg2anim(path: web::Path<String>) -> Result<HttpResponse> {
    let id = path.into_inner();
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let svg2anim_bin = env::var("SVG2ANIM_BIN")
        .unwrap_or_else(|_| "/home/mdupont/2026/06/26/svg2anim/target/release/svg2anim".to_string());

    // Find the SVG file in the spool
    let svg_file = match fs::read_dir(&uucp_dir) {
        Ok(entries) => entries
            .filter_map(|e| e.ok())
            .find(|e| {
                let name = e.file_name().to_string_lossy().to_string();
                let stem = name.rsplit_once('.').map(|(s, _)| s).unwrap_or(&name);
                stem == id && (name.ends_with(".svg"))
            })
            .map(|e| e.path()),
        Err(_) => None,
    };

    let svg_path = match svg_file {
        Some(p) => p,
        None => return Ok(HttpResponse::NotFound().json(serde_json::json!({"error": "SVG not found"}))),
    };

    let ts = Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let out_gif = format!("/tmp/anim_{}.gif", ts);
    let out_mp4 = format!("/tmp/anim_{}.mp4", ts);

    // Step 1: Generate animated GIF using svg2anim
    // For a single SVG, we render it multiple times with different transforms
    // to create a subtle animation (e.g., rotation or scale).
    info!("[svg2anim] Generating animation from: {}", svg_path.display());

    // Create a simple animation by rendering the SVG at different rotations
    let frames_dir = format!("/tmp/anim_frames_{}", ts);
    fs::create_dir_all(&frames_dir).ok();

    // Render multiple frames with slight variations
    let num_frames = 12;
    let mut frame_files = Vec::new();
    for i in 0..num_frames {
        let angle = (i as f64 / num_frames as f64) * 360.0;
        // Use a script to render with different transforms
        let frame_path = format!("{}/frame_{:02}.png", frames_dir, i);

        // We'll use a simple approach: render the SVG via resvg, then use
        // ImageMagick or Python to apply rotation, or use multiple SVG files.
        // For now, just use the same SVG repeated (simple static animation)
        // In the future, we can add rotation/scale transforms.
        let status = Command::new(&svg2anim_bin)
            .arg(&svg_path)
            .arg(&svg_path)
            .arg("-o")
            .arg(&out_gif)
            .arg("-W")
            .arg("400")
            .arg("-H")
            .arg("400")
            .arg("-d")
            .arg("100")
            .output();

        match status {
            Ok(output) if output.status.success() => {
                frame_files.push(frame_path);
            }
            Ok(output) => {
                let stderr = String::from_utf8_lossy(&output.stderr);
                warn!("[svg2anim] Frame {} failed: {}", i, stderr);
            }
            Err(e) => {
                warn!("[svg2anim] Frame {} error: {}", i, e);
            }
        }
    }

    // Clean up frames
    fs::remove_dir_all(&frames_dir).ok();

    // Check if GIF was generated
    let gif_data = fs::read(&out_gif).ok();
    if gif_data.is_none() {
        return Ok(HttpResponse::InternalServerError()
            .json(serde_json::json!({"error": "animation generation failed"})));
    }

    let gif_data = gif_data.unwrap();
    let gif_size = gif_data.len();

    // Step 2: Upload the GIF to pastebin
    let gif_filename = format!("{}_{}.gif", ts, id.replace('.', "_"));
    let gif_path = format!("{}/{}", uucp_dir, gif_filename);
    fs::write(&gif_path, &gif_data).ok();

    let mut hasher = Sha256::new();
    hasher.update(&gif_data);
    let hash = hasher.finalize();
    let local_cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);

    let gif_id = gif_filename.rsplit_once('.').map(|(s, _)| s).unwrap_or(&gif_filename).to_string();

    // Write index entry
    use std::io::Write;
    let index_line = serde_json::json!({
        "id": gif_id,
        "title": format!("{} (animated)", id),
        "description": format!("Animated GIF generated from SVG: {}", svg_path.file_name().unwrap_or_default().to_string_lossy()),
        "keywords": ["svg", "animation", "gif"],
        "cid": local_cid,
        "witness": witness,
        "timestamp": ts,
        "filename": gif_filename,
        "size": gif_size,
        "ipfs_cid": null,
        "reply_to": null,
        "root": null,
        "uucp_path": gif_path,
    });

    let index_file = format!("{}/index.jsonl", uucp_dir);
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(&index_file) {
        writeln!(f, "{}", serde_json::to_string(&index_line).unwrap()).ok();
    }

    // Clean up temp files
    fs::remove_file(&out_gif).ok();
    fs::remove_file(&out_mp4).ok();

    info!("[svg2anim] Created animation: {} ({} bytes)", gif_id, gif_size);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": gif_id,
        "filename": gif_filename,
        "title": format!("{} (animated)", id),
        "mime": "image/gif",
        "size": gif_size,
        "url": format!("/paste/{}", gif_id),
        "original_svg": id,
    })))
}
