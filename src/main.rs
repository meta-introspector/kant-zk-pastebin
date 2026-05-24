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
mod search;
mod dasl;
mod sheaf;
mod car_index;

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
    
    // Initialize CAR file index (searches locate DB)
    let car_index = std::sync::Arc::new(car_index::CarIndex::new());
    {
        let idx = car_index.clone();
        actix_web::rt::spawn(async move {
            log::info!("📂 Building CAR file index from locate DB...");
            match idx.build(&[("mid", "MIDI"), ("puml", "PlantUML"), ("plantuml", "PlantUML")]) {
                Ok(_) => log::info!("✅ CAR index built: {:?}", idx.stats()),
                Err(e) => log::warn!("CAR index build skipped: {}", e),
            }
        });
    }
    
    // Initialize plugin registry
    let mut registry = plugin::PluginRegistry::new();
    registry.register(Box::new(plugins::screenshot::ScreenshotPlugin::new()));
    registry.register(Box::new(plugins::bkma::BkmaAnalyzerPlugin::new()));
    registry.register(Box::new(plugins::tiles::TilesPlugin::new()));
    registry.register(Box::new(plugins::midi::MidiPlugin::new(car_index.clone())));
    registry.register(Box::new(plugins::plantuml::PlantUmlPlugin::new(car_index.clone())));
    registry.register(Box::new(plugins::graphviz::GraphvizPlugin::new()));
    registry.register(Box::new(plugins::minizinc::MiniZincPlugin::new()));
    registry.register(Box::new(plugins::lean::LeanPlugin::new()));
    registry.register(Box::new(plugins::tulip::TulipPlugin::new()));
    registry.register(Box::new(plugins::flamegraph::FlamegraphPlugin::new()));
    registry.register(Box::new(plugins::dasl_testing::DaslTestingPlugin::new()));
    registry.register(Box::new(plugins::decl_tile::DeclTilePlugin::new()));
    registry.register(Box::new(plugins::perf_annotations::PerfAnnotationsPlugin::new()));
    registry.register(Box::new(plugins::plugin_browser::PluginBrowserPlugin::new()));
    registry.register(Box::new(plugins::zombie::ZombiePlugin::new()));
    registry.register(Box::new(plugins::zos::ZosPlugin::new()));
    registry.register(Box::new(plugins::deep_scan::DeepScanPlugin::new()));
    registry.register(Box::new(plugins::git_tile::GitTilePlugin::new()));
    registry.register(Box::new(plugins::cargo_tile::CargoTilePlugin::new()));
    registry.register(Box::new(plugins::nix_tile::NixTilePlugin::new()));
    registry.register(Box::new(plugins::data_tiles::DataTilesPlugin::new()));
    registry.register(Box::new(plugins::dasl_decode_finder::DaslDecodeFinderPlugin::new()));
    registry.register(Box::new(plugins::testing_tile_matrix::TestingTileMatrixPlugin::new()));
    registry.register(Box::new(plugins::plocate_search::PlocateSearchPlugin::new()));
    let registry = web::Data::new(std::sync::Mutex::new(registry));
    let car_index_data = web::Data::new(car_index);
    
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
            .route("/file/{id}/source", web::get().to(handlers::get_file_source))
            .route("/file/{id}/raw", web::get().to(handlers::get_file_raw))
            .route("/ipfs/{cid}", web::get().to(handlers::ipfs_proxy))
            .route("/gallery", web::get().to(handlers::gallery))
            .route("/gallery/img/{qid}", web::get().to(handlers::gallery_image))
            .route("/plugin/{name}/{id}", web::post().to(handlers::run_plugin))
            .route("/plugins", web::get().to(handlers::list_plugins))
            .route("/tiles", web::get().to(handlers::tiles_view))
            .route("/car/midi", web::get().to(handlers::car_browse_midi))
            .route("/car/plantuml", web::get().to(handlers::car_browse_plantuml))
            .route("/plugin/{name}", web::get().to(handlers::plugin_route))
            .route("/stego", web::get().to(handlers::stego_dashboard))
            .service(actix_files::Files::new("/stego/pkg", "erdfa-clean/wasm/pkg"))
            .service(actix_files::Files::new("/stego/samples", "erdfa-clean/wasm/samples"))
            .route("/wasm", web::get().to(handlers::wasm_frontend))
            .service(actix_files::Files::new("/wasm/pkg", "pastebin-wasm/static/pkg"))
            .service(actix_files::Files::new("/wasm", "pastebin-wasm/static"))
    })
    .bind(&bind)?
    .run()
    .await
}
