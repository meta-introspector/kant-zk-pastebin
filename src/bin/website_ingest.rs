use html5ever::parse_document;
use html5ever::tendril::TendrilSink;
use markup5ever_rcdom::RcDom;
use oxc_allocator::Allocator;
use oxc_parser::Parser;
use oxc_span::SourceType;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::Path;

#[derive(Serialize, Deserialize)]
struct WebsiteArtifact {
    html_files: Vec<HtmlFile>,
    css_files: Vec<CssFile>,
    js_files: Vec<JsFile>,
    static_assets: Vec<StaticAsset>,
}

#[derive(Serialize, Deserialize)]
struct HtmlFile {
    path: String,
    coords: Vec<u64>,
    node_count: usize,
}

#[derive(Serialize, Deserialize)]
struct CssFile {
    path: String,
    coords: Vec<u64>,
    rule_count: usize,
}

#[derive(Serialize, Deserialize)]
struct JsFile {
    path: String,
    coords: Vec<u64>,
    statement_count: usize,
}

#[derive(Serialize, Deserialize)]
struct StaticAsset {
    path: String,
    size: u64,
    coords: Vec<u64>,
}

#[zkperf_macros::witness_boundary(complexity = "K0:scalar", max_n = 1, max_ms = 250)]
fn ingest_html(path: &Path) -> HtmlFile {
    let html = fs::read_to_string(path).expect("read html");
    let dom = parse_document(RcDom::default(), Default::default())
        .from_utf8()
        .read_from(&mut html.as_bytes())
        .unwrap();
    
    let coords = erdfa_dasl::orbifold_coords_full(html.len());
    
    HtmlFile {
        path: path.display().to_string(),
        coords: coords[..3].to_vec(),
        node_count: html.len(),
    }
}

#[zkperf_macros::witness_boundary(complexity = "K0:scalar", max_n = 1, max_ms = 230)]
fn ingest_js(path: &Path) -> JsFile {
    let source = fs::read_to_string(path).expect("read js");
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(path).unwrap_or_default();
    let ret = Parser::new(&allocator, &source, source_type).parse();
    
    let coords = erdfa_dasl::orbifold_coords_full(source.len());
    
    JsFile {
        path: path.display().to_string(),
        coords: coords[..3].to_vec(),
        statement_count: ret.program.body.len(),
    }
}

#[zkperf_macros::witness_boundary(complexity = "K0:scalar", max_n = 1, max_ms = 190)]
fn ingest_css(path: &Path) -> CssFile {
    let css = fs::read_to_string(path).expect("read css");
    let coords = erdfa_dasl::orbifold_coords_full(css.len());
    
    CssFile {
        path: path.display().to_string(),
        coords: coords[..3].to_vec(),
        rule_count: css.lines().count(),
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: website_ingest <static_dir>");
        eprintln!("\nIngests HTML/CSS/JS and assigns Monster orbifold coords.");
        std::process::exit(1);
    }

    let static_dir = Path::new(&args[1]);
    let mut artifact = WebsiteArtifact {
        html_files: vec![],
        css_files: vec![],
        js_files: vec![],
        static_assets: vec![],
    };

    // Scan directory
    for entry in fs::read_dir(static_dir).expect("read dir") {
        let entry = entry.expect("entry");
        let path = entry.path();
        
        if let Some(ext) = path.extension() {
            match ext.to_str() {
                Some("html") => artifact.html_files.push(ingest_html(&path)),
                Some("js") => artifact.js_files.push(ingest_js(&path)),
                Some("css") => artifact.css_files.push(ingest_css(&path)),
                _ => {}
            }
        }
    }

    println!("Ingested:");
    println!("  {} HTML files", artifact.html_files.len());
    println!("  {} CSS files", artifact.css_files.len());
    println!("  {} JS files", artifact.js_files.len());
    
    // Output CBOR
    let cbor = serde_cbor::to_vec(&artifact).expect("serialize");
    fs::write("website_artifact.cbor", cbor).expect("write cbor");
    println!("\nWrote website_artifact.cbor");
}
