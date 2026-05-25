use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use zos_circuit_optimizer::{CacheLine, CircuitStep, optimize, circuit_cost};

/// Helper: extract 8 u64 register values from input bytes.
fn coords_in_regs(data: &[u8]) -> [u64; 8] {
    let mut regs = [0u64; 8];
    for i in 0..8 {
        let offset = (i * 8) % data.len().max(1);
        let end = (offset + 8).min(data.len());
        let mut buf = [0u8; 8];
        buf[..end - offset].copy_from_slice(&data[offset..end]);
        regs[i] = u64::from_le_bytes(buf);
    }
    regs
}

/// Render ZOS circuit analysis from raw JSON input.
/// Accepts: {"input": "...byte content"}
/// Returns JSON: {"steps": [...], "cost": N, "optimized_steps": N}
#[no_mangle]
pub extern "C" fn render_zos_circuit(input: *const c_char) -> *mut c_char {
    let input_str = if input.is_null() {
        "{}"
    } else {
        match unsafe { CStr::from_ptr(input) }.to_str() {
            Ok(s) => s,
            Err(_) => "{}",
        }
    };

    let parsed: serde_json::Value = serde_json::from_str(input_str).unwrap_or_default();
    let body = parsed
        .get("input")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .as_bytes();

    let cl_in = CacheLine::from_regs(&coords_in_regs(body));
    let cl_out = CacheLine::from_regs(&coords_in_regs(&[0u8; 64]));

    let steps = vec![
        CircuitStep::new("input", cl_in.clone(), cl_in.clone()),
        CircuitStep::new("process", cl_in.clone(), cl_out.clone()),
        CircuitStep::new("output", cl_out.clone(), cl_out.clone()),
    ];
    let optimized = optimize(steps.clone());
    let cost = circuit_cost(&optimized);

    let result = serde_json::json!({
        "steps": steps.iter().map(|s| {
            serde_json::json!({ "name": s.name, "cost": s.cost })
        }).collect::<Vec<_>>(),
        "cost": cost,
        "optimized_steps": optimized.len(),
    });

    let output =
        serde_json::to_string(&result).unwrap_or_else(|_| r#"{"error":"serialization failed"}"#.to_string());
    match CString::new(output) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free memory allocated by `render_zos_circuit`.
#[no_mangle]
pub extern "C" fn free_zos_circuit_result(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}

/// Version information for dynamic loading.
#[no_mangle]
pub static zos_circuit_tile_version: [u8; 4] = [0, 1, 0, 0];

/// Test helper: simple ping to verify the tile loads correctly.
#[no_mangle]
pub extern "C" fn zos_circuit_tile_ping() -> i32 {
    1
}
