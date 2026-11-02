// sparql-query-tile — SPARQL query interface for pastebin CID resolution
// Exports C-ABI functions for dynamic loading: tile_render, tile_free_result, tile_ping

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Render the tile view information as HTML for CID search/filtering.
/// Input: null-terminated string (could be a CID or query in the future).
fn tile_render_inner(input: &str) -> Result<String, String> {
    let query = if input.is_empty() {
        "SELECT * WHERE { ?s ?p ?o } LIMIT 10"
    } else {
        input
    };

    let html = format!(
        r#"<div class="sparql-query-tile">
            <h2>🔍 CID Search & SPARQL Query</h2>
            <p>Search recent pastes by CID or content using recursive SPARQL queries over the IPLD CAR store.</p>
            <div style="margin:10px 0">
                <input type="text" id="cid-search" placeholder="Enter CID (bafk..., Qm...) or SPARQL query" style="width:80%;padding:8px;font-family:monospace" />
                <button onclick="searchCID()">Search</button>
            </div>
            <div id="results" style="background:#111;padding:10px;margin:10px 0;max-height:400px;overflow:auto;font-family:monospace;font-size:0.9em"></div>
            <script>
            function searchCID() {{
                const cid = document.getElementById('cid-search').value.trim();
                if (!cid) return;
                fetch('/api/cid-search?q=' + encodeURIComponent(cid))
                    .then(r => r.json())
                    .then(data => {{
                        const results = document.getElementById('results');
                        results.innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
                    }})
                    .catch(e => {{
                        document.getElementById('results').innerHTML = '<span style="color:#f00">Error: ' + e + '</span>';
                    }});
            }}
            </script>
        </div>"#,
        query
    );

    let headlines: Vec<serde_json::Value> = Vec::new();
    let result = serde_json::json!({
        "html": html,
        "title": "CID Search & SPARQL Query",
        "headlines": headlines,
        "meta": {
            "title": "CID Search & SPARQL Query",
            "query": query,
        },
    });

    Ok(result.to_string())
}

// ── C-ABI exports for dynamic loading ─────────────────────────────

#[no_mangle]
pub extern "C" fn tile_render(input: *const c_char) -> *mut c_char {
    let input_str = if input.is_null() {
        ""
    } else {
        let c_str = unsafe { CStr::from_ptr(input) };
        c_str.to_str().unwrap_or("")
    };

    match tile_render_inner(input_str) {
        Ok(output) => CString::new(output).unwrap().into_raw(),
        Err(e) => CString::new(format!(r#"{{"error":"{}"}}"#, e))
            .unwrap()
            .into_raw(),
    }
}

#[no_mangle]
pub extern "C" fn tile_free_result(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn tile_ping() -> i32 {
    1
}