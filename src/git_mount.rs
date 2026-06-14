// Git Mount — demand-driven cache of git repo files for the pastebin.
//
// Instead of scanning everything upfront, we cache only what's been accessed:
// - Directory listings are cached when browsed
// - File metadata is cached when viewed
// - Search builds a content index lazily from cached files
//
// Cache persists to disk as JSONL so it survives restarts.
// A background task can warm the cache for recently-accessed paths.
//
// Environment:
//   GIT_MOUNTS — colon-separated list of repo roots (default: ~/dasl)
//   GIT_MOUNT_CACHE — path to the JSONL cache file (default: UUCP_SPOOL/git_mount_cache.jsonl)

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Instant, SystemTime};

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

/// A single file entry in the cache.
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct GitFileEntry {
    pub path: String,
    pub repo_root: String,
    pub rel_path: String,
    pub name: String,
    pub ext: String,
    pub size: u64,
    pub head_commit: Option<String>,
    pub branch: Option<String>,
    pub is_submodule: bool,
    pub submodule_chain: Vec<String>,
    pub mtime: u64,
    pub mount_id: String,
    /// When this entry was last accessed (epoch seconds)
    pub last_accessed: u64,
    /// Number of times accessed
    pub access_count: u64,
}

/// A directory listing cache entry.
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct DirCacheEntry {
    pub mount_id: String,
    pub rel_path: String,
    pub entries: Vec<DirEntry>,
    /// When this listing was cached (epoch seconds)
    pub cached_at: u64,
}

/// A directory entry for listing.
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct DirEntry {
    pub name: String,
    pub rel_path: String,
    pub is_dir: bool,
    pub is_submodule: bool,
    pub size: u64,
    pub ext: String,
}

/// Summary of a mounted git repo.
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct GitMountInfo {
    pub id: String,
    pub root: String,
    pub name: String,
    pub head_commit: Option<String>,
    pub branch: Option<String>,
}

// ---------------------------------------------------------------------------
// The cache
// ---------------------------------------------------------------------------

pub struct GitMountCache {
    /// Mount points (id -> info)
    pub mounts: HashMap<String, GitMountInfo>,
    /// Cached file entries (key: "mount_id:rel_path" -> entry)
    pub files: HashMap<String, GitFileEntry>,
    /// Cached directory listings (key: "mount_id:rel_path" -> listing)
    pub dirs: HashMap<String, DirCacheEntry>,
    /// Path to the on-disk cache file
    cache_path: String,
    /// When the cache was last flushed to disk
    last_flush: Instant,
    /// Dirty flag — need to flush?
    dirty: bool,
    /// Max file entries before LRU eviction
    max_files: usize,
    /// Max dir entries before LRU eviction
    max_dirs: usize,
}

impl GitMountCache {
    pub fn new() -> Self {
        let uucp_dir = env::var("UUCP_SPOOL")
            .unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
        let cache_path = env::var("GIT_MOUNT_CACHE")
            .unwrap_or_else(|_| format!("{}/git_mount_cache.jsonl", uucp_dir));

        let mut cache = Self {
            mounts: HashMap::new(),
            files: HashMap::new(),
            dirs: HashMap::new(),
            cache_path,
            last_flush: Instant::now(),
            dirty: false,
            max_files: env::var("GIT_MOUNT_MAX_FILES")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(10_000),
            max_dirs: env::var("GIT_MOUNT_MAX_DIRS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(2_000),
        };

        // Initialize mount points
        cache.init_mounts();

        // Load from disk
        cache.load_from_disk();

        cache
    }

    /// Initialize mount points from GIT_MOUNTS env var.
    fn init_mounts(&mut self) {
        let mounts_config = env::var("GIT_MOUNTS").unwrap_or_else(|_| {
            let home = env::var("HOME").unwrap_or_else(|_| "/home/mdupont".to_string());
            format!("{}/dasl", home)
        });

        for mount_path in mounts_config.split(':') {
            let mount_path = mount_path.trim();
            if mount_path.is_empty() { continue; }

            let real_path = match fs::canonicalize(mount_path) {
                Ok(p) => p,
                Err(_) => continue,
            };

            let mount_id = real_path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unknown")
                .to_string();

            let head_commit = git_head_commit(&real_path);
            let branch = git_branch(&real_path);

            self.mounts.insert(mount_id.clone(), GitMountInfo {
                id: mount_id.clone(),
                root: real_path.display().to_string(),
                name: mount_id,
                head_commit,
                branch,
            });
        }
    }

    /// Load cache from disk.
    fn load_from_disk(&mut self) {
        if let Ok(content) = fs::read_to_string(&self.cache_path) {
            for line in content.lines() {
                if line.starts_with('#') || line.trim().is_empty() { continue; }

                // Try to parse as a file entry
                if let Ok(entry) = serde_json::from_str::<GitFileEntry>(line) {
                    let key = format!("{}:{}", entry.mount_id, entry.rel_path);
                    self.files.insert(key, entry);
                }
                // Try to parse as a dir cache entry
                else if let Ok(entry) = serde_json::from_str::<DirCacheEntry>(line) {
                    let key = format!("{}:{}", entry.mount_id, entry.rel_path);
                    self.dirs.insert(key, entry);
                }
            }
            eprintln!("[git_mount] Loaded {} file entries, {} dir listings from disk",
                self.files.len(), self.dirs.len());
        }

        // Evict if we loaded more than the limit
        self.evict_lru();
    }

    /// LRU eviction — drop the coldest entries when cache is full.
    /// Sort by (last_accessed, access_count) ascending, evict the bottom.
    /// Keeps the hot entries (recently accessed, frequently accessed).
    fn evict_lru(&mut self) {
        // Evict files
        if self.files.len() > self.max_files {
            let evict_count = self.files.len() - self.max_files;
            // Collect keys sorted by (last_accessed, access_count) ascending
            let mut ranked: Vec<(u64, u64, String)> = self.files.iter()
                .map(|(k, v)| (v.last_accessed, v.access_count, k.clone()))
                .collect();
            ranked.sort_by_key(|(t, c, _)| (*t, *c));

            let keys_to_evict: Vec<String> = ranked.iter()
                .take(evict_count)
                .map(|(_, _, k)| k.clone())
                .collect();

            for key in keys_to_evict {
                self.files.remove(&key);
            }
            eprintln!("[git_mount] LRU evicted {} file entries ({} remaining)",
                evict_count, self.files.len());
            self.dirty = true;
        }

        // Evict dirs
        if self.dirs.len() > self.max_dirs {
            let evict_count = self.dirs.len() - self.max_dirs;
            let mut ranked: Vec<(u64, String)> = self.dirs.iter()
                .map(|(k, v)| (v.cached_at, k.clone()))
                .collect();
            ranked.sort_by_key(|(t, _)| *t);

            let keys_to_evict: Vec<String> = ranked.iter()
                .take(evict_count)
                .map(|(_, k)| k.clone())
                .collect();

            for key in keys_to_evict {
                self.dirs.remove(&key);
            }
            eprintln!("[git_mount] LRU evicted {} dir entries ({} remaining)",
                evict_count, self.dirs.len());
            self.dirty = true;
        }
    }

    /// Flush cache to disk.
    pub fn flush_to_disk(&mut self) {
        if !self.dirty { return; }

        let mut lines = Vec::new();

        // Write file entries
        for entry in self.files.values() {
            if let Ok(json) = serde_json::to_string(entry) {
                lines.push(json);
            }
        }

        // Write dir entries
        for entry in self.dirs.values() {
            if let Ok(json) = serde_json::to_string(entry) {
                lines.push(json);
            }
        }

        let content = lines.join("\n") + "\n";
        if let Err(e) = fs::write(&self.cache_path, content) {
            eprintln!("[git_mount] Failed to write cache: {}", e);
        } else {
            eprintln!("[git_mount] Flushed {} file entries, {} dir listings to disk",
                self.files.len(), self.dirs.len());
        }

        self.dirty = false;
        self.last_flush = Instant::now();
    }

    /// Maybe flush if enough time has passed.
    pub fn maybe_flush(&mut self) {
        if self.dirty && self.last_flush.elapsed().as_secs() > 30 {
            self.flush_to_disk();
        }
    }

    /// Get a directory listing — from cache or filesystem.
    pub fn list_dir(&mut self, mount_id: &str, sub_path: &str) -> Vec<DirEntry> {
        let cache_key = format!("{}:{}", mount_id, sub_path.trim_end_matches('/'));

        // Check cache — use it if less than 60 seconds old
        if let Some(cached) = self.dirs.get(&cache_key) {
            let now = SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            if now - cached.cached_at < 60 {
                return cached.entries.clone();
            }
        }

        // Read from filesystem
        let mount_info = match self.mounts.get(mount_id) {
            Some(m) => m,
            None => return Vec::new(),
        };

        let full_path = if sub_path.is_empty() || sub_path == "/" {
            PathBuf::from(&mount_info.root)
        } else {
            PathBuf::from(&mount_info.root).join(sub_path.trim_start_matches('/'))
        };

        let mut entries = Vec::new();

        if let Ok(read_dir) = fs::read_dir(&full_path) {
            for entry in read_dir.flatten() {
                let path = entry.path();
                let name = entry.file_name().to_string_lossy().to_string();

                if name.starts_with('.') { continue; }
                if name == "target" || name == "build" || name == "node_modules" { continue; }

                let is_dir = path.is_dir();
                let is_submodule = is_dir && path.join(".git").exists();

                let rel_path = path.strip_prefix(&mount_info.root)
                    .unwrap_or(&path)
                    .display()
                    .to_string();

                let size = if is_dir { 0 } else {
                    fs::metadata(&path).map(|m| m.len()).unwrap_or(0)
                };

                let ext = if is_dir { String::new() } else {
                    path.extension()
                        .and_then(|e| e.to_str())
                        .unwrap_or("")
                        .to_string()
                };

                entries.push(DirEntry {
                    name,
                    rel_path,
                    is_dir,
                    is_submodule,
                    size,
                    ext,
                });
            }
        }

        // Sort: dirs first, then files
        entries.sort_by(|a, b| {
            match (a.is_dir, b.is_dir) {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
            }
        });

        // Cache it
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        self.dirs.insert(cache_key, DirCacheEntry {
            mount_id: mount_id.to_string(),
            rel_path: sub_path.trim_end_matches('/').to_string(),
            entries: entries.clone(),
            cached_at: now,
        });
        self.dirty = true;
        self.evict_lru();
        self.maybe_flush();

        entries
    }

    /// Read a file's content from a mount.
    pub fn read_file(&mut self, mount_id: &str, sub_path: &str) -> Option<String> {
        let mount_info = self.mounts.get(mount_id)?;
        let full_path = PathBuf::from(&mount_info.root).join(sub_path.trim_start_matches('/'));
        let content = fs::read_to_string(&full_path).ok()?;

        // Cache the file entry
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let cache_key = format!("{}:{}", mount_id, sub_path.trim_end_matches('/'));

        if let Some(existing) = self.files.get_mut(&cache_key) {
            existing.last_accessed = now;
            existing.access_count += 1;
        } else {
            let path = full_path.display().to_string();
            let name = Path::new(sub_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("file")
                .to_string();
            let ext = Path::new(sub_path)
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("")
                .to_string();
            let size = fs::metadata(&full_path).map(|m| m.len()).unwrap_or(0);
            let mtime = fs::metadata(&full_path)
                .ok()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let (head_commit, branch) = git_info_for_path(&full_path);

            self.files.insert(cache_key, GitFileEntry {
                path,
                repo_root: mount_info.root.clone(),
                rel_path: sub_path.trim_start_matches('/').to_string(),
                name,
                ext,
                size,
                head_commit,
                branch,
                is_submodule: false, // updated below
                submodule_chain: Vec::new(),
                mtime,
                mount_id: mount_id.to_string(),
                last_accessed: now,
                access_count: 1,
            });
        }

        self.dirty = true;
        self.evict_lru();
        self.maybe_flush();

        Some(content)
    }

    /// Get file metadata from cache.
    pub fn get_file_entry(&self, mount_id: &str, sub_path: &str) -> Option<&GitFileEntry> {
        let key = format!("{}:{}", mount_id, sub_path.trim_end_matches('/'));
        self.files.get(&key)
    }

    /// Search cached files by name/path.
    pub fn search_names(&self, query: &str, limit: usize) -> Vec<&GitFileEntry> {
        let q = query.to_lowercase();
        let mut results = Vec::new();

        // Sort by access count (most accessed first)
        let mut entries: Vec<&GitFileEntry> = self.files.values().collect();
        entries.sort_by(|a, b| b.access_count.cmp(&a.access_count));

        for entry in entries {
            if results.len() >= limit { break; }
            if entry.name.to_lowercase().contains(&q) || entry.rel_path.to_lowercase().contains(&q) {
                results.push(entry);
            }
        }
        results
    }

    /// Search cached file contents.
    pub fn search_content(&self, query: &str, limit: usize) -> Vec<(&GitFileEntry, String)> {
        let q = query.to_lowercase();
        let mut results = Vec::new();

        let text_exts = [
            "rs", "py", "js", "ts", "go", "java", "c", "h", "cpp", "hpp",
            "md", "txt", "org", "toml", "yaml", "yml", "json", "nix", "sh",
            "html", "css", "xml", "rb", "hs", "lean", "zig", "nim",
        ];

        // Sort by access count
        let mut entries: Vec<&GitFileEntry> = self.files.values().collect();
        entries.sort_by(|a, b| b.access_count.cmp(&a.access_count));

        for entry in entries {
            if results.len() >= limit { break; }
            if !text_exts.contains(&entry.ext.as_str()) { continue; }

            if let Ok(content) = fs::read_to_string(&entry.path) {
                if content.to_lowercase().contains(&q) {
                    let excerpt = excerpt_around(&content, query, 120);
                    results.push((entry, excerpt));
                }
            }
        }

        results
    }

    /// Warm the cache for a specific directory (called when browsing).
    /// Adds file entries for all files in the directory to the cache.
    pub fn warm_dir(&mut self, mount_id: &str, sub_path: &str) {
        let entries = self.list_dir(mount_id, sub_path);
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let mount_info = match self.mounts.get(mount_id) {
            Some(m) => m,
            None => return,
        };

        for entry in entries.iter().filter(|e| !e.is_dir) {
            let cache_key = format!("{}:{}", mount_id, entry.rel_path);
            if self.files.contains_key(&cache_key) { continue; }

            let full_path = PathBuf::from(&mount_info.root).join(&entry.rel_path);
            let mtime = fs::metadata(&full_path)
                .ok()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let (head_commit, branch) = git_info_for_path(&full_path);

            self.files.insert(cache_key, GitFileEntry {
                path: full_path.display().to_string(),
                repo_root: mount_info.root.clone(),
                rel_path: entry.rel_path.clone(),
                name: entry.name.clone(),
                ext: entry.ext.clone(),
                size: entry.size,
                head_commit,
                branch,
                is_submodule: entry.is_submodule,
                submodule_chain: Vec::new(),
                mtime,
                mount_id: mount_id.to_string(),
                last_accessed: now,
                access_count: 0, // not yet accessed, just warmed
            });
        }

        self.dirty = true;
        self.evict_lru();
    }

    /// Get stats about the cache.
    pub fn stats(&self) -> serde_json::Value {
        let total_accesses: u64 = self.files.values().map(|f| f.access_count).sum();
        let total_size: u64 = self.files.values().map(|f| f.size).sum();

        serde_json::json!({
            "mounts": self.mounts.len(),
            "cached_files": self.files.len(),
            "cached_dirs": self.dirs.len(),
            "total_accesses": total_accesses,
            "total_cached_size": total_size,
        })
    }
}

// ---------------------------------------------------------------------------
// Git helpers
// ---------------------------------------------------------------------------

fn git_head_commit(repo_path: &Path) -> Option<String> {
    let head_path = repo_path.join(".git").join("HEAD");
    let head_content = fs::read_to_string(&head_path).ok()?;

    if head_content.starts_with("ref:") {
        let ref_path = head_content.trim().strip_prefix("ref: ")?;
        let full_ref = repo_path.join(".git").join(ref_path);
        fs::read_to_string(&full_ref).ok().map(|s| s.trim().to_string())
    } else {
        Some(head_content.trim().to_string())
    }
}

fn git_branch(repo_path: &Path) -> Option<String> {
    let head_path = repo_path.join(".git").join("HEAD");
    let head_content = fs::read_to_string(&head_path).ok()?;

    if let Some(ref_path) = head_content.trim().strip_prefix("ref: refs/heads/") {
        Some(ref_path.trim().to_string())
    } else {
        None
    }
}

fn git_info_for_path(path: &Path) -> (Option<String>, Option<String>) {
    let mut dir = path.parent();
    while let Some(d) = dir {
        if d.join(".git").exists() {
            return (git_head_commit(d), git_branch(d));
        }
        dir = d.parent();
    }
    (None, None)
}

fn excerpt_around(text: &str, query: &str, context_chars: usize) -> String {
    let lower = text.to_lowercase();
    let q = query.to_lowercase();

    if let Some(pos) = lower.find(&q) {
        let start = pos.saturating_sub(context_chars / 2);
        let end = (pos + q.len() + context_chars / 2).min(text.len());
        let mut excerpt = String::new();
        if start > 0 { excerpt.push_str("..."); }
        excerpt.push_str(&text[start..end]);
        if end < text.len() { excerpt.push_str("..."); }
        excerpt
    } else {
        String::new()
    }
}

// ---------------------------------------------------------------------------
// Global cache (lazy-initialized, thread-safe)
// ---------------------------------------------------------------------------

lazy_static::lazy_static! {
    pub static ref GIT_CACHE: Mutex<GitMountCache> = Mutex::new(GitMountCache::new());
}

/// Get the cache (may block briefly on first access to load from disk).
pub fn get_cache() -> std::sync::MutexGuard<'static, GitMountCache> {
    GIT_CACHE.lock().unwrap()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_git_head_commit_parsing() {
        let tmp = tempfile::tempdir().unwrap();
        let git_dir = tmp.path().join(".git");
        fs::create_dir_all(&git_dir).unwrap();
        fs::write(git_dir.join("HEAD"), "ref: refs/heads/main\n").unwrap();
        fs::create_dir_all(git_dir.join("refs/heads")).unwrap();
        fs::write(git_dir.join("refs/heads/main"), "abc123def456\n").unwrap();

        let commit = git_head_commit(tmp.path()).unwrap();
        assert_eq!(commit, "abc123def456");

        let branch = git_branch(tmp.path()).unwrap();
        assert_eq!(branch, "main");
    }

    #[test]
    fn test_excerpt_around() {
        let text = "The quick brown fox jumps over the lazy dog";
        let excerpt = excerpt_around(text, "fox", 10);
        assert!(excerpt.contains("fox"));
    }
}
