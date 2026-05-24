// CAR file index — indexes files from locate DB and serves them as CAR archives
//
// This builds an in-memory index of files on disk (MIDI, PlantUML, etc.)
// and serves them as IPLD CAR files for content-addressed access.
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;
use std::sync::RwLock;
use serde::{Serialize, Deserialize};

/// A single indexed file entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntry {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub ext: String,
}

/// The file index — maps file types to lists of entries
pub struct CarIndex {
    files: RwLock<HashMap<String, Vec<FileEntry>>>,
    ready: RwLock<bool>,
}

impl CarIndex {
    pub fn new() -> Self {
        Self {
            files: RwLock::new(HashMap::new()),
            ready: RwLock::new(false),
        }
    }

    /// Build the index by running locate for each file type
    pub fn build(&self, types: &[(&str, &str)]) -> Result<(), String> {
        let mut files = self.files.write().map_err(|e| e.to_string())?;
        
        for &(ext, label) in types {
            log::info!("  Indexing {} files (locate -r '\\.{}$')...", label, ext);
            let output = Command::new("locate")
                .args(["-r", &format!("\\.{}$", ext)])
                .output()
                .map_err(|e| format!("locate failed: {}", e))?;

            if !output.status.success() {
                log::warn!("  locate for .{} returned non-zero (may need updatedb)", ext);
            }

            let stdout = String::from_utf8_lossy(&output.stdout);
            let entries: Vec<FileEntry> = stdout
                .lines()
                .filter(|l| !l.is_empty())
                .map(|l| {
                    let path = PathBuf::from(l);
                    let name = path.file_name()
                        .map(|n| n.to_string_lossy().to_string())
                        .unwrap_or_else(|| l.to_string());
                    let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
                    FileEntry { path, name, size, ext: ext.to_string() }
                })
                .collect();

            log::info!("    {} entries for .{}", entries.len(), ext);
            files.insert(ext.to_string(), entries);
        }

        let mut ready = self.ready.write().map_err(|e| e.to_string())?;
        *ready = true;
        Ok(())
    }

    /// Check if index is ready
    pub fn is_ready(&self) -> bool {
        self.ready.read().map(|r| *r).unwrap_or(false)
    }

    /// Get entries for a file type
    pub fn get_by_type(&self, ext: &str) -> Vec<FileEntry> {
        self.files.read()
            .map(|f| f.get(ext).cloned().unwrap_or_default())
            .unwrap_or_default()
    }

    /// Search entries by name (substring)
    pub fn search(&self, ext: &str, query: &str) -> Vec<FileEntry> {
        let q = query.to_lowercase();
        self.files.read()
            .map(|f| {
                f.get(ext)
                    .map(|entries| {
                        entries.iter()
                            .filter(|e| e.name.to_lowercase().contains(&q))
                            .take(100)
                            .cloned()
                            .collect()
                    })
                    .unwrap_or_default()
            })
            .unwrap_or_default()
    }

    /// Get stats
    pub fn stats(&self) -> HashMap<String, usize> {
        self.files.read()
            .map(|f| f.iter().map(|(k, v)| (k.clone(), v.len())).collect())
            .unwrap_or_default()
    }
}
