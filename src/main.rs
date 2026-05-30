use actix_web::{web, App, HttpServer};
use actix_cors::Cors;
use std::env;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

mod model;
mod view;
mod api;
mod handlers;
mod storage;
mod ipfs;
mod tagging;
mod plugin;
mod plugins;
mod tiles;
mod dasl;
mod sheaf;

mod archive;

mod nix_skill;
mod mcp_server;

#[derive(OpenApi)]
#[openapi(
    paths(handlers::create_paste, handlers::get_paste, handlers::browse),
    components(schemas(model::Paste, model::Response))
)]
struct ApiDoc;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));
    
    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8090".to_string());
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    
    log::info!("🚀 Starting kant-pastebin microservice on {}", bind);
    log::info!("📁 UUCP spool: {}", uucp_dir);
    
    // Initialize plugin registry
    let mut registry = plugin::PluginRegistry::new();
    registry.register(Box::new(plugins::screenshot::ScreenshotPlugin::new()));
    registry.register(Box::new(plugins::pipelight::PipelightPlugin::new()));
    registry.register(Box::new(plugins::git2nora::Git2NoraPlugin::new()));

    // Discover and register tile plugins from TILES_DIR
    let tiles_dir = env::var("TILES_DIR").unwrap_or_default();
    if !tiles_dir.is_empty() {
        let loaded_tiles = tiles::discover_tiles(&tiles_dir);
        for loaded in loaded_tiles {
            log::info!("Registering tile plugin: {}", loaded.name());
            let plugin = tiles::TilePlugin::new(loaded);
            registry.register(Box::new(plugin));
        }
        log::info!("Tile plugin discovery complete");
    } else {
        log::warn!("TILES_DIR not set — no tile plugins loaded");
    }

    let registry = web::Data::new(std::sync::Mutex::new(registry));
    
    let openapi = ApiDoc::openapi();
    
    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);
            
        App::new()
            .wrap(cors)
            .app_data(registry.clone())
            .service(
                SwaggerUi::new("/swagger-ui/{_:.*}")
                    .url("/openapi.json", openapi.clone())
            )
            .route("/", web::get().to(handlers::index))
            .route("/browse", web::get().to(handlers::browse))
            .route("/paste", web::post().to(handlers::create_paste))
            .route("/paste/{id}", web::get().to(handlers::get_paste))
            .route("/preview/{id}", web::get().to(handlers::preview_paste))
            .route("/raw/{id}", web::get().to(handlers::get_raw))
            .route("/upgrade", web::post().to(handlers::upgrade_pastes))
            .route("/thread/{id}", web::get().to(handlers::get_thread))
            .route("/upload", web::post().to(handlers::upload_file))
            .route("/file/{id}", web::get().to(handlers::get_file))
            .route("/ipfs/{cid}", web::get().to(handlers::ipfs_proxy))
            .route("/gallery", web::get().to(handlers::gallery))
            .route("/gallery/img/{qid}", web::get().to(handlers::gallery_image))
            .route("/upload-archive", web::post().to(handlers::upload_archive))
            .route("/browse-archive/{session_id}", web::get().to(handlers::archive_viewer))
            .route("/allm/{session_id}", web::post().to(handlers::archive_generate))
            .route("/archive-generate/{session_id}", web::post().to(handlers::archive_generate))
            .route("/archive-split/{session_id}", web::post().to(handlers::archive_split))
            .route("/archive-preview/{session_id}/{idx}", web::get().to(handlers::archive_preview))
            .route("/archive-post-file/{session_id}/{idx}", web::post().to(handlers::archive_post_file))
            .route("/splitter", web::get().to(handlers::splitter_page))
            .route("/api/split", web::post().to(handlers::api_split))
            .route("/api/split-upload", web::post().to(handlers::api_split_upload))
            .route("/api/search", web::get().to(handlers::api_search))
            .route("/api/search-doc", web::get().to(handlers::search_doc))
            .route("/api/similar/{id}", web::get().to(handlers::api_similar))
            .route("/api/bundle", web::post().to(handlers::api_bundle))
            .route("/plugin/{name}/{id}", web::post().to(handlers::run_plugin))
            .route("/plugins", web::get().to(handlers::list_plugins))
            .route("/api/nix-skill/analyze", web::post().to(handlers::nix_skill_analyze))
            .route("/api/nix-skill/find", web::post().to(handlers::nix_skill_find))
            .route("/mcp", web::post().to(mcp_server::mcp_handler))
    })
    .bind(&bind)?
    .run()
    .await
}
