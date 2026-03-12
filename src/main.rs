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
    
    let openapi = ApiDoc::openapi();
    
    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);
            
        App::new()
            .wrap(cors)
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
    })
    .bind(&bind)?
    .run()
    .await
}
