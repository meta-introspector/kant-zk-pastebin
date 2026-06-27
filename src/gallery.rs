// Gallery — shows NFT enrichments + all uploaded media (images, SVG, GIF, video)
use actix_web::{HttpResponse, Result};
use log::warn;
use std::{collections::HashMap, env, fs};

/// GET /gallery - Gallery of NFT enrichments + uploaded media
pub async fn gallery() -> Result<HttpResponse> {
    let base_path = env::var("BASE_PATH").unwrap_or_default();
    let nft_dir = env::var("NFT_DIR")
        .unwrap_or_else(|_| "/mnt/data1/time-2026/03-march/13/nft_enriched".to_string());
    let uucp_dir = env::var("UUCP_SPOOL")
        .unwrap_or_else(|_| "/var/spool/uucp/pastebin".to_string());

    // ── NFT items ──
    let mut items = Vec::new();
    if let Ok(entries) = fs::read_dir(&nft_dir) {
        for entry in entries.flatten() {
            if !entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                continue;
            }
            let qid = entry.file_name().to_string_lossy().to_string();
            let meta_path = entry.path().join("metadata.rdfa");
            let mut meta = HashMap::new();
            if let Ok(content) = fs::read_to_string(&meta_path) {
                for line in content.lines() {
                    if let Some((k, v)) = line.split_once('=') {
                        meta.insert(k.to_string(), v.to_string());
                    }
                }
            }
            let name = meta.get("name").cloned().unwrap_or_else(|| qid.clone());
            let desc = meta.get("description").cloned().unwrap_or_default();
            let html_cid = meta.get("ipfs_html_cid").cloned().unwrap_or_default();
            let nft_cid = meta.get("ipfs_nft_cid").cloned().unwrap_or_default();
            let dir_cid = meta.get("ipfs_dir_cid").cloned().unwrap_or_default();
            let witness = meta.get("witness").cloned().unwrap_or_default();
            let has_image = entry.path().join("source.jpg").exists();

            let img_html = if has_image && !nft_cid.is_empty() {
                format!(
                    r#"<img src="{}/ipfs/{}" style="max-width:200px;max-height:150px;border-radius:4px" alt="{}">"#,
                    base_path, nft_cid, name
                )
            } else if has_image {
                format!(
                    r#"<img src="{}/gallery/img/{}" style="max-width:200px;max-height:150px;border-radius:4px" alt="{}">"#,
                    base_path, qid, name
                )
            } else {
                r#"<div style="width:200px;height:150px;background:#222;display:flex;align-items:center;justify-content:center;border-radius:4px">🖼️</div>"#.to_string()
            };

            items.push(format!(
                r#"<div style="background:#1a1a1a;padding:15px;border-radius:8px;display:flex;gap:15px;align-items:start">
{img_html}
<div>
<h3 style="color:#0ff;margin:0"><a href="{bp}/ipfs/{hcid}">{name}</a></h3>
<p style="color:#999;margin:5px 0">{desc}</p>
<p style="font-size:12px;color:#666">
<a href="https://www.wikidata.org/wiki/{qid}">{qid}</a>
{nft_link}{dir_link}
</p>
<code style="font-size:10px;color:#555">{witness}</code>
</div></div>"#,
                bp = base_path,
                hcid = html_cid,
                name = name,
                desc = desc,
                qid = qid,
                nft_link = if nft_cid.is_empty() { String::new() } else { format!(r#"| <a href="{}/ipfs/{}">NFT</a>"#, base_path, nft_cid) },
                dir_link = if dir_cid.is_empty() { String::new() } else { format!(r#"| <a href="{}/ipfs/{}">IPFS Dir</a>"#, base_path, dir_cid) },
                witness = &witness[..witness.len().min(16)],
            ));
        }
    }

    // ── Media uploads from spool ──
    let media_exts = ["png", "jpg", "jpeg", "gif", "svg", "webp", "mp4", "webm"];
    let mut media = Vec::new();
    if let Ok(entries) = fs::read_dir(&uucp_dir) {
        let index_file = format!("{}/index.jsonl", uucp_dir);
        let index: Vec<crate::model::PasteIndex> = fs::read_to_string(&index_file)
            .unwrap_or_default()
            .lines()
            .filter_map(|l| serde_json::from_str(l).ok())
            .collect();

        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            let ext = name.rsplit_once('.').map(|(_, e)| e.to_lowercase()).unwrap_or_default();
            if !media_exts.contains(&ext.as_str()) { continue; }
            let stem = name.rsplit_once('.').map(|(s, _)| s).unwrap_or(&name).to_string();
            let title = index.iter().find(|e| e.id == stem).map(|e| &e.title).cloned().unwrap_or_else(|| stem.clone());
            let mime = match ext.as_str() {
                "svg" => "image/svg+xml",
                "gif" => "image/gif",
                "png" | "jpg" | "jpeg" | "webp" => "image",
                "mp4" | "webm" => "video",
                _ => "file",
            };
            let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
            let pretty_size = if size > 1_000_000 { format!("{:.1}MB", size as f64 / 1_000_000.0) } else { format!("{:.1}KB", size as f64 / 1_000.0) };

            let preview = if mime == "video" {
                format!(r#"<video src="{bp}/file/{stem}" style="max-width:200px;max-height:150px;border-radius:4px" controls></video>"#, bp = base_path, stem = stem)
            } else if ext == "svg" {
                format!(r#"<a href="{bp}/paste/{stem}"><img src="{bp}/file/{stem}" style="max-width:200px;max-height:150px;border-radius:4px;background:#fff" alt="{title}"></a><br><a href="{bp}/svg2anim/{stem}" style="font-size:11px;color:#0f0" onclick="return confirm('Generate animation from this SVG?')">🎬 Render Animation</a>"#, bp = base_path, stem = stem, title = title)
            } else {
                format!(r#"<a href="{bp}/paste/{stem}"><img src="{bp}/file/{stem}" style="max-width:200px;max-height:150px;border-radius:4px" alt="{title}"></a>"#, bp = base_path, stem = stem, title = title)
            };

            media.push(format!(
                r#"<div style="background:#1a1a1a;padding:10px;border-radius:8px;text-align:center">
{preview}
<div style="font-size:12px;color:#0ff;margin-top:5px">{title}</div>
<div style="font-size:10px;color:#666">{pretty_size} · {ext}</div>
</div>"#,
                preview = preview,
                title = title,
                pretty_size = pretty_size,
                ext = ext,
            ));
        }
    }

    let nft_count = items.len();
    let media_count = media.len();
    let media_html = if media.is_empty() {
        String::new()
    } else {
        format!(r#"<h2>📁 Media Uploads</h2>
<p style="color:#999">{media_count} files</p>
<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px">{items}</div>"#,
            media_count = media_count,
            items = media.join("\n"),
        )
    };

    Ok(HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(format!(
            r#"<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Gallery</title>
<style>
body{{font-family:system-ui,sans-serif;max-width:1000px;margin:0 auto;padding:20px;background:#111;color:#eee}}
a{{color:#0ff;text-decoration:none}}
.nav{{background:#1a1a1a;padding:10px;margin-bottom:20px;border-radius:8px}}
.nav a{{margin-right:15px}}
h1,h2{{color:#0ff}}
</style></head><body>
<div class="nav">
<a href="{bp}/">🏠 Home</a>
<a href="{bp}/browse">📚 Browse</a>
<a href="{bp}/gallery">🖼️ Gallery</a>
<a href="{bp}/api/version">📋 Version</a>
</div>
<h1>🖼️ Gallery</h1>
{nft_section}
{media_section}
</body></html>"#,
            bp = base_path,
            nft_section = if nft_count > 0 {
                format!("<h2>🏛️ NFT Enrichments</h2><p style=\"color:#999\">{count} entities</p><div style=\"display:flex;flex-direction:column;gap:10px\">{items}</div>",
                    count = nft_count,
                    items = items.join("\n"),
                )
            } else { String::new() },
            media_section = media_html,
        )))
}
