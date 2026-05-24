// Tiles plugin — DAG-CBOR spec tiles viewer
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::path::Path;

pub struct TilesPlugin;

impl TilesPlugin {
    pub fn new() -> Self { Self }
}

impl Plugin for TilesPlugin {
    fn name(&self) -> &str { "tiles" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "DAG-CBOR spec tiles — full-stack traceability view" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let tiles_path = std::env::var("DAGCBOR_TILES_PATH")
            .unwrap_or_else(|_| "/mnt/data1/time-2026/02-february/22/dasl/dasl-testing/sheaf/tiles/dagcbor_tiles.html".to_string());

        match std::fs::read_to_string(&tiles_path) {
            Ok(html) => {
                let mut map = HashMap::new();
                map.insert("html".to_string(), html);
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
                Ok(map)
            }
            Err(e) => {
                let mut map = HashMap::new();
                map.insert("error".to_string(), format!("Tiles not found: {}", e));
                map.insert("hint".to_string(), "Run: cd /mnt/data1/time-2026/02-february/22/dasl/dasl-testing && make tiles".to_string());
                Ok(map)
            }
        }
    }
}
