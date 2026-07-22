use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::path::PathBuf;

pub fn render_via_tile(tile_path: &PathBuf, svg_data: &[u8]) -> Result<Vec<u8>, String> {
    let lib =
        unsafe { libloading::Library::new(tile_path) }.map_err(|e| format!("load tile: {}", e))?;

    let ping: libloading::Symbol<unsafe extern "C" fn() -> c_int> =
        unsafe { lib.get(b"tile_ping\0") }.map_err(|e| format!("get ping: {}", e))?;
    if unsafe { ping() } != 1 {
        return Err("tile ping failed".into());
    }

    let svg_str = String::from_utf8_lossy(svg_data);
    let req = serde_json::json!({
        "id": "cli",
        "input": svg_str,
        "mime": "image/svg+xml",
        "url": "",
        "extra": {},
    });
    let req_cstr = CString::new(req.to_string()).map_err(|e| format!("CString: {}", e))?;

    let render: libloading::Symbol<unsafe extern "C" fn(*const c_char) -> *mut c_char> =
        unsafe { lib.get(b"tile_render\0") }.map_err(|e| format!("get render: {}", e))?;

    let result_ptr = unsafe { render(req_cstr.as_ptr()) };
    if result_ptr.is_null() {
        return Err("tile returned null".into());
    }

    let result_str = unsafe { CStr::from_ptr(result_ptr) }
        .to_str()
        .map_err(|e| format!("CStr: {}", e))?
        .to_string();

    let free: libloading::Symbol<unsafe extern "C" fn(*mut c_char)> =
        unsafe { lib.get(b"tile_free_result\0") }.unwrap_or(std::mem::zeroed());
    unsafe { free(result_ptr as *mut c_char) };

    let parsed: serde_json::Value =
        serde_json::from_str(&result_str).map_err(|e| format!("parse: {}", e))?;

    if parsed.get("status").and_then(|v| v.as_str()) == Some("error") {
        return Err(parsed
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .into());
    }

    let b64 = parsed
        .get("png")
        .and_then(|v| v.as_str())
        .ok_or("no png in tile output")?;

    base64::engine::general_purpose::STANDARD
        .decode(b64)
        .map_err(|e| format!("decode base64: {}", e))
}
