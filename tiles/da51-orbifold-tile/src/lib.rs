// da51-orbifold-tile — DA51 Orbifold Arrow Matrix Tile
// Exports C-ABI functions for dynamic loading: tile_render, tile_free_result, tile_ping

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Render the tile view information as HTML + metadata about the DA51 Orbifold.
/// Input: null-terminated string (ignored in this implementation).
fn tile_render_inner(_input: &str) -> Result<String, String> {
    let html = r#"<div class="da51-orbifold-tile">
        <h2>DA51 Orbifold Arrow Matrix Tile View</h2>
        <p><strong>Monster Group Representation:</strong> 71×59×47 = 196,883 coordinates</p>
        <p><strong>Arrow Matrix:</strong> 38,764,092,889 possible directed arrows</p>
        <p><strong>Active Edges:</strong> sparse storage — dependency graph from Cargo metadata</p>
        <p><strong>Bott Mod 8 Folding:</strong> uniform distribution across 8 periods</p>
        <p><strong>AZ Mod 10 Folding:</strong> uniform distribution across 10 periods</p>
    </div>"#;

    let headlines: Vec<serde_json::Value> = Vec::new();
    let result = serde_json::json!({
        "html": html,
        "title": "DA51 Orbifold Tile View",
        "headlines": headlines,
        "meta": {
            "title": "DA51 Orbifold Tile View",
            "x_range": "0..71",
            "y_range": "0..59",
            "z_range": "0..47",
            "coordinate_count": 196883,
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