// ipld-query-tile — IPLD CAR store query interface
// Exports C-ABI functions for dynamic loading: tile_render, tile_free_result, tile_ping

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Render the tile view information as HTML for IPLD CID queries.
/// Input: null-terminated string (could be a CID).
fn tile_render_inner(input: &str) -> Result<String, String> {
    let cid = if input.is_empty() {
        "bafk26ced9e439f678632689aeae842da24c"
    } else {
        input
    };

    let html = format!(
        r#"<div class="ipld-query-tile">
            <h2>🔗 IPLD CID Query</h2>
            <p>Query IPFS CIDs from the IPLD CAR store with recursive resolution and metadata.</p>
            <div style="margin:10px 0">
                <input type="text" id="ipld-cid" placeholder="Enter CID (bafk..., Qm...)" value="{cid}" style="width:80%;padding:8px;font-family:monospace" />
                <button onclick="queryIPLD()">Query</button>
                <button onclick="resolveRecursive()">Resolve Recursive</button>
            </div>
            <div id="results" style="background:#111;padding:10px;margin:10px 0;max-height:400px;overflow:auto;font-family:monospace;font-size:0.9em"></div>
            <script>
            function queryIPLD() {{
                const cid = document.getElementById('ipld-cid').value.trim();
                if (!cid) return;
                fetch('/api/ipld/cid/' + encodeURIComponent(cid))
                    .then(r => r.json())
                    .then(data => {{
                        const results = document.getElementById('results');
                        results.innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
                    }})
                    .catch(e => {{
                        document.getElementById('results').innerHTML = '<span style="color:#f00">Error: ' + e + '</span>';
                    }});
            }}
            function resolveRecursive() {{
                const cid = document.getElementById('ipld-cid').value.trim();
                if (!cid) return;
                fetch('/api/ipld/resolve/' + encodeURIComponent(cid))
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
        cid
    );

    let headlines: Vec<serde_json::Value> = Vec::new();
    let result = serde_json::json!({
        "html": html,
        "title": "IPLD CID Query",
        "headlines": headlines,
        "meta": {
            "title": "IPLD CID Query",
            "cid": cid,
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