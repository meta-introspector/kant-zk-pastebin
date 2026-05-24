// Standalone tile detection tests — no library dependency needed
// Run: cargo test --test tile_tests

/// Duplicate of the detect_tile_type logic for testing
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
    let trimmed = content.trim();
    if trimmed.starts_with("@startuml") || trimmed.starts_with("@startdot") { return "plantuml"; }
    if trimmed.starts_with("digraph") || trimmed.starts_with("graph ") { return "graphviz"; }
    if trimmed.contains("constraint ") || trimmed.contains("solve satisfy") { return "minizinc"; }
    if trimmed.starts_with("theorem") || trimmed.starts_with("lemma") || trimmed.starts_with("def ") { return "lean"; }
    if trimmed.starts_with("(nodes ") || trimmed.starts_with("(TLP") { return "tulip"; }
    ""
}

/// Render tile HTML — logic duplicated for standalone testing
fn render_tile_html(tile_type: &str, content: &str, file_url: &str, title: &str) -> String {
    let escaped = content.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    match tile_type {
        "plantuml" => format!(
            r#"<div class="tile" data-tile="plantuml"><h3>📐 PlantUML: {}</h3><pre style="max-height:200px;overflow:auto">{}</pre><button onclick="renderPlantUML(this)">▶ Render Diagram</button><div class="tile-output"></div></div>"#,
            title, escaped),
        "graphviz" => format!(
            r#"<div class="tile" data-tile="graphviz"><h3>📊 Graphviz: {}</h3><pre style="max-height:200px;overflow:auto">{}</pre><button onclick="renderGraphViz(this)">▶ Render Graph</button><div class="tile-output"></div></div>"#,
            title, escaped),
        "minizinc" => format!(
            r#"<div class="tile" data-tile="minizinc"><h3>🧮 MiniZinc: {}</h3><pre style="max-height:200px;overflow:auto">{}</pre><button onclick="solveMiniZinc(this)">▶ Solve</button><div class="tile-output"></div></div>"#,
            title, escaped),
        "lean" => format!(
            r#"<div class="tile" data-tile="lean"><h3>🏛️ Lean: {}</h3><pre style="max-height:200px;overflow:auto">{}</pre><button onclick="verifyLean(this)">▶ Verify</button><div class="tile-output"></div></div>"#,
            title, escaped),
        "tulip" => format!(
            r#"<div class="tile" data-tile="tulip"><h3>🔗 Tulip Graph: {}</h3><pre style="max-height:200px;overflow:auto">{}</pre><button onclick="analyzeTulip(this)">▶ Analyze</button><div class="tile-output"></div></div>"#,
            title, escaped),
        _ => String::new(),
    }
}

// ── Tests ──

#[test]
fn test_detect_plantuml_ext() { assert_eq!(detect_tile_type("d.puml", "", ""), "plantuml"); }
#[test]
fn test_detect_plantuml_content() { assert_eq!(detect_tile_type("d", "", "@startuml"), "plantuml"); }
#[test]
fn test_detect_graphviz_ext() { assert_eq!(detect_tile_type("g.dot", "", ""), "graphviz"); }
#[test]
fn test_detect_graphviz_content() { assert_eq!(detect_tile_type("g", "", "digraph G {}"), "graphviz"); }
#[test]
fn test_detect_minizinc_ext() { assert_eq!(detect_tile_type("m.mzn", "", ""), "minizinc"); }
#[test]
fn test_detect_minizinc_content() { assert_eq!(detect_tile_type("m", "", "solve satisfy;"), "minizinc"); }
#[test]
fn test_detect_lean_ext() { assert_eq!(detect_tile_type("p.lean", "", ""), "lean"); }
#[test]
fn test_detect_lean_content() { assert_eq!(detect_tile_type("p", "", "theorem t"), "lean"); }
#[test]
fn test_detect_tulip_ext() { assert_eq!(detect_tile_type("g.tlp", "", ""), "tulip"); }
#[test]
fn test_detect_tulip_content() { assert_eq!(detect_tile_type("g", "", "(nodes 0 1)"), "tulip"); }
#[test]
fn test_detect_none() { assert_eq!(detect_tile_type("n.txt", "", "hi"), ""); }

#[test]
fn test_render_plantuml() { let h = render_tile_html("plantuml", "x", "/f", "t"); assert!(h.contains("renderPlantUML")); assert!(h.contains("📐")); }
#[test]
fn test_render_graphviz() { let h = render_tile_html("graphviz", "x", "/f", "t"); assert!(h.contains("renderGraphViz")); assert!(h.contains("📊")); }
#[test]
fn test_render_minizinc() { let h = render_tile_html("minizinc", "x", "/f", "t"); assert!(h.contains("solveMiniZinc")); assert!(h.contains("🧮")); }
#[test]
fn test_render_lean() { let h = render_tile_html("lean", "x", "/f", "t"); assert!(h.contains("verifyLean")); assert!(h.contains("🏛️")); }
#[test]
fn test_render_tulip() { let h = render_tile_html("tulip", "x", "/f", "t"); assert!(h.contains("analyzeTulip")); assert!(h.contains("🔗")); }
#[test]
fn test_render_unknown() { assert_eq!(render_tile_html("nope", "x", "/f", "t"), ""); }
#[test]
fn test_render_escapes() { let h = render_tile_html("lean", "<script>", "/f", "t"); assert!(!h.contains("<script>")); assert!(h.contains("&lt;")); }
