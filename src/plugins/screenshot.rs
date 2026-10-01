// Screenshot plugin - disabled, no shell-out allowed
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct ScreenshotPlugin;

impl ScreenshotPlugin {
    pub fn new() -> Self {
        Self
    }
}

impl Plugin for ScreenshotPlugin {
    fn name(&self) -> &str {
        "screenshot"
    }
    fn version(&self) -> &str {
        "0.1.0"
    }
    fn description(&self) -> &str {
        "Headless chromium PNG/PDF capture (disabled: no shell-out)"
    }

    fn execute(&self, _input: &PluginInput) -> PluginResult {
        Err("screenshot plugin disabled: shell-out not allowed".to_string())
    }
}
