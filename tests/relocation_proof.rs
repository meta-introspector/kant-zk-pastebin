//! Relocation Proof Test
//!
//! Proves that the pastebin HTML is relocatable: when served behind a reverse proxy
//! with a BASE_PATH prefix (e.g., /pastebin/), all internal links resolve correctly.
//!
//! Strategy:
//!   1. Fetch each HTML page from the running server
//!   2. Extract all internal links (href, fetch(), window.open(), location=, action=)
//!   3. Verify every link starts with the expected BASE_PATH
//!   4. Verify the path after BASE_PATH matches a registered route
//!
//! This catches the class of bugs where a hardcoded path like `/splitter/` works
//! on localhost:8090 but 404s behind nginx at `/pastebin/splitter/`.
//!
//! Run:
//!   BASE_URL=http://127.0.0.1:8090 cargo test --test relocation_proof -- --nocapture

/// Base URL for the pastebin under test.
fn base_url() -> String {
    std::env::var("BASE_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:8090".to_string())
}

/// The BASE_PATH the server was started with.
/// Defaults to "/pastebin" since that's what the systemd service uses.
fn base_path() -> String {
    std::env::var("TEST_BASE_PATH")
        .unwrap_or_else(|_| "/pastebin".to_string())
}

/// All registered routes in the app (from main.rs).
/// These are the paths AFTER the BASE_PATH prefix.
/// Dynamic segments like {id} are normalized to {id} for matching.
fn registered_routes() -> Vec<&'static str> {
    vec![
        "/",
        "/browse",
        "/paste",
        "/paste/{id}",
        "/preview/{id}",
        "/raw/{id}",
        "/upgrade",
        "/thread/{id}",
        "/upload",
        "/file/{id}",
        "/ipfs/{cid}",
        "/gallery",
        "/gallery/img/{qid}",
        "/upload-archive",
        "/browse-archive/{session_id}",
        "/allm/{session_id}",
        "/archive-generate/{session_id}",
        "/archive-split/{session_id}",
        "/archive-preview/{session_id}/{idx}",
        "/archive-post-file/{session_id}/{idx}",
        "/splitter",
        "/api/split",
        "/api/split-upload",
        "/api/split-profiles",
        "/api/split-profiles/{name}",
        "/api/search",
        "/api/search-doc",
        "/api/similar/{id}",
        "/api/bundle",
        "/plugin/{name}/{id}",
        "/plugins",
        "/api/nix-skill/analyze",
        "/api/nix-skill/find",
        "/mcp",
        "/openapi.json",
        "/swagger-ui/",
        "/static/a11y.js",
    ]
}

/// Check if a path matches a registered route.
/// Dynamic segments like {id} match any non-empty segment.
/// Also handles "prefix routes" — paths like /api/similar/ that are JS concatenation
/// bases (the JS does `fetch(base + 'api/similar/' + id)`), so /api/similar/ is valid
/// as a prefix of the registered route /api/similar/{id}.
fn matches_route(path: &str) -> bool {
    let routes = registered_routes();
    
    // Exact match
    if routes.contains(&path) {
        return true;
    }
    
    // Try dynamic segment matching
    let path_segments: Vec<&str> = path.trim_end_matches('/')
        .split('/')
        .filter(|s| !s.is_empty())
        .collect();
    
    for route in &routes {
        let route_segments: Vec<&str> = route.trim_end_matches('/')
            .split('/')
            .filter(|s| !s.is_empty())
            .collect();
        
        if path_segments.len() != route_segments.len() {
            continue;
        }
        
        let mut matches = true;
        for (ps, rs) in path_segments.iter().zip(route_segments.iter()) {
            if rs.starts_with('{') && rs.ends_with('}') {
                continue; // dynamic segment matches anything non-empty
            }
            if ps != rs {
                matches = false;
                break;
            }
        }
        if matches {
            return true;
        }
    }
    
    // Prefix match: if the path is a prefix of a route with a dynamic segment,
    // it's a valid JS concatenation base (e.g., /api/similar/ is prefix of /api/similar/{id})
    for route in &routes {
        // Find routes that end with a dynamic segment
        if route.contains("/{") {
            let prefix = route.split("/{").next().unwrap();
            if path == prefix || path == format!("{}/", prefix) {
                return true;
            }
        }
    }
    
    false
}

/// Extract all quoted strings from text after a prefix pattern.
/// Simple string-based extraction — no regex needed.
fn extract_quoted_after(text: &str, prefix: &str) -> Vec<String> {
    let mut results = Vec::new();
    let mut search_from = 0;
    
    while let Some(pos) = text[search_from..].find(prefix) {
        let after = &text[search_from + pos + prefix.len()..];
        // Find the quote character used
        if let Some(quote_char) = after.chars().next() {
            if quote_char == '"' || quote_char == '\'' {
                if let Some(end) = after[1..].find(quote_char) {
                    results.push(after[1..end+1].to_string());
                }
            }
        }
        search_from += pos + prefix.len();
    }
    
    results
}

/// Extract all internal links from HTML.
/// Returns a list of (link_url, context_description) pairs.
fn extract_links(html: &str) -> Vec<(String, String)> {
    let mut links = Vec::new();
    
    // href="..." and href='...'
    for url in extract_quoted_after(html, "href=") {
        links.push((url, "href".to_string()));
    }
    
    // fetch('...' or fetch("..."
    for url in extract_quoted_after(html, "fetch(") {
        links.push((url, "fetch()".to_string()));
    }
    
    // window.open('...' or window.open("..."
    for url in extract_quoted_after(html, "window.open(") {
        links.push((url, "window.open()".to_string()));
    }
    
    // location = '...' or location = "..."
    for url in extract_quoted_after(html, "location =") {
        links.push((url, "location=".to_string()));
    }
    for url in extract_quoted_after(html, "location=") {
        links.push((url, "location=".to_string()));
    }
    
    // action="..."
    for url in extract_quoted_after(html, "action=") {
        links.push((url, "action".to_string()));
    }
    
    // <script src="...">
    for url in extract_quoted_after(html, "<script src=") {
        links.push((url, "script src".to_string()));
    }
    
    links
}

/// Classify a URL as internal (should be base_path-prefixed) or external/fragment.
fn is_internal_link(url: &str) -> bool {
    // Skip external URLs
    if url.starts_with("http://") || url.starts_with("https://") {
        return false;
    }
    // Skip data: URLs
    if url.starts_with("data:") {
        return false;
    }
    // Skip blob: URLs
    if url.starts_with("blob:") {
        return false;
    }
    // Skip pure fragments
    if url.starts_with('#') {
        return false;
    }
    // Skip javascript: URLs
    if url.starts_with("javascript:") {
        return false;
    }
    // Skip custom protocol URLs (erdfa:, etc.) — anything with : before /
    if url.contains(':') && !url.starts_with('/') && !url.starts_with("./") {
        return false;
    }
    true
}

/// Strip the base_path prefix from a URL and return the app-relative path.
fn strip_base_path<'a>(url: &'a str, base_path: &str) -> Option<&'a str> {
    if url.starts_with(base_path) {
        let rest = &url[base_path.len()..];
        if rest.is_empty() {
            return Some("/");
        }
        Some(rest)
    } else if url.starts_with('/') {
        // Link without base_path prefix — this is the bug we're catching!
        None
    } else {
        // Relative URL (like "api/split") — these are fine, they resolve relative to the page
        Some(url)
    }
}

/// Check a single page for relocation errors.
fn check_page_links(html: &str, page_name: &str, bp: &str) -> Vec<String> {
    let links = extract_links(html);
    let internal: Vec<_> = links.iter()
        .filter(|(url, _)| is_internal_link(url))
        .collect();
    
    eprintln!("  {}: {} total links, {} internal", page_name, links.len(), internal.len());
    
    let mut errors = Vec::new();
    
    for (url, context) in &internal {
        // Check 1: Does the link start with the base_path?
        if url.starts_with('/') && !url.starts_with(bp) {
            errors.push(format!(
                "MISSING BASE_PATH: '{}' ({}) — should start with '{}'",
                url, context, bp
            ));
            continue;
        }
        
        // Check 2: Does the path after base_path match a registered route?
        if let Some(app_path) = strip_base_path(url, bp) {
            // Skip relative URLs for route matching
            if !app_path.starts_with('/') {
                continue;
            }
            // Strip query string for route matching
            let path_only = app_path.split('?').next().unwrap();
            if !matches_route(path_only) {
                errors.push(format!(
                    "NO MATCHING ROUTE: '{}' ({}) — path '{}' not in registered routes",
                    url, context, path_only
                ));
            }
        }
    }
    
    errors
}

#[tokio::test]
async fn test_relocation_home_page() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let bp = base_path();
    let client = reqwest::Client::new();
    
    let resp = client.get(format!("{}/", base)).send().await?;
    assert!(resp.status().is_success(), "Home page should load");
    let html = resp.text().await?;
    
    let errors = check_page_links(&html, "home page", &bp);
    
    if !errors.is_empty() {
        for e in &errors { eprintln!("  ❌ {}", e); }
        panic!("Found {} relocation error(s) on home page", errors.len());
    }
    
    eprintln!("  ✅ All internal links on home page are correctly prefixed and resolve");
    Ok(())
}

#[tokio::test]
async fn test_relocation_paste_page() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let bp = base_path();
    let client = reqwest::Client::new();
    
    // Create a test paste
    let resp = client.post(format!("{}/paste", base))
        .header("Content-Type", "application/json")
        .body(r#"{"title":"relocation-test","content":"testing link relocation"}"#)
        .send().await?;
    assert!(resp.status().is_success(), "Paste creation should succeed");
    let body: serde_json::Value = resp.json().await?;
    let paste_id = body["id"].as_str().unwrap();
    
    // Fetch the paste view page
    let resp = client.get(format!("{}/paste/{}", base, paste_id)).send().await?;
    assert!(resp.status().is_success(), "Paste page should load");
    let html = resp.text().await?;
    
    let errors = check_page_links(&html, "paste page", &bp);
    
    if !errors.is_empty() {
        for e in &errors { eprintln!("  ❌ {}", e); }
        panic!("Found {} relocation error(s) on paste page", errors.len());
    }
    
    eprintln!("  ✅ All internal links on paste page are correctly prefixed and resolve");
    Ok(())
}

#[tokio::test]
async fn test_relocation_splitter_page() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let bp = base_path();
    let client = reqwest::Client::new();
    
    let resp = client.get(format!("{}/splitter", base)).send().await?;
    assert!(resp.status().is_success(), "Splitter page should load");
    let html = resp.text().await?;
    
    let errors = check_page_links(&html, "splitter page", &bp);
    
    if !errors.is_empty() {
        for e in &errors { eprintln!("  ❌ {}", e); }
        panic!("Found {} relocation error(s) on splitter page", errors.len());
    }
    
    eprintln!("  ✅ All internal links on splitter page are correctly prefixed and resolve");
    Ok(())
}

#[tokio::test]
async fn test_relocation_browse_page() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let bp = base_path();
    let client = reqwest::Client::new();
    
    let resp = client.get(format!("{}/browse", base)).send().await?;
    assert!(resp.status().is_success(), "Browse page should load");
    let html = resp.text().await?;
    
    let errors = check_page_links(&html, "browse page", &bp);
    
    if !errors.is_empty() {
        for e in &errors { eprintln!("  ❌ {}", e); }
        panic!("Found {} relocation error(s) on browse page", errors.len());
    }
    
    eprintln!("  ✅ All internal links on browse page are correctly prefixed and resolve");
    Ok(())
}

#[tokio::test]
async fn test_relocation_gallery_page() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let bp = base_path();
    let client = reqwest::Client::new();
    
    let resp = client.get(format!("{}/gallery", base)).send().await?;
    assert!(resp.status().is_success(), "Gallery page should load");
    let html = resp.text().await?;
    
    let errors = check_page_links(&html, "gallery page", &bp);
    
    if !errors.is_empty() {
        for e in &errors { eprintln!("  ❌ {}", e); }
        panic!("Found {} relocation error(s) on gallery page", errors.len());
    }
    
    eprintln!("  ✅ All internal links on gallery page are correctly prefixed and resolve");
    Ok(())
}

/// Comprehensive test: fetch ALL HTML pages and verify every internal link
/// is correctly base_path-prefixed and resolves to a registered route.
#[tokio::test]
async fn test_relocation_all_pages() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let bp = base_path();
    let client = reqwest::Client::new();
    
    // Create a test paste first (needed for paste view page)
    let resp = client.post(format!("{}/paste", base))
        .header("Content-Type", "application/json")
        .body(r#"{"title":"relocation-all-pages","content":"testing all pages"}"#)
        .send().await?;
    let body: serde_json::Value = resp.json().await?;
    let paste_id = body["id"].as_str().unwrap_or("unknown").to_string();
    
    // Pages to test
    let pages: Vec<(&str, &str)> = vec![
        ("/", "home page"),
        ("/browse", "browse page"),
        ("/splitter", "splitter page"),
        ("/gallery", "gallery page"),
    ];
    
    let mut total_errors = 0;
    let mut total_links = 0;
    let mut total_internal = 0;
    
    for (path, desc) in &pages {
        let resp = client.get(format!("{}{}", base, path)).send().await?;
        if !resp.status().is_success() {
            eprintln!("  ⚠️  {} ({}) returned {}", desc, path, resp.status());
            continue;
        }
        let html = resp.text().await?;
        
        let links = extract_links(&html);
        let internal_count = links.iter().filter(|(url, _)| is_internal_link(url)).count();
        total_links += links.len();
        total_internal += internal_count;
        
        let errors = check_page_links(&html, desc, &bp);
        
        if errors.is_empty() {
            eprintln!("  ✅ {}: {} internal links, all correct", desc, internal_count);
        } else {
            eprintln!("  ❌ {}: {} error(s)", desc, errors.len());
            for e in &errors { eprintln!("     {}", e); }
            total_errors += errors.len();
        }
    }
    
    // Also test paste view page
    let resp = client.get(format!("{}/paste/{}", base, paste_id)).send().await?;
    if resp.status().is_success() {
        let html = resp.text().await?;
        let errors = check_page_links(&html, "paste view page", &bp);
        if errors.is_empty() {
            eprintln!("  ✅ paste view page: all correct");
        } else {
            eprintln!("  ❌ paste view page: {} error(s)", errors.len());
            for e in &errors { eprintln!("     {}", e); }
            total_errors += errors.len();
        }
    }
    
    eprintln!("\n  Summary: {} total links, {} internal, {} errors", total_links, total_internal, total_errors);
    
    if total_errors > 0 {
        panic!("Found {} relocation error(s) across all pages", total_errors);
    }
    
    Ok(())
}

/// Regression test: verify that the specific bugs we fixed don't come back.
/// These are the exact paths that were hardcoded and broke behind nginx.
#[tokio::test]
async fn test_relocation_regression_hardcoded_paths() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let bp = base_path();
    let client = reqwest::Client::new();
    
    // Create a test paste
    let resp = client.post(format!("{}/paste", base))
        .header("Content-Type", "application/json")
        .body(r#"{"title":"regression-test","content":"regression test content"}"#)
        .send().await?;
    let body: serde_json::Value = resp.json().await?;
    let paste_id = body["id"].as_str().unwrap_or("unknown");
    
    // Fetch the paste view page
    let resp = client.get(format!("{}/paste/{}", base, paste_id)).send().await?;
    let html = resp.text().await?;
    
    // These are the exact patterns that were broken before the fix:
    // They used hardcoded paths like /splitter/ instead of {base_path}/splitter/
    
    let bad_patterns: &[(&str, &str)] = &[
        // Split button on paste view: was window.open('/splitter/','_blank')
        ("window.open('/splitter/'", "Split button on paste view uses hardcoded /splitter/"),
        // Nav link: was href="/splitter/"
        ("href=\"/splitter/\"", "Nav link uses hardcoded /splitter/"),
        // Reply button: was href="/?reply_to=..."
        ("href=\"/?reply_to=", "Reply button uses hardcoded /?reply_to="),
        // Similar API: was fetch('/api/similar/')
        ("fetch('/api/similar/", "Similar API fetch uses hardcoded /api/similar/"),
        // Bundle API: was fetch('/api/bundle')
        ("fetch('/api/bundle", "Bundle API fetch uses hardcoded /api/bundle"),
    ];
    
    let mut errors = Vec::new();
    
    for (pattern, description) in bad_patterns {
        if html.contains(pattern) {
            errors.push(format!(
                "REGRESSION: {} — found hardcoded pattern '{}' (should use base_path prefix '{}')",
                description, pattern, bp
            ));
        }
    }
    
    // Also check the home page
    let resp = client.get(format!("{}/", base)).send().await?;
    let html = resp.text().await?;
    
    let home_bad_patterns: &[(&str, &str)] = &[
        // Home page sendToSplitter: was window.open('/splitter/', '_blank')
        ("window.open('/splitter/'", "Home page Split button uses hardcoded /splitter/"),
        // Nav link: was href="/splitter/"
        ("href=\"/splitter/\"", "Home page nav link uses hardcoded /splitter/"),
    ];
    
    for (pattern, description) in home_bad_patterns {
        if html.contains(pattern) {
            errors.push(format!(
                "REGRESSION: {} — found hardcoded pattern '{}' (should use base_path prefix '{}')",
                description, pattern, bp
            ));
        }
    }
    
    if !errors.is_empty() {
        for e in &errors { eprintln!("  ❌ {}", e); }
        panic!("Found {} regression(s) — hardcoded paths are back!", errors.len());
    }
    
    eprintln!("  ✅ No hardcoded path regressions detected");
    Ok(())
}
