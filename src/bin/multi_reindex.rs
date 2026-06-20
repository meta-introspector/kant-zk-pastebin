// multi_reindex.rs — Multi-root scanner: import .org/.md/.txt files into pastebin search index
//
// Usage:
//   cargo run --bin multi-reindex -- <config.json>
//   multi-reindex /path/to/config.json
//
// Config format (JSON):
//   { "roots": [
//       { "path": "/mnt/data1/time-2026", "label": "time-repo", "glob": "**/*.org" },
//       { "path": "/mnt/data1/docs",      "label": "docs",     "glob": "**/*.md" }
//   ]}
//
// Scans each root, indexes matching files into UUCP_SPOOL/index.jsonl
// with the `root` field set to the label for origin tracking.

use kant_pastebin::model::PasteIndex;
use kant_pastebin::tagging;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use walkdir::WalkDir;

#[derive(Deserialize)]
struct Config {
    roots: Vec<Root>,
}

#[derive(Deserialize)]
struct Root {
    path: String,
    label: String,
    #[serde(default = "default_glob")]
    glob: String,
}

fn default_glob() -> String {
    "*.txt".to_string()
}

fn glob_to_pattern(glob: &str) -> String {
    // Simple glob → regex conversion for basic use cases
    // Supports: **/*.ext, *.ext, **/*, path/**/*.org
    let regex = regex_lite::Regex::new(r"\*\*|\*|\.|\\.").unwrap();
    regex
        .replace_all(glob, |caps: &regex_lite::Captures| match &caps[0] {
            "**" => ".*".to_string(),
            "*" => "[^/]*".to_string(),
            "." | "\\." => "\\.".to_string(),
            _ => caps[0].to_string(),
        })
        .to_string()
}

fn matches_glob(path: &str, glob: &str) -> bool {
    let pattern = format!("^{}$", glob_to_pattern(glob));
    if let Ok(re) = regex_lite::Regex::new(&pattern) {
        re.is_match(path)
    } else {
        // Fallback: simple extension check
        let ext = std::path::Path::new(path)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("");
        let glob_ext = std::path::Path::new(glob)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("");
        ext == glob_ext
    }
}

fn main() {
    let config_path = std::env::args().nth(1).unwrap_or_else(|| {
        // Try default config path
        let spool = std::env::var("UUCP_SPOOL")
            .unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
        format!("{}/roots.json", spool)
    });

    let uucp_dir = std::env::var("UUCP_SPOOL")
        .unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string());
    let index_path = format!("{}/index.jsonl", uucp_dir);

    // Read config
    let config_str = fs::read_to_string(&config_path).unwrap_or_else(|e| {
        eprintln!("ERROR: Could not read config at {}: {}", config_path, e);
        eprintln!("Usage: multi-reindex [config.json]");
        eprintln!();
        eprintln!("Config format:");
        eprintln!(r#"{{ "roots": ["#);
        eprintln!(r#"  {{"path": "/path/to/root", "label": "my-root", "glob": "**/*.org"}}"#);
        eprintln!(r#"]}}"#);
        std::process::exit(1);
    });

    let config: Config = serde_json::from_str(&config_str).unwrap_or_else(|e| {
        eprintln!("ERROR: Invalid config JSON: {}", e);
        std::process::exit(1);
    });

    eprintln!(
        "Multi-root scanner: {} root(s) configured",
        config.roots.len()
    );

    // Load existing index entries by filename to avoid duplicates
    let mut existing: HashSet<String> = HashSet::new();
    if fs::metadata(&index_path).is_ok() {
        let f = BufReader::new(fs::File::open(&index_path).unwrap());
        for line in f.lines().flatten() {
            if let Ok(entry) = serde_json::from_str::<PasteIndex>(&line) {
                existing.insert(entry.filename.clone());
            }
        }
    }
    eprintln!("Existing: {} entries", existing.len());

    let mut new_lines: Vec<String> = Vec::new();

    for root in &config.roots {
        let root_path = PathBuf::from(&root.path);
        if !root_path.exists() || !root_path.is_dir() {
            eprintln!("  WARN: Root path does not exist: {}", root.path);
            continue;
        }

        eprintln!("  Scanning: {} (label={})...", root.path, root.label);
        let mut root_count = 0usize;

        for entry in WalkDir::new(&root_path)
            .follow_links(true)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
        {
            let path = entry.path();
            let path_str = path.to_string_lossy();

            // Check glob match relative to root
            let rel_path = path
                .strip_prefix(&root_path)
                .unwrap_or(path)
                .to_string_lossy();

            if !matches_glob(&rel_path, &root.glob) {
                continue;
            }

            // Use a filename that includes the root to avoid collisions
            let safe_filename = format!("{}_{}", root.label, rel_path.replace('/', "_"));

            if existing.contains(&safe_filename) {
                continue;
            }

            let content = fs::read_to_string(path).unwrap_or_default();
            if content.trim().is_empty() {
                continue;
            }

            // Generate ID from path hash
            let mut h = Sha256::new();
            h.update(safe_filename.as_bytes());
            let base_id = hex::encode(&h.finalize()[..8]);

            // Timestamp from file metadata
            let timestamp = entry
                .metadata()
                .ok()
                .and_then(|m| m.modified().ok())
                .map(|t| {
                    let d = t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
                    chrono::DateTime::from_timestamp(d.as_secs() as i64, 0)
                        .map(|dt| dt.format("%Y%m%d_%H%M%S").to_string())
                        .unwrap_or_default()
                })
                .unwrap_or_default();

            // Title from filename or content
            let title = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("untitled")
                .replace('_', " ")
                .replace('-', " ");

            // CID (for dedup)
            let mut cid_hasher = Sha256::new();
            cid_hasher.update(content.as_bytes());
            let cid = format!("bafk{}", hex::encode(&cid_hasher.finalize()[..16]));

            let witness = {
                let mut h2 = Sha256::new();
                h2.update(content.as_bytes());
                hex::encode(h2.finalize())
            };

            let keywords = tagging::auto_tag(&content);
            let description = tagging::auto_describe(&content);
            let ngrams = tagging::extract_ngrams(&content, 2, 5);

            let idx = PasteIndex {
                id: base_id,
                title,
                description: Some(description),
                keywords,
                cid,
                witness,
                timestamp,
                filename: safe_filename,
                ngrams,
                ipfs_cid: None,
                reply_to: None,
                size: content.len(),
                uucp_path: path_str.to_string(),
                root: Some(root.label.clone()),
            };

            if let Ok(json) = serde_json::to_string(&idx) {
                new_lines.push(json);
                root_count += 1;
            }
        }

        eprintln!("  {}: {} new entries", root.label, root_count);
    }

    // Append new entries to index
    if !new_lines.is_empty() {
        let mut f = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&index_path)
            .unwrap();
        for line in &new_lines {
            writeln!(f, "{}", line).unwrap();
        }
    }

    let total = existing.len() + new_lines.len();
    eprintln!(
        "Done. Added {} new entries. Total: {}. Index: {}",
        new_lines.len(),
        total,
        index_path
    );
}
