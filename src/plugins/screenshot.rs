// Screenshot plugin - headless chromium PNG/PDF capture
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct ScreenshotPlugin {
    chromium_path: String,
}

impl ScreenshotPlugin {
    pub fn new() -> Self {
        // Find chromium in PATH or known nix store locations
        let path = std::env::var("CHROMIUM_PATH").unwrap_or_else(|_| {
            // Try PATH first
            if let Ok(output) = Command::new("which").arg("chromium").output() {
                if output.status.success() {
                    return String::from_utf8_lossy(&output.stdout).trim().to_string();
                }
            }
            "chromium".to_string()
        });
        Self { chromium_path: path }
    }

    fn capture(&self, url: &str, output_path: &str, format: &str) -> Result<(), String> {
        let mut args = vec![
            "--headless".to_string(),
            "--no-sandbox".to_string(),
            "--disable-gpu".to_string(),
            "--disable-software-rasterizer".to_string(),
            "--window-size=1280,960".to_string(),
        ];

        match format {
            "pdf" => {
                args.push(format!("--print-to-pdf={}", output_path));
            }
            _ => {
                args.push(format!("--screenshot={}", output_path));
            }
        }
        args.push(url.to_string());

        let output = Command::new(&self.chromium_path)
            .args(&args)
            .output()
            .map_err(|e| format!("chromium failed: {}", e))?;

        if !output.status.success() {
            return Err(format!("chromium exit {}: {}", output.status, String::from_utf8_lossy(&output.stderr)));
        }
        Ok(())
    }
}

impl Plugin for ScreenshotPlugin {
    fn name(&self) -> &str { "screenshot" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Headless chromium PNG/PDF capture" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let format = input.extra.get("format").map(|s| s.as_str()).unwrap_or("png");
        let ext = if format == "pdf" { "pdf" } else { "png" };
        let spool = std::env::var("UUCP_SPOOL").unwrap_or_else(|_| "/tmp".to_string());
        let output_path = format!("{}/{}_{}.{}", spool, input.id, self.name(), ext);

        self.capture(&input.url, &output_path, format)?;

        let data = std::fs::read(&output_path).map_err(|e| e.to_string())?;
        let ipfs_cid = crate::ipfs::ipfs_add_bytes(&data).unwrap_or_default();

        let mut result = HashMap::new();
        result.insert("path".into(), output_path);
        result.insert("format".into(), ext.into());
        result.insert("size".into(), data.len().to_string());
        result.insert("ipfs_cid".into(), ipfs_cid);
        Ok(result)
    }
}
