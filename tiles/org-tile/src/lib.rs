// org-tile — Render org-mode content to HTML
// Uses orgize 0.10 native Rust parser (no subprocess)
// Exports C-ABI functions for dynamic loading: render_org(), free_org_result(), org_tile_ping()

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Render org-mode content to HTML + metadata JSON.
///
/// Input: JSON string {"content": "..."}
/// Output: JSON string {
///   "html": "<div class=\"org-content\">...",
///   "title": "Document Title",
///   "headlines": [{"level":1,"title":"Section 1","children":[...]}],
///   "meta": {"title":"...", "author":"...", "date":"..."}
/// }
fn render_org_inner(input: &str) -> Result<String, String> {
    // Parse input JSON for the content field
    // Extract to owned String to avoid borrow issues
    let content_owned = if let Ok(val) = serde_json::from_str::<serde_json::Value>(input) {
        val.get("content")
            .and_then(|c| c.as_str())
            .map(|c| c.to_string())
            .unwrap_or_else(|| input.to_string())
    } else {
        // If not JSON, treat the whole input as org content
        input.to_string()
    };
    let content: &str = &content_owned;

    // Parse org-mode text
    let org = orgize::Org::parse(content);

    // Convert to HTML using built-in html export
    let html_body = org.to_html();

    // Extract metadata from raw text
    let mut title = String::new();
    let mut author = String::new();
    let mut date = String::new();
    let mut tags: Vec<String> = Vec::new();

    for line in content.lines() {
        if let Some(val) = line.strip_prefix("#+TITLE:") {
            title = val.trim().to_string();
        } else if let Some(val) = line.strip_prefix("#+AUTHOR:") {
            author = val.trim().to_string();
        } else if let Some(val) = line.strip_prefix("#+DATE:") {
            date = val.trim().to_string();
        } else if let Some(val) = line.strip_prefix("#+FILETAGS:") {
            tags = val.split_whitespace().map(|s| s.trim().to_string()).collect();
        }
    }

    // Extract headline structure for navigation
    let doc = org.document();
    let mut headlines: Vec<serde_json::Value> = Vec::new();
    for hdl in doc.headlines() {
        let level = hdl.level();
        let raw_title = hdl.title_raw().trim().to_string();
        headlines.push(serde_json::json!({
            "level": level,
            "title": raw_title,
        }));
    }

    // Build result JSON
    let result = serde_json::json!({
        "html": format!("<div class=\"org-content\">{}</div>", html_body),
        "title": title,
        "headlines": headlines,
        "meta": {
            "title": title,
            "author": author,
            "date": date,
            "tags": tags,
        },
    });

    Ok(result.to_string())
}

// ── C-ABI exports for dynamic loading ─────────────────────────────

/// Render org-mode content. Returns JSON string (caller must free via free_org_result).
/// Input: null-terminated JSON string with "content" field, or raw org text.
#[no_mangle]
pub extern "C" fn tile_render(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        let err = CString::new(r#"{"error":"null input"}"#).unwrap();
        return err.into_raw();
    }

    let c_str = unsafe { CStr::from_ptr(input) };
    let input_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => {
            let err = CString::new(r#"{"error":"invalid UTF-8"}"#).unwrap();
            return err.into_raw();
        }
    };

    match render_org_inner(input_str) {
        Ok(output) => CString::new(output).unwrap().into_raw(),
        Err(e) => CString::new(format!(r#"{{"error":"{}"}}"#, e))
            .unwrap()
            .into_raw(),
    }
}

/// Free memory allocated by render_org.
#[no_mangle]
pub extern "C" fn tile_free_result(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Health check — returns 1 if tile is operational.
#[no_mangle]
pub extern "C" fn tile_ping() -> i32 {
    1
}
