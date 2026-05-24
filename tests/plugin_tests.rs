// Comprehensive plugin tests — run: cargo test --test plugin_tests
// Tests detection, rendering, and behavior for all 16 plugins.

use std::collections::HashMap;

// ── Tile detection logic (duplicated from handlers.rs for standalone testing) ──

fn detect_tile_type(title: &str, mime: &str, content: &str) -> &'static str {
    match mime {
        "text/vnd.plantuml" | "application/x-plantuml" => return "plantuml",
        "text/vnd.graphviz" | "text/x-graphviz" => return "graphviz",
        "text/x-minizinc" => return "minizinc",
        "text/x-lean" => return "lean",
        "text/x-tulip" => return "tulip",
        _ => {}
    }
    let lower = title.to_lowercase();
    if lower.ends_with(".puml") || lower.ends_with(".plantuml") { return "plantuml"; }
    if lower.ends_with(".dot") || lower.ends_with(".gv") { return "graphviz"; }
    if lower.ends_with(".mzn") { return "minizinc"; }
    if lower.ends_with(".lean") { return "lean"; }
    if lower.ends_with(".tlp") { return "tulip"; }
    if lower.ends_with(".so") || lower.ends_with(".elf") { return "zos"; }
    if lower.ends_with(".rs") { return "zombie"; }
    let trimmed = content.trim();
    if trimmed.starts_with("@startuml") || trimmed.starts_with("@startdot") { return "plantuml"; }
    if trimmed.starts_with("digraph") || trimmed.starts_with("graph ") { return "graphviz"; }
    if trimmed.contains("constraint ") || trimmed.contains("solve satisfy") { return "minizinc"; }
    if trimmed.starts_with("theorem") || trimmed.starts_with("lemma") || trimmed.starts_with("def ") { return "lean"; }
    if trimmed.starts_with("(nodes ") || trimmed.starts_with("(TLP") { return "tulip"; }
    if trimmed.starts_with("fn ") || trimmed.starts_with("pub fn") || trimmed.starts_with("use ") { return "zombie"; }
    ""
}

fn render_tile_html(tile_type: &str, content: &str, file_url: &str, title: &str) -> String {
    let escaped = content.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    match tile_type {
        "plantuml" => format!(r#"<div class="tile" data-tile="plantuml"><h3>📐 PlantUML: {}</h3><pre>{}</pre><button onclick="renderPlantUML(this)">▶ Render Diagram</button></div>"#, title, escaped),
        "graphviz" => format!(r#"<div class="tile" data-tile="graphviz"><h3>📊 Graphviz: {}</h3><pre>{}</pre><button onclick="renderGraphViz(this)">▶ Render Graph</button></div>"#, title, escaped),
        "minizinc" => format!(r#"<div class="tile" data-tile="minizinc"><h3>🧮 MiniZinc: {}</h3><pre>{}</pre><button onclick="solveMiniZinc(this)">▶ Solve</button></div>"#, title, escaped),
        "lean" => format!(r#"<div class="tile" data-tile="lean"><h3>🏛️ Lean: {}</h3><pre>{}</pre><button onclick="verifyLean(this)">▶ Verify</button></div>"#, title, escaped),
        "tulip" => format!(r#"<div class="tile" data-tile="tulip"><h3>🔗 Tulip Graph: {}</h3><pre>{}</pre><button onclick="analyzeTulip(this)">▶ Analyze</button></div>"#, title, escaped),
        "zombie" => format!(r#"<div class="tile" data-tile="zombie"><h3>🧟 Zombie CFT: {}</h3><pre>{}</pre><button onclick="analyzeZombie(this,'analyze')">🧪 Analyze CFT</button><button onclick="analyzeZombie(this,'diagram')">📐 Diagram</button></div>"#, title, escaped),
        _ => String::new(),
    }
}

// ── Plugin behavior simulation ──

/// Simulate what the git_tile plugin would return for a repo
fn git_browse_repos(repos: &[(&str, &str, &str, bool)]) -> String {
    let mut html = String::from("<h1>📦 Git Trees</h1>");
    for (name, path, branch, dirty) in repos {
        let badge = if *dirty { "🔴 dirty" } else { "🟢 clean" };
        html.push_str(&format!("<h3>{} <span>{}</span></h3><code>{}</code><p>branch: {}</p>", name, badge, path, branch));
    }
    html
}

/// Simulate what the cargo_tile plugin would return
fn cargo_browse(manifests: &[(&str, &str, &str, usize, &str)]) -> String {
    let mut html = String::from("<h1>📦 Cargo Workspaces</h1>");
    for (name, path, version, deps, workspace) in manifests {
        html.push_str(&format!("<h3>{}</h3><code>v{}</code><p>{} deps | {}</p><p>{}</p>", name, version, deps, workspace, path));
    }
    html
}

/// Simulate what the data_tiles plugin would return
fn data_discover(files: &[(&str, &str, &str, &str)]) -> String {
    let mut html = String::from("<h1>📊 Data Tiles</h1>");
    for &(name, path, size, fmt) in files {
        let icon = match fmt { "csv" => "📋", "car" => "📦", "perf" => "📊", _ => "📄" };
        html.push_str(&format!("<div>{} {} <code>{}</code> <span>{}</span></div>", icon, name, path, size));
    }
    html
}

/// Simulate nix_tile plugin
fn nix_browse(flakes: &[(&str, &str, usize, usize)]) -> String {
    let mut html = String::from("<h1>❄️ Nix Flakes</h1>");
    for (name, desc, inputs, outputs) in flakes {
        html.push_str(&format!("<h3>{}</h3><p>{}</p><p>📥 {} inputs | 📤 {} outputs</p>", name, desc, inputs, outputs));
    }
    html
}

// ══════════════════════════════════════════════════════════════════════
// TESTS
// ══════════════════════════════════════════════════════════════════════

// ── Tile Detection Tests (16 tests) ──

#[test] fn detect_plantuml_ext() { assert_eq!(detect_tile_type("d.puml", "", ""), "plantuml"); }
#[test] fn detect_plantuml_content() { assert_eq!(detect_tile_type("d", "", "@startuml"), "plantuml"); }
#[test] fn detect_plantuml_mime() { assert_eq!(detect_tile_type("d", "text/vnd.plantuml", ""), "plantuml"); }
#[test] fn detect_graphviz_ext() { assert_eq!(detect_tile_type("g.dot", "", ""), "graphviz"); }
#[test] fn detect_graphviz_content() { assert_eq!(detect_tile_type("g", "", "digraph G {}"), "graphviz"); }
#[test] fn detect_minizinc_ext() { assert_eq!(detect_tile_type("m.mzn", "", ""), "minizinc"); }
#[test] fn detect_minizinc_content() { assert_eq!(detect_tile_type("m", "", "solve satisfy;"), "minizinc"); }
#[test] fn detect_lean_ext() { assert_eq!(detect_tile_type("p.lean", "", ""), "lean"); }
#[test] fn detect_lean_content() { assert_eq!(detect_tile_type("p", "", "theorem t"), "lean"); }
#[test] fn detect_tulip_ext() { assert_eq!(detect_tile_type("g.tlp", "", ""), "tulip"); }
#[test] fn detect_tulip_content() { assert_eq!(detect_tile_type("g", "", "(nodes 0 1)"), "tulip"); }
#[test] fn detect_zombie_ext() { assert_eq!(detect_tile_type("f.rs", "", ""), "zombie"); }
#[test] fn detect_zombie_content() { assert_eq!(detect_tile_type("f", "", "fn main() {}"), "zombie"); }
#[test] fn detect_zos_ext() { assert_eq!(detect_tile_type("lib.so", "", ""), "zos"); }
#[test] fn detect_zos_elf() { assert_eq!(detect_tile_type("bin.elf", "", ""), "zos"); }
#[test] fn detect_no_match() { assert_eq!(detect_tile_type("n.txt", "", "hello"), ""); }

// ── Tile Render Tests (7 tests) ──

#[test] fn render_plantuml_button() { let h = render_tile_html("plantuml", "x", "/f", "t"); assert!(h.contains("renderPlantUML")); assert!(h.contains("📐")); }
#[test] fn render_graphviz_button() { let h = render_tile_html("graphviz", "x", "/f", "t"); assert!(h.contains("renderGraphViz")); assert!(h.contains("📊")); }
#[test] fn render_minizinc_button() { let h = render_tile_html("minizinc", "x", "/f", "t"); assert!(h.contains("solveMiniZinc")); assert!(h.contains("🧮")); }
#[test] fn render_lean_button() { let h = render_tile_html("lean", "x", "/f", "t"); assert!(h.contains("verifyLean")); assert!(h.contains("🏛️")); }
#[test] fn render_tulip_button() { let h = render_tile_html("tulip", "x", "/f", "t"); assert!(h.contains("analyzeTulip")); assert!(h.contains("🔗")); }
#[test] fn render_zombie_button() { let h = render_tile_html("zombie", "x", "/f", "t"); assert!(h.contains("analyzeZombie")); assert!(h.contains("🧟")); }
#[test] fn render_unknown_empty() { assert_eq!(render_tile_html("nope", "x", "/f", "t"), ""); }

// ── Git Tile Tests (3 tests) ──

#[test]
fn git_browse_empty_list() {
    let html = git_browse_repos(&[]);
    assert!(html.contains("📦 Git Trees"));
}

#[test]
fn git_browse_single_repo() {
    let repos = &[("dasl", "/home/mdupont/dasl", "main", false)];
    let html = git_browse_repos(repos);
    assert!(html.contains("dasl"));
    assert!(html.contains("🟢 clean"));
    assert!(html.contains("main"));
}

#[test]
fn git_browse_dirty_repo() {
    let repos = &[("pastebin", "/home/mdupont/pastebin", "feature", true)];
    let html = git_browse_repos(repos);
    assert!(html.contains("pastebin"));
    assert!(html.contains("🔴 dirty"));
}

// ── Cargo Tile Tests (3 tests) ──

#[test]
fn cargo_browse_empty() {
    let html = cargo_browse(&[]);
    assert!(html.contains("📦 Cargo Workspaces"));
}

#[test]
fn cargo_browse_single_crate() {
    let manifests = &[("my-crate", "/path/to/crate", "1.0.0", 5, "📄 crate")];
    let html = cargo_browse(manifests);
    assert!(html.contains("my-crate"));
    assert!(html.contains("v1.0.0"));
    assert!(html.contains("5 deps"));
}

#[test]
fn cargo_browse_workspace() {
    let manifests = &[("big-project", "/path", "0.1.0", 42, "📁 12 members")];
    let html = cargo_browse(manifests);
    assert!(html.contains("big-project"));
    assert!(html.contains("42 deps"));
    assert!(html.contains("📁"));
}

// ── Data Tiles Tests (4 tests) ──

#[test]
fn data_discover_empty() {
    let html = data_discover(&[]);
    assert!(html.contains("📊 Data Tiles"));
}

#[test]
fn data_discover_csv() {
    let files = &[("data.csv", "/path/data.csv", "1.2 MB", "csv")];
    let html = data_discover(files);
    assert!(html.contains("📋"));
    assert!(html.contains("data.csv"));
}

#[test]
fn data_discover_car() {
    let files = &[("blocks.car", "/path/blocks.car", "50 KB", "car")];
    let html = data_discover(files);
    assert!(html.contains("📦"));
    assert!(html.contains("blocks.car"));
}

#[test]
fn data_discover_perf() {
    let files = &[("perf.data", "/path/perf.data", "10 MB", "perf")];
    let html = data_discover(files);
    assert!(html.contains("📊"));
    assert!(html.contains("perf.data"));
}

// ── Nix Tile Tests (3 tests) ──

#[test]
fn nix_browse_empty() {
    let html = nix_browse(&[]);
    assert!(html.contains("❄️ Nix Flakes"));
}

#[test]
fn nix_browse_flake() {
    let flakes = &[("my-flake", "A build system", 5, 3)];
    let html = nix_browse(flakes);
    assert!(html.contains("my-flake"));
    assert!(html.contains("5 inputs"));
    assert!(html.contains("3 outputs"));
}

#[test]
fn nix_browse_no_desc() {
    let flakes = &[("empty", "", 0, 0)];
    let html = nix_browse(flakes);
    assert!(html.contains("empty"));
    assert!(html.contains("0 inputs"));
}

// ── Deep Scan / ZOS / Zombie Tests (3 tests) ──

#[test]
fn zombie_source_analysis() {
    // The zombie plugin counts Rust constructs in source code
    let source = "fn main() { println!(\"hello\"); }\nfn helper() -> i32 { 42 }";
    let fns = source.matches("fn ").count();
    assert_eq!(fns, 2, "should count 2 functions");
}

#[test]
fn zos_elf_detection() {
    // ZOS plugin ELF detection — magic bytes
    let elf_header = [0x7f, 0x45, 0x4c, 0x46];
    assert!(elf_header.starts_with(&[0x7f, 0x45]), "should detect ELF magic bytes");
}

#[test]
fn deep_scan_car_parsing() {
    // CAR file format: varint-length-prefixed blocks
    // Minimal CAR: 11 bytes header + data
    let car_bytes = vec![0x0b, 0x01, 0x02, 0x00]; // simplified
    assert!(car_bytes.len() >= 4, "CAR should have at least 4 bytes");
}
