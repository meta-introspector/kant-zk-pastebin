// Tile loader — loads standalone .so tile plugins from a directory.
// Each tile is a compiled cdylib crate implementing a C-ABI interface.
// This module discovers .so files, loads them via libloading, and wraps
// them as Plugin trait instances for the pastebin plugin system.

use crate::plugin::{Plugin, PluginInput, PluginResult};
use libloading::{Library, Symbol};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// Expected C-ABI symbols in each tile .so
pub(crate) const TILE_PING_SYMBOL: &str = "zos_circuit_tile_ping";
pub(crate) const TILE_RENDER_SYMBOL: &str = "render_zos_circuit";
pub(crate) const TILE_FREE_SYMBOL: &str = "free_zos_circuit_result";

/// Holds a loaded .so library and its known extern symbols.
pub(crate) struct LoadedTile {
    _lib: Arc<Library>,
    name: String,
}

impl LoadedTile {
    pub(crate) fn name(&self) -> &str {
        &self.name
    }

    /// Try to load a .so file as a tile.
    /// Returns None if the file doesn't have the expected ping symbol.
    fn load(path: &Path) -> Option<Self> {
        let lib = unsafe { Library::new(path) }.ok()?;

        // Verify the tile is alive by calling its ping function
        let ping: Symbol<unsafe extern "C" fn() -> i32> =
            unsafe { lib.get(TILE_PING_SYMBOL.as_bytes()) }.ok()?;
        let alive = unsafe { ping() };
        if alive != 1 {
            log::warn!("Tile at {:?} ping returned {}", path, alive);
            return None;
        }

        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .trim_start_matches("lib")
            .to_string();

        log::info!("TILE loaded: {} from {:?} (ping={})", name, path, alive);
        Some(Self {
            _lib: Arc::new(lib),
            name,
        })
    }
}

/// A Plugin wrapper around a loaded .so tile.
pub(crate) struct TilePlugin {
    tile: Arc<LoadedTile>,
    lib: Arc<Library>,
    version_str: String,
}

impl TilePlugin {
    pub fn new(tile: LoadedTile) -> Self {
        let lib = Arc::clone(&tile._lib);
        Self {
            tile,
            lib,
            version_str: "0.1.0".to_string(),
        }
    }
}

impl Plugin for TilePlugin {
    fn name(&self) -> &str {
        &self.tile.name
    }

    fn version(&self) -> &str {
        &self.version_str
    }

    fn description(&self) -> &str {
        "Dynamically loaded tile plugin from .so"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        // Build JSON input for the tile
        let req = serde_json::json!({
            "id": input.id,
            "input": String::from_utf8_lossy(&input.content),
            "mime": input.mime,
            "url": input.url,
            "extra": input.extra,
        });
        let req_str =
            serde_json::to_string(&req).map_err(|e| format!("serialize: {}", e))?;
        let cstr =
            std::ffi::CString::new(req_str).map_err(|e| format!("CString: {}", e))?;

        // Call the tile's render function
        unsafe {
            let render: Symbol<
                unsafe extern "C" fn(
                    *const std::os::raw::c_char,
                ) -> *mut std::os::raw::c_char,
            > = self
                .lib
                .get(TILE_RENDER_SYMBOL.as_bytes())
                .map_err(|e| format!("symbol {}: {}", TILE_RENDER_SYMBOL, e))?;

            let result_ptr = render(cstr.as_ptr());
            if result_ptr.is_null() {
                return Err("tile returned null".to_string());
            }

            let result_str = std::ffi::CStr::from_ptr(result_ptr)
                .to_str()
                .map_err(|e| format!("CStr: {}", e))?
                .to_string();

            // Free the tile's allocated string
            let free: Symbol<
                unsafe extern "C" fn(*mut std::os::raw::c_char),
            > = self
                .lib
                .get(TILE_FREE_SYMBOL.as_bytes())
                .unwrap_or(std::mem::zeroed());

            free(result_ptr);

            // Parse result as JSON and convert to PluginResult
            let parsed: serde_json::Value = serde_json::from_str(&result_str)
                .map_err(|e| format!("parse tile response: {}", e))?;

            let mut map = HashMap::new();
            if let Some(obj) = parsed.as_object() {
                for (k, v) in obj {
                    map.insert(
                        k.clone(),
                        match v {
                            serde_json::Value::String(s) => s.clone(),
                            other => other.to_string(),
                        },
                    );
                }
            }
            Ok(map)
        }
    }
}

/// Discover and load all tile .so files from a directory.
/// Each file matching `lib*.so` is tried as a tile.
pub(crate) fn discover_tiles(tiles_dir: &Path) -> Vec<LoadedTile> {
    let mut tiles = Vec::new();

    if !tiles_dir.is_dir() {
        log::warn!(
            "TILES_DIR not found: {}",
            tiles_dir.display()
        );
        return tiles;
    }

    let entries = match std::fs::read_dir(tiles_dir) {
        Ok(e) => e,
        Err(e) => {
            log::error!(
                "Cannot read TILES_DIR {}: {}",
                tiles_dir.display(),
                e
            );
            return tiles;
        }
    };

    for entry in entries.flatten() {
        let path = entry.path();
        // Look for lib*.so files (cdylib output)
        if path
            .extension()
            .map_or(false, |e| e == "so")
            && path
                .file_name()
                .and_then(|n| n.to_str())
                .map_or(false, |n| n.starts_with("lib"))
        {
            if let Some(tile) = LoadedTile::load(&path) {
                tiles.push(tile);
            }
        }
    }

    log::info!(
        "Discovered {} tile(s) in {}",
        tiles.len(),
        tiles_dir.display()
    );
    tiles
}
