// Plugin system - ZOS-compatible plugin trait and loader
use std::collections::HashMap;

/// Plugin result: name → value (JSON string, bytes, etc.)
pub type PluginResult = Result<HashMap<String, String>, String>;

/// ZOS-compatible plugin trait
pub trait Plugin: Send + Sync {
    fn name(&self) -> &str;
    fn version(&self) -> &str;
    fn description(&self) -> &str;
    /// Execute plugin on content, returns key-value results
    fn execute(&self, input: &PluginInput) -> PluginResult;
}

/// Input passed to plugins
pub struct PluginInput {
    pub id: String,
    pub content: Vec<u8>,
    pub mime: String,
    pub url: String,
    pub extra: HashMap<String, String>,
}

/// Plugin registry
pub struct PluginRegistry {
    plugins: HashMap<String, Box<dyn Plugin>>,
}

impl PluginRegistry {
    pub fn new() -> Self {
        Self { plugins: HashMap::new() }
    }

    pub fn register(&mut self, plugin: Box<dyn Plugin>) {
        let name = plugin.name().to_string();
        log::info!("🔌 Registered plugin: {} v{}", name, plugin.version());
        self.plugins.insert(name, plugin);
    }

    pub fn get(&self, name: &str) -> Option<&dyn Plugin> {
        self.plugins.get(name).map(|p| p.as_ref())
    }

    pub fn list(&self) -> Vec<(&str, &str, &str)> {
        self.plugins.values().map(|p| (p.name(), p.version(), p.description())).collect()
    }

    pub fn execute(&self, name: &str, input: &PluginInput) -> PluginResult {
        self.plugins.get(name)
            .ok_or_else(|| format!("plugin '{}' not found", name))?
            .execute(input)
    }
}
