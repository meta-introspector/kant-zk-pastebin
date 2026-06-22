use actix_cors::Cors;
use actix_web::{web, App, HttpServer};
use clap::{Parser, Subcommand, ValueEnum};
use model::{SplitMode, SplitProfile, SplitUnit};
use std::{env, fs, io, io::Read};
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

mod api;
mod dasl;
mod handlers;
mod ipfs;
mod model;
mod plugin;
mod plugins;
mod rename;
mod share;
mod sheaf;
mod storage;
mod summary;
mod tagging;
mod tiles;
mod view;

mod archive;

mod git_mount;

mod mcp_server;
mod nix_skill;
mod splitter;

#[derive(Parser)]
#[command(
    name = "kant-pastebin",
    about = "Kant Pastebin server and splitter testing CLI"
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    Split(SplitArgs),
    SplitUrl(SplitUrlArgs),
    Profiles,
    TestShareMenu,
    RenameAllmPastes(RenameAllmPastesArgs),
}

#[derive(Parser)]
struct SplitArgs {
    #[arg(short, long)]
    profile: Option<String>,
    #[arg(short = 'c', long)]
    chunk_size: Option<usize>,
    #[arg(short, long)]
    overlap: Option<usize>,
    #[arg(long)]
    unit: Option<CliUnit>,
    #[arg(long)]
    split_mode: Option<CliSplitMode>,
    #[arg(short, long)]
    input: Option<String>,
    #[arg(long)]
    json: bool,
}

#[derive(Parser)]
struct SplitUrlArgs {
    url: String,
    #[arg(short, long)]
    profile: Option<String>,
    #[arg(long)]
    json: bool,
}

#[derive(Parser)]
struct RenameAllmPastesArgs {
    #[arg(long)]
    uucp_dir: Option<String>,
    #[arg(long)]
    apply: bool,
    #[arg(long)]
    rename_files: bool,
    #[arg(long)]
    limit: Option<usize>,
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Copy, ValueEnum)]
enum CliUnit {
    Byte,
    Word,
    Token,
}

#[derive(Clone, Copy, ValueEnum)]
enum CliSplitMode {
    Line,
    Word,
    Exact,
}

#[derive(OpenApi)]
#[openapi(
    paths(handlers::create_paste, handlers::get_paste, handlers::browse),
    components(schemas(model::Paste, model::Response))
)]
struct ApiDoc;

async fn run_cli(cli: Cli) -> Result<bool, String> {
    match cli.command {
        Some(Commands::Split(args)) => {
            run_split_cli(args)?;
            Ok(true)
        }
        Some(Commands::SplitUrl(args)) => {
            run_split_url_cli(args).await?;
            Ok(true)
        }
        Some(Commands::Profiles) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&SplitProfile::presets()).map_err(|e| e.to_string())?
            );
            Ok(true)
        }
        Some(Commands::TestShareMenu) => {
            share::run_share_menu_test()?;
            println!("share menu test passed");
            Ok(true)
        }
        Some(Commands::RenameAllmPastes(args)) => {
            run_rename_allm_pastes_cli(args)?;
            Ok(true)
        }
        None => Ok(false),
    }
}

fn run_split_cli(args: SplitArgs) -> Result<(), String> {
    let content = read_input(args.input.as_deref())?;
    print_mem("after read_input");
    if content.trim().is_empty() {
        return Err("empty input".to_string());
    }

    let (chunk_size, overlap, unit, split_mode, profile_name) = resolve_split_config(&args)?;
    print_mem("after resolve_split_config");
    let chunks = splitter::split_text(&content, chunk_size, unit, split_mode);
    let overlapped = splitter::apply_overlap(chunks, overlap, unit, split_mode);

    if args.json {
        let payload = serde_json::json!({
            "chunks": overlapped.len(),
            "chunk_size": chunk_size,
            "overlap": overlap,
            "unit": serde_json::to_value(unit).map_err(|e| e.to_string())?,
            "split_mode": serde_json::to_value(split_mode).map_err(|e| e.to_string())?,
            "profile": profile_name,
            "total_size": content.len(),
            "word_count": crate::splitter::count_words(&content),
            "estimated_tokens": crate::splitter::estimate_tokens(&content),
            "contents": overlapped,
        });
        print_mem("after build json payload");
        println!(
            "{}",
            serde_json::to_string_pretty(&payload).map_err(|e| e.to_string())?
        );
    } else {
        println!(
            "unit: {} | chunk_size: {} | overlap: {} | split_mode: {} | profile: {} | chunks: {} | words: {} | est_tokens: {}",
            unit_label(unit),
            chunk_size,
            overlap,
            split_mode_label(split_mode),
            profile_name.as_deref().unwrap_or("custom"),
            overlapped.len(),
            crate::splitter::count_words(&content),
            crate::splitter::estimate_tokens(&content)
        );
        for (idx, chunk) in overlapped.iter().enumerate() {
            println!("\n===== chunk {} / {} =====", idx + 1, overlapped.len());
            print!("{}", chunk);
            if !chunk.ends_with('\n') {
                println!();
            }
        }
    }

    print_mem("before return");
    Ok(())
}

fn print_mem(label: &str) {
    let rss_kb = std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|status| {
            status
                .lines()
                .find(|line| line.starts_with("VmRSS:"))
                .and_then(|line| line.split_whitespace().nth(1))
                .and_then(|value| value.parse::<usize>().ok())
        });

    if let Some(rss_kb) = rss_kb {
        eprintln!("mem {}: {} KB", label, rss_kb);
    }
}

fn run_rename_allm_pastes_cli(args: RenameAllmPastesArgs) -> Result<(), String> {
    let options = rename::RenameOptions {
        uucp_dir: args.uucp_dir.unwrap_or_else(rename::default_uucp_dir),
        apply: args.apply,
        rename_files: args.rename_files,
        limit: args.limit,
    };
    let report = rename::rename_allm_pastes(&options)?;

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&report).map_err(|e| e.to_string())?
        );
        return Ok(());
    }

    println!(
        "allm rename: total={} renamed={} skipped={} errors={}",
        report.total,
        report.renamed,
        report.skipped,
        report.errors.len()
    );
    if !report.errors.is_empty() {
        for error in report.errors.iter().take(20) {
            eprintln!("error {} {}: {}", error.id, error.filename, error.error);
        }
    }
    for item in report.items.iter().take(20) {
        println!(
            "{}: {} -> {} | {} | {} files | {}",
            if item.applied { "applied" } else { "planned" },
            item.old_title,
            item.title,
            item.old_filename,
            item.selected_files,
            item.description
        );
    }
    if report.items.len() > 20 {
        println!("... {} more", report.items.len() - 20);
    }

    Ok(())
}

async fn run_split_url_cli(args: SplitUrlArgs) -> Result<(), String> {
    let raw_url = raw_url_from_split_url(&args.url)
        .ok_or_else(|| "could not derive /raw/ URL from split URL".to_string())?;
    let base_url = base_url_from_split_url(&args.url)
        .ok_or_else(|| "could not derive API base URL from split URL".to_string())?;
    let content = reqwest::get(&raw_url)
        .await
        .map_err(|e| e.to_string())?
        .error_for_status()
        .map_err(|e| e.to_string())?
        .text()
        .await
        .map_err(|e| e.to_string())?;

    if content.trim().is_empty() {
        return Err("empty paste content".to_string());
    }

    let profile = args.profile.unwrap_or_else(|| "notebooklm".to_string());
    let api_url = format!("{}/api/split", base_url.trim_end_matches('/'));
    let payload: serde_json::Value = reqwest::Client::new()
        .post(&api_url)
        .json(&serde_json::json!({
            "profile": profile,
            "content": content,
        }))
        .send()
        .await
        .map_err(|e| e.to_string())?
        .error_for_status()
        .map_err(|e| e.to_string())?
        .json()
        .await
        .map_err(|e| e.to_string())?;

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&payload).map_err(|e| e.to_string())?
        );
    } else {
        let chunks = payload
            .get("chunks")
            .and_then(|v| v.as_u64())
            .unwrap_or_default();
        let words = payload
            .get("word_count")
            .and_then(|v| v.as_u64())
            .unwrap_or_default();
        let tokens = payload
            .get("estimated_tokens")
            .and_then(|v| v.as_u64())
            .unwrap_or_default();
        println!(
            "split-url: {} | raw: {} | api: {} | chunks: {} | words: {} | est_tokens: {}",
            args.url, raw_url, api_url, chunks, words, tokens
        );
        if let Some(contents) = payload.get("contents").and_then(|v| v.as_array()) {
            for (idx, chunk) in contents.iter().take(3).enumerate() {
                let text = chunk.as_str().unwrap_or_default();
                println!("\n===== chunk {} / {} =====", idx + 1, chunks);
                println!("{}", text.chars().take(1000).collect::<String>());
                if text.chars().count() > 1000 {
                    println!("… truncated");
                }
            }
        }
    }

    Ok(())
}

fn raw_url_from_split_url(url: &str) -> Option<String> {
    let id = paste_id_from_split_url(url)?;
    let path_start = url.find("/pastebin/")?;
    let origin = &url[..path_start];
    Some(format!("{}/pastebin/raw/{}", origin, id))
}

fn base_url_from_split_url(url: &str) -> Option<String> {
    let path_start = url.find("/pastebin/")?;
    Some(format!("{}/pastebin", &url[..path_start]))
}

fn paste_id_from_split_url(url: &str) -> Option<String> {
    let path = url.split('?').next()?;
    let parts: Vec<&str> = path.trim_end_matches('/').split('/').collect();
    if parts.len() >= 4 && parts[parts.len() - 1] == "split" {
        Some(parts[parts.len() - 2].to_string())
    } else if parts.len() >= 3 && parts[parts.len() - 2] == "paste" {
        Some(parts[parts.len() - 1].to_string())
    } else {
        None
    }
}

fn resolve_split_config(
    args: &SplitArgs,
) -> Result<(usize, usize, SplitUnit, SplitMode, Option<String>), String> {
    let (mut chunk_size, mut overlap, mut unit, mut split_mode, profile_name) =
        if let Some(name) = args.profile.as_deref() {
            let profile = SplitProfile::find_preset(name)
                .ok_or_else(|| format!("unknown profile: {}", name))?;
            (
                profile.chunk_size,
                profile.overlap,
                profile.unit,
                profile.split_mode,
                Some(name.to_string()),
            )
        } else {
            (
                args.chunk_size.unwrap_or(102_400),
                args.overlap.unwrap_or(0),
                args.unit.map(to_split_unit).unwrap_or(SplitUnit::Byte),
                args.split_mode
                    .map(to_split_mode)
                    .unwrap_or(SplitMode::Word),
                None,
            )
        };

    if let Some(value) = args.chunk_size {
        chunk_size = value;
    }
    if let Some(value) = args.overlap {
        overlap = value;
    }
    if let Some(value) = args.unit {
        unit = to_split_unit(value);
    }
    if let Some(value) = args.split_mode {
        split_mode = to_split_mode(value);
    }

    Ok((chunk_size, overlap, unit, split_mode, profile_name))
}

fn read_input(path: Option<&str>) -> Result<String, String> {
    match path {
        Some("-") | None => {
            let mut content = String::new();
            io::stdin()
                .read_to_string(&mut content)
                .map_err(|e| e.to_string())?;
            Ok(content)
        }
        Some(path) => fs::read_to_string(path).map_err(|e| e.to_string()),
    }
}

fn to_split_unit(value: CliUnit) -> SplitUnit {
    match value {
        CliUnit::Byte => SplitUnit::Byte,
        CliUnit::Word => SplitUnit::Word,
        CliUnit::Token => SplitUnit::Token,
    }
}

fn to_split_mode(value: CliSplitMode) -> SplitMode {
    match value {
        CliSplitMode::Line => SplitMode::Line,
        CliSplitMode::Word => SplitMode::Word,
        CliSplitMode::Exact => SplitMode::Exact,
    }
}

fn unit_label(unit: SplitUnit) -> &'static str {
    match unit {
        SplitUnit::Byte => "byte",
        SplitUnit::Word => "word",
        SplitUnit::Token => "token",
    }
}

fn split_mode_label(split_mode: SplitMode) -> &'static str {
    match split_mode {
        SplitMode::Line => "line",
        SplitMode::Word => "word",
        SplitMode::Exact => "exact",
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let cli = Cli::parse();
    if run_cli(cli)
        .await
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidInput, error))?
    {
        return Ok(());
    }

    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));

    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8090".to_string());
    let uucp_dir =
        env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());

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
            .service(SwaggerUi::new("/swagger-ui/{_:.*}").url("/openapi.json", openapi.clone()))
            .route("/", web::get().to(handlers::index))
            .route("/browse", web::get().to(handlers::browse))
            .route("/threads", web::get().to(handlers::threads))
            .route("/paste", web::post().to(handlers::create_paste))
            .route("/paste/{id}", web::get().to(handlers::get_paste))
            .route(
                "/paste/{id}/split",
                web::get().to(handlers::get_paste_split),
            )
            .route("/preview/{id}", web::get().to(handlers::preview_paste))
            .route("/raw/{id}", web::get().to(handlers::get_raw))
            .route("/upgrade", web::post().to(handlers::upgrade_pastes))
            .route(
                "/thread/{id}/export",
                web::get().to(handlers::export_thread),
            )
            .route("/thread/{id}", web::get().to(handlers::get_thread))
            .route("/api/thread/{id}", web::get().to(handlers::api_thread))
            .route("/upload", web::post().to(handlers::upload_file))
            .route("/file/{id}", web::get().to(handlers::get_file))
            .route("/ipfs/{cid}", web::get().to(handlers::ipfs_proxy))
            .route("/gallery", web::get().to(handlers::gallery))
            .route("/gallery/img/{qid}", web::get().to(handlers::gallery_image))
            .route("/upload-archive", web::post().to(handlers::upload_archive))
            .route(
                "/browse-archive/{session_id}",
                web::get().to(handlers::archive_viewer),
            )
            .route(
                "/allm/{session_id}",
                web::post().to(handlers::archive_generate),
            )
            .route(
                "/archive-generate/{session_id}",
                web::post().to(handlers::archive_generate),
            )
            .route(
                "/archive-split/{session_id}",
                web::post().to(handlers::archive_split),
            )
            .route(
                "/archive-preview/{session_id}/{idx}",
                web::get().to(handlers::archive_preview),
            )
            .route(
                "/archive-post-file/{session_id}/{idx}",
                web::post().to(handlers::archive_post_file),
            )
            .route("/splitter", web::get().to(handlers::splitter_page))
            .route("/splitter/", web::get().to(handlers::splitter_page))
            .route("/api/split", web::post().to(handlers::api_split))
            .route(
                "/api/split-paste",
                web::post().to(handlers::api_split_paste),
            )
            .route(
                "/api/split-download",
                web::post().to(handlers::api_split_download),
            )
            .route(
                "/api/split-upload",
                web::post().to(handlers::api_split_upload),
            )
            .route(
                "/api/split-profiles",
                web::get().to(handlers::list_split_profiles),
            )
            .route(
                "/api/split-profiles/{name}",
                web::get().to(handlers::get_split_profile),
            )
            .route(
                "/api/split-profiles",
                web::post().to(handlers::create_split_profile),
            )
            .route("/api/search", web::get().to(handlers::api_search))
            .route("/search", web::get().to(handlers::search_page))
            .route(
                "/api/search-results-bundle",
                web::post().to(handlers::api_search_results_bundle),
            )
            .route(
                "/api/search-results-chunks",
                web::post().to(handlers::api_search_results_chunks),
            )
            .route("/api/search-doc", web::get().to(handlers::search_doc))
            .route("/api/similar/{id}", web::get().to(handlers::api_similar))
            .route("/api/bundle", web::post().to(handlers::api_bundle))
            .route("/plugin/{name}/{id}", web::post().to(handlers::run_plugin))
            .route("/plugins", web::get().to(handlers::list_plugins))
            .route(
                "/api/nix-skill/analyze",
                web::post().to(handlers::nix_skill_analyze),
            )
            .route(
                "/api/nix-skill/find",
                web::post().to(handlers::nix_skill_find),
            )
            .route("/mcp", web::post().to(mcp_server::mcp_handler))
            .route("/git-browse", web::get().to(handlers::git_browse))
            .route(
                "/git-browse/{mount_id}",
                web::get().to(handlers::git_browse_mount),
            )
            .route(
                "/git-view/{mount_id}/{path:.*}",
                web::get().to(handlers::git_view_file),
            )
            .route("/api/git-search", web::get().to(handlers::api_git_search))
            .route("/api/git-index", web::get().to(handlers::api_git_index))
            .route(
                "/api/git-reindex",
                web::post().to(handlers::api_git_reindex),
            )
    })
    .bind(&bind)?
    .run()
    .await
}
