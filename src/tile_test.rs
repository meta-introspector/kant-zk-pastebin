// Tile detection and rendering tests — pure functions, no external dependencies.
// These test the auto-compose tile system that detects and renders tiles from pasted content.

#[cfg(test)]
mod tests {
    #[test]
    fn test_detect_plantuml_by_ext() {
        assert_eq!(crate::handlers::detect_tile_type("d.puml", "", ""), "plantuml");
    }
    #[test]
    fn test_detect_plantuml_by_content() {
        assert_eq!(crate::handlers::detect_tile_type("d", "", "@startuml"), "plantuml");
    }
    #[test]
    fn test_detect_graphviz_by_ext() {
        assert_eq!(crate::handlers::detect_tile_type("g.dot", "", ""), "graphviz");
    }
    #[test]
    fn test_detect_graphviz_by_content() {
        assert_eq!(crate::handlers::detect_tile_type("g", "", "digraph G {}"), "graphviz");
    }
    #[test]
    fn test_detect_minizinc_by_ext() {
        assert_eq!(crate::handlers::detect_tile_type("m.mzn", "", ""), "minizinc");
    }
    #[test]
    fn test_detect_minizinc_by_content() {
        assert_eq!(crate::handlers::detect_tile_type("m", "", "solve satisfy"), "minizinc");
    }
    #[test]
    fn test_detect_lean_by_ext() {
        assert_eq!(crate::handlers::detect_tile_type("p.lean", "", ""), "lean");
    }
    #[test]
    fn test_detect_lean_by_content() {
        assert_eq!(crate::handlers::detect_tile_type("p", "", "theorem t"), "lean");
    }
    #[test]
    fn test_detect_tulip_by_ext() {
        assert_eq!(crate::handlers::detect_tile_type("g.tlp", "", ""), "tulip");
    }
    #[test]
    fn test_detect_tulip_by_content() {
        assert_eq!(crate::handlers::detect_tile_type("g", "", "(nodes 0 1)"), "tulip");
    }
    #[test]
    fn test_detect_no_match() {
        assert_eq!(crate::handlers::detect_tile_type("notes.txt", "", "hello"), "");
    }

    #[test]
    fn test_render_plantuml() {
        let h = crate::handlers::render_tile_html("plantuml", "x", "/f", "t");
        assert!(h.contains("renderPlantUML"));
        assert!(h.contains("📐"));
    }
    #[test]
    fn test_render_graphviz() {
        let h = crate::handlers::render_tile_html("graphviz", "x", "/f", "t");
        assert!(h.contains("renderGraphViz"));
        assert!(h.contains("📊"));
    }
    #[test]
    fn test_render_minizinc() {
        let h = crate::handlers::render_tile_html("minizinc", "x", "/f", "t");
        assert!(h.contains("solveMiniZinc"));
        assert!(h.contains("🧮"));
    }
    #[test]
    fn test_render_lean() {
        let h = crate::handlers::render_tile_html("lean", "x", "/f", "t");
        assert!(h.contains("verifyLean"));
        assert!(h.contains("🏛️"));
    }
    #[test]
    fn test_render_tulip() {
        let h = crate::handlers::render_tile_html("tulip", "x", "/f", "t");
        assert!(h.contains("analyzeTulip"));
        assert!(h.contains("🔗"));
    }
    #[test]
    fn test_render_unknown_empty() {
        assert_eq!(crate::handlers::render_tile_html("nope", "x", "/f", "t"), "");
    }
    #[test]
    fn test_render_escapes_html() {
        let h = crate::handlers::render_tile_html("lean", "<script>", "/f", "t");
        assert!(!h.contains("<script>"));
        assert!(h.contains("&lt;"));
    }
}
