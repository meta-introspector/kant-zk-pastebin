// Resvg Render Tile — renders SVG content to PNG via C-ABI plugin interface.
// Loaded dynamically by the pastebin tile loader.

use std::ffi::CString;
use std::os::raw::{c_char, c_int};

use resvg::tiny_skia::Pixmap;
use resvg::usvg::Tree;
use resvg::usvg::{Options, Transform};

/// C-ABI: verify tile is alive. Returns 1.
#[no_mangle]
pub extern "C" fn tile_ping() -> c_int {
    1
}

/// C-ABI: render SVG input to PNG.
/// Input: JSON string with fields: input (svg string), mime, id, url, extra
/// Output: JSON string with fields: png (base64), width, height, format, status, error
/// Caller must free the returned string with tile_free_result.
#[no_mangle]
pub extern "C" fn tile_render(input_json: *const c_char) -> *mut c_char {
    if input_json.is_null() {
        return return_error("null input");
    }

    let c_str = unsafe { CString::from_raw(input_json as *mut c_char) };
    let input_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return return_error("invalid utf8 input"),
    };

    let parsed: serde_json::Value = match serde_json::from_str(input_str) {
        Ok(v) => v,
        Err(_) => return return_error("invalid json input"),
    };

    let svg_content = parsed["input"].as_str().unwrap_or("");
    if svg_content.is_empty() {
        return return_error("empty svg input");
    }

    let mut opt = Options::default();
    opt.fontdb_mut().load_system_fonts();

    let tree = match Tree::from_str(svg_content, &opt) {
        Ok(t) => t,
        Err(e) => return return_error(&format!("usvg parse error: {:?}", e)),
    };

    let size = tree.size();
    let int_size = size.to_int_size();
    let width = int_size.width();
    let height = int_size.height();

    if width == 0 || height == 0 {
        return return_error("svg has zero size");
    }

    let mut pixmap = match Pixmap::new(width, height) {
        Some(p) => p,
        None => return return_error("failed to allocate pixmap"),
    };

    resvg::render(&tree, Transform::default(), &mut pixmap.as_mut());

    let png_bytes = match pixmap.encode_png() {
        Ok(b) => b,
        Err(_) => return return_error("failed to encode png"),
    };

    let b64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &png_bytes);

    let result = serde_json::json!({
        "png": b64,
        "width": width,
        "height": height,
        "format": "png",
        "status": "ok",
    });

    match CString::new(result.to_string()) {
        Ok(s) => s.into_raw(),
        Err(_) => return return_error("result contains null bytes"),
    }
}

/// C-ABI: free a string returned by tile_render.
#[no_mangle]
pub extern "C" fn tile_free_result(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

fn return_error(msg: &str) -> *mut c_char {
    let result = serde_json::json!({
        "status": "error",
        "error": msg,
    });
    match CString::new(result.to_string()) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
