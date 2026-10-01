// approval-graph-tile — Tile for displaying the Hermes Agent approval system graph tile view
// Exports C-ABI functions for dynamic loading: tile_render, tile_free_result, tile_ping

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Render the tile view information as HTML + metadata.
/// Ignores input (could be used for configuration in the future).
fn tile_render_inner(_input: &str) -> Result<String, String> {
    // These CIDs are from the previous step: tile view of the approval system graph
    let tile_view_cid = option_env!("TILE_VIEW_CID")
        .unwrap_or("015512208a176826f4353838c4e91b1dd1e8dd4ce11ef80ca10020fcc366507de6994506");
    let graph_cid = option_env!("GRAPH_CID")
        .unwrap_or("01551220362e4bd9bf0dc074336c13403f635ee5a06eb6f71f37e78aeba508a257dae15f");

    let html = format!(
        r#"<div class=\"approval-graph-tile\">
            <h2>Hermes Agent Approval System Graph Tile View</h2>
            <p><strong>Tile View CID:</strong> {}</p>
            <p><strong>Original Graph CID:</strong> {}</p>
            <p><strong>Node Count:</strong> 684</p>
            <p><strong>Edge Count:</strong> 27,094</p>
        </div>"#,
        tile_view_cid, graph_cid
    );

    // Build result JSON similar to org-tile
    let headlines: Vec<serde_json::Value> = Vec::new();
    let result = serde_json::json!({
        "html": html,
        "title": "Approval Graph Tile View",
        "headlines": headlines,
        "meta": {
            "title": "Approval Graph Tile View",
            "tile_view_cid": tile_view_cid,
            "graph_cid": graph_cid,
            "node_count": 684,
            "edge_count": 27094
        },
    });

    Ok(result.to_string())
}

// ── C-ABI exports for dynamic loading ─────────────────────────────

/// Render the tile. Returns JSON string (caller must free via tile_free_result).
/// Input: null-terminated string (ignored in this implementation).
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
        Err(e) => CString::new(format!(r#"{{\"error\":\"{}\"}}"#, e))
            .unwrap()
            .into_raw(),
    }
}

/// Free memory allocated by tile_render.
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
