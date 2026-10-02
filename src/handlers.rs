// handlers.rs — HTTP request handlers for the kant-pastebin server
use actix_web::{web, HttpResponse, Result as ActixResult, HttpRequest};
use actix_cors::Cors;
use crate::model::{SplitProfile, SplitProfileRequest, Identity, Avatar, MeshPeer, MeshMessage, MeshMessageKind, SplitUnit, SplitMode};
use crate::storage;
use crate::mesh::MeshState;
use std::collections::HashMap;
use std::sync::Arc;
use serde::Serialize;
use std::io::Read;
use futures_util::StreamExt;

// ========== Paste-related handlers ==========

/// GET / — Serve the main index page
pub async fn index() -> ActixResult<HttpResponse> {
    let content = std::include_str!("../static/index.html");
    Ok(HttpResponse::Ok().content_type("text/html").body(content))
}

/// GET /browse — Browse pastes
pub async fn browse() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("browse endpoint"))
}

/// GET /threads — List threads
pub async fn threads() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("threads endpoint"))
}

// ========== Paste operations ==========

/// POST /paste — Create a new paste
pub async fn create_paste(data: crate::model::Paste) -> ActixResult<HttpResponse> {
    let paste = data;
    Ok(HttpResponse::Ok().json(crate::model::Response {
        ok: true,
        data: Some(paste),
        id: Some(format!("{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64)),
        cid: None,
        witness: None,
        ipfs_cid: None,
        url: None,
        permalink: None,
        uucp_path: None,
        reply_to: None,
        error: None,
    }))
}

/// POST /paste-form — Create paste from form data
pub async fn create_paste_form(form: web::Form<crate::model::Paste>) -> ActixResult<HttpResponse> {
    create_paste(form.into_inner()).await
}

/// POST /paste-multipart — Create paste from multipart form data
pub async fn create_paste_multipart(mut payload: actix_multipart::Multipart) -> ActixResult<HttpResponse> {
    let mut content = String::new();
    while let Some(field_result) = payload.next().await {
        if let Ok(mut field) = field_result {
            let field_content = field.content_disposition()
                .map(|d| d.get_name().unwrap_or("").to_string())
                .unwrap_or_default();
            let mut text = String::new();
            while let Some(chunk) = field.next().await {
                let bytes: actix_web::web::Bytes = match chunk {
                    Ok(b) => b,
                    Err(_) => break,
                };
                text.push_str(&String::from_utf8_lossy(&bytes));
            }
            if field_content == "content" {
                content = text;
            }
        }
    }
    Ok(HttpResponse::Ok().json(crate::model::Response {
        ok: true,
        data: Some(crate::model::Paste {
            id: format!("{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64),
            content,
            created: std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64,
            expires: None,
            tags: vec![],
            owner: None,
            title: None,
            reply_to: None,
            cid: None,
        }),
        id: Some(format!("{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64)),
        cid: None,
        witness: None,
        ipfs_cid: None,
        url: None,
        permalink: None,
        uucp_path: None,
        reply_to: None,
        error: None,
    }))
}

/// GET /paste/{id} — Get a paste
pub async fn get_paste(path: web::Path<String>) -> ActixResult<HttpResponse> {
    let id = path.into_inner();
    // Use storage to load the paste
    let storage = crate::storage::Storage::new(None);
    if let Some(content) = storage.load_content(&id) {
        Ok(HttpResponse::Ok().body(content))
    } else {
        Ok(HttpResponse::NotFound().body("paste not found"))
    }
}

/// GET /preview/{id} — Preview a paste
pub async fn preview_paste(path: web::Path<String>) -> ActixResult<HttpResponse> {
    let id = path.into_inner();
    Ok(HttpResponse::Ok().body(format!("preview of {}", id)))
}

/// GET /raw/{id} — Get raw paste content
pub async fn get_raw(path: web::Path<String>) -> ActixResult<HttpResponse> {
    let id = path.into_inner();
    storage::load_content(&id).map(|c| HttpResponse::Ok().body(c)).unwrap_or_else(|| HttpResponse::NotFound().body("not found"))
}

// ========== Gallery / rendering ==========

/// GET /gallery — Gallery page
pub async fn gallery() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("gallery endpoint"))
}

/// GET /gallery/img/{qid} — Gallery image
pub async fn gallery_image() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("gallery image endpoint"))
}

/// GET /render/{filename} — Render a file
pub async fn render_file(filename: web::Path<String>) -> ActixResult<HttpResponse> {
    let fname = filename.into_inner();
    Ok(HttpResponse::Ok().body(format!("render: {}", fname)))
}

// ========== Archive operations ==========

/// POST /upload-archive — Upload an archive
pub async fn upload_archive(mut payload: actix_multipart::Multipart) -> ActixResult<HttpResponse> {
    let mut data = Vec::new();
    while let Some(field_result) = payload.next().await {
        if let Ok(mut field) = field_result {
            let mut content = Vec::new();
            while let Some(chunk) = field.next().await {
                let bytes: actix_web::web::Bytes = match chunk {
                    Ok(b) => b,
                    Err(_) => break,
                };
                content.extend_from_slice(&bytes);
            }
            data.extend_from_slice(&content);
        }
    }
    Ok(HttpResponse::Ok().body(format!("archive: {} bytes", data.len())))
}

/// POST /archive-generate/{session_id} — Generate archive
pub async fn archive_generate(path: web::Path<(String, usize)>) -> ActixResult<HttpResponse> {
    let (session_id, idx) = path.into_inner();
    Ok(HttpResponse::Ok().body(format!("archive generate: {} idx {}", session_id, idx)))
}

/// POST /archive-split/{session_id} — Split archive
pub async fn archive_split(path: web::Path<(String, usize)>) -> ActixResult<HttpResponse> {
    let (session_id, idx) = path.into_inner();
    Ok(HttpResponse::Ok().body(format!("archive split: {} idx {}", session_id, idx)))
}

/// GET /archive-preview/{session_id}/{idx} — Archive preview
pub async fn archive_preview(path: web::Path<(String, usize)>) -> ActixResult<HttpResponse> {
    let (session_id, idx) = path.into_inner();
    Ok(HttpResponse::Ok().body(format!("archive preview: {} idx {}", session_id, idx)))
}

/// POST /archive-post-file/{session_id}/{idx} — Post archive file
pub async fn archive_post_file(path: web::Path<(String, usize)>) -> ActixResult<HttpResponse> {
    let (session_id, idx) = path.into_inner();
    Ok(HttpResponse::Ok().body(format!("archive post file: {} idx {}", session_id, idx)))
}

// ========== Splitter ==========

/// GET /splitter — Splitter page
pub async fn splitter_page(query: web::Query<HashMap<String, String>>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(format!("splitter: {:?}", query)))
}

/// GET /splitter/ — Splitter page (no query)
pub async fn splitter_page_default() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("splitter default"))
}

/// POST /api/split — API split
pub async fn api_split(body: web::Json<serde_json::Value>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(body.to_string()))
}

/// POST /api/split-paste — API split paste
pub async fn api_split_paste(body: web::Json<serde_json::Value>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(body.to_string()))
}

/// POST /api/split-download — API split download
pub async fn api_split_download(body: web::Json<serde_json::Value>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(body.to_string()))
}

/// POST /api/split-upload — API split upload
pub async fn api_split_upload(body: web::Json<serde_json::Value>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(body.to_string()))
}

/// GET /api/split-profiles — List split profiles
pub async fn list_split_profiles() -> ActixResult<HttpResponse> {
    let profiles = crate::model::SplitProfile::presets();
    Ok(HttpResponse::Ok().json(profiles))
}

/// GET /api/split-profiles/{name} — Get a split profile
pub async fn get_split_profile(path: web::Path<String>) -> ActixResult<HttpResponse> {
    let name = path.into_inner();
    if let Some(profile) = crate::model::SplitProfile::find_preset(&name) {
        Ok(HttpResponse::Ok().json(profile))
    } else {
        Ok(HttpResponse::NotFound().json(serde_json::json!({"error": "profile not found"})))
    }
}

/// POST /api/split-profiles — Create a split profile
pub async fn create_split_profile(body: web::Json<SplitProfileRequest>) -> ActixResult<HttpResponse> {
    let profile = crate::model::SplitProfile {
        name: body.name.clone(),
        label: body.label.clone().unwrap_or_else(|| body.name.clone()),
        context_window: body.context_window.unwrap_or(4096),
        unit: body.unit.unwrap_or(crate::model::SplitUnit::Byte),
        chunk_size: body.chunk_size,
        overlap: body.overlap.unwrap_or(0),
        max_output_tokens: body.max_output_tokens.unwrap_or(4096),
        split_mode: body.split_mode.unwrap_or(crate::model::SplitMode::Word),
        builtin: false,
        description: body.description.clone(),
    };
    Ok(HttpResponse::Created().json(profile))
}

// ========== API search ==========

/// GET /api/search — API search
pub async fn api_search(req: actix_web::HttpRequest) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("search endpoint"))
}

/// GET /search — Search page
pub async fn search_page() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("search page"))
}

/// POST /api/search-results-bundle — API search results bundle
pub async fn api_search_results_bundle(body: web::Json<serde_json::Value>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(body.to_string()))
}

/// POST /api/search-results-chunks — API search results chunks
pub async fn api_search_results_chunks(body: web::Json<serde_json::Value>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(body.to_string()))
}

/// GET /api/search-doc — API search doc
pub async fn api_search_doc(req: actix_web::HttpRequest) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("search-doc endpoint"))
}

// ========== Similar / bundle ==========

/// GET /api/similar/{id} — API similar
pub async fn api_similar(path: web::Path<String>) -> ActixResult<HttpResponse> {
    let id = path.into_inner();
    Ok(HttpResponse::Ok().json(serde_json::json!({"id": id, "similar": []})))
}

/// POST /api/bundle — API bundle
pub async fn api_bundle(body: web::Json<serde_json::Value>) -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body(body.to_string()))
}

// ========== Plugins ==========

/// GET /plugins — List plugins
pub async fn list_plugins() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("plugins endpoint"))
}

/// POST /plugin/{name}/{id} — Run a plugin
pub async fn run_plugin(path: web::Path<(String, String)>) -> ActixResult<HttpResponse> {
    let (name, id) = path.into_inner();
    Ok(HttpResponse::Ok().json(serde_json::json!({"name": name, "id": id, "result": "ok"})))
}

/// GET /health — Health check
pub async fn health_check() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().json(serde_json::json!({"status": "ok"})))
}

/// GET /api/version — Version
pub async fn api_version() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().json(serde_json::json!({"version": "0.1.0"})))
}

/// GET /api/diagnostics — Diagnostics
pub async fn api_diagnostics() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().json(serde_json::json!({})))
}

// ========== Git operations ==========

/// GET /git-browse — Git browse
pub async fn git_browse() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("git browse"))
}

/// GET /git-browse/{mount_id} — Git browse mount
pub async fn git_browse_mount(path: web::Path<String>) -> ActixResult<HttpResponse> {
    let mount_id = path.into_inner();
    Ok(HttpResponse::Ok().json(serde_json::json!({"mount_id": mount_id})))
}

/// GET /git-view/{mount_id}/{path:.*} — Git view file
pub async fn git_view_file(path: web::Path<(String, String)>) -> ActixResult<HttpResponse> {
    let (mount_id, file_path) = path.into_inner();
    Ok(HttpResponse::Ok().json(serde_json::json!({"mount_id": mount_id, "file": file_path})))
}

// ========== Mesh / Identity / Avatar handlers ==========

/// GET /api/mesh/peers — List all known mesh peers
pub async fn list_mesh_peers(
    state: web::Data<Arc<MeshState>>,
) -> ActixResult<HttpResponse> {
    let peers = state.get_peers();
    Ok(HttpResponse::Ok().json(peers))
}

/// POST /api/mesh/ping — Receive a ping from another relay
pub async fn receive_mesh_ping(
    state: web::Data<Arc<MeshState>>,
    msg: web::Json<MeshMessage>,
) -> ActixResult<HttpResponse> {
    state.handle_message(msg.into_inner()).await?;
    Ok(HttpResponse::Ok().json(serde_json::json!({"ok": true})))
}

/// POST /api/mesh/announce — Announce this relay's identity
pub async fn announce_identity(
    state: web::Data<Arc<MeshState>>,
    identity: web::Json<Identity>,
) -> ActixResult<HttpResponse> {
    let identity = identity.into_inner();
    state.save_identity(&identity).await?;
    Ok(HttpResponse::Ok().json(serde_json::json!({"ok": true})))
}

/// GET /api/identities — List all saved identities
pub async fn list_identities(
    state: web::Data<Arc<Storage>>,
) -> ActixResult<HttpResponse> {
    let identities = state.list_identities().await;
    Ok(HttpResponse::Ok().json(identities))
}

/// GET /api/identities/{id} — Get a specific identity
pub async fn get_identity(
    path: web::Path<String>,
    state: web::Data<Arc<Storage>>,
) -> ActixResult<HttpResponse> {
    let id = path.into_inner();
    let identity = state.load_identity(&id).await;
    match identity {
        Some(ident) => Ok(HttpResponse::Ok().json(ident)),
        None => Ok(HttpResponse::Ok().json(serde_json::json!({"error": "identity not found"})))
    }
}

/// POST /api/identities — Create a new identity
pub async fn create_identity(
    state: web::Data<Arc<Storage>>,
    ident: web::Json<Identity>,
) -> ActixResult<HttpResponse> {
    let identity = ident.into_inner();
    state.save_identity(&identity).await?;
    Ok(HttpResponse::Created().json(identity))
}

/// GET /api/avatars/{owner} — List avatars for a specific owner
pub async fn list_avatars(
    path: web::Path<String>,
    state: web::Data<Arc<Storage>>,
) -> ActixResult<HttpResponse> {
    let owner = path.into_inner();
    let avatars = state.list_avatars(&owner).await;
    Ok(HttpResponse::Ok().json(avatars))
}

/// POST /api/avatars — Upload a new avatar
pub async fn upload_avatar(
    state: web::Data<Arc<Storage>>,
    avatar: web::Json<Avatar>,
) -> ActixResult<HttpResponse> {
    let avatar = avatar.into_inner();
    state.save_avatar(&avatar).await?;
    Ok(HttpResponse::Created().json(avatar))
}

/// GET /api/avatars/{id} — Get a specific avatar
pub async fn get_avatar(
    path: web::Path<String>,
    state: web::Data<Arc<Storage>>,
) -> ActixResult<HttpResponse> {
    let id = path.into_inner();
    let avatar = state.load_avatar(&id).await;
    match avatar {
        Some(avatar) => Ok(HttpResponse::Ok().json(avatar)),
        None => Ok(HttpResponse::Ok().json(serde_json::json!({"error": "avatar not found"})))
    }
}

// ========== Plugin handlers (already defined elsewhere) ==========

/// POST /plugins — List plugins
pub async fn list_plugins_handler() -> ActixResult<HttpResponse> {
    Ok(HttpResponse::Ok().body("plugins endpoint"))
}

/// POST /plugin/{name}/{id} — Run a plugin
pub async fn run_plugin_handler(path: web::Path<(String, String)>) -> ActixResult<HttpResponse> {
    let (name, id) = path.into_inner();
    Ok(HttpResponse::Ok().json(serde_json::json!({"name": name, "id": id, "result": "ok"})))
}
