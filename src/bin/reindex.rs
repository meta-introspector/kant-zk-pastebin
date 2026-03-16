use kant_pastebin::model::PasteIndex;
use kant_pastebin::tagging;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;

fn main() {
    let dir = std::env::args()
        .nth(1)
        .unwrap_or_else(|| std::env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".into()));
    let dir = PathBuf::from(&dir);
    let index_path = dir.join("index.jsonl");

    // Load existing index entries by filename
    let mut existing: HashSet<String> = HashSet::new();
    let mut lines_kept: Vec<String> = Vec::new();
    if index_path.exists() {
        let f = BufReader::new(fs::File::open(&index_path).unwrap());
        for line in f.lines().flatten() {
            if let Ok(entry) = serde_json::from_str::<PasteIndex>(&line) {
                existing.insert(entry.filename.clone());
            }
            lines_kept.push(line);
        }
    }
    eprintln!("Existing: {} entries", existing.len());

    // Build CID lookup: cid_filename -> base_id (content of .cid file)
    let mut cid_map: HashMap<String, String> = HashMap::new();
    for entry in fs::read_dir(&dir).unwrap().flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with("bafk") && name.ends_with(".cid") {
            if let Ok(content) = fs::read_to_string(entry.path()) {
                let base = content.trim().to_string();
                let cid_name = name.trim_end_matches(".cid").to_string();
                cid_map.insert(base, cid_name);
            }
        }
    }
    eprintln!("CID map: {} entries", cid_map.len());

    // Scan txt files
    let mut added = 0usize;
    let mut new_lines: Vec<String> = Vec::new();
    for entry in fs::read_dir(&dir).unwrap().flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.ends_with(".txt") || existing.contains(&name) {
            continue;
        }
        let base = name.trim_end_matches(".txt");
        let content = fs::read_to_string(entry.path()).unwrap_or_default();

        // Parse timestamp and title from filename
        let (timestamp, title) = if base.len() > 16 && base.chars().take(8).all(|c| c.is_ascii_digit())
            && base.chars().nth(8) == Some('_')
            && base.chars().skip(9).take(6).all(|c| c.is_ascii_digit())
        {
            let ts = &base[..15];
            let rest = if base.len() > 16 { &base[16..] } else { "untitled" };
            (ts.to_string(), rest.replace('_', " "))
        } else {
            let mtime = entry.metadata().ok()
                .and_then(|m| m.modified().ok())
                .map(|t| {
                    let d = t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
                    chrono::DateTime::from_timestamp(d.as_secs() as i64, 0)
                        .map(|dt| dt.format("%Y%m%d_%H%M%S").to_string())
                        .unwrap_or_default()
                })
                .unwrap_or_default();
            (mtime, base.replace('_', " "))
        };

        // CID from map or compute
        let cid = cid_map.get(base).cloned().unwrap_or_else(|| {
            let mut h = Sha256::new();
            h.update(content.as_bytes());
            format!("bafk{}", hex::encode(&h.finalize()[..16]))
        });

        let witness = {
            let mut h = Sha256::new();
            h.update(content.as_bytes());
            hex::encode(h.finalize())
        };

        let keywords = tagging::auto_tag(&content);
        let description = tagging::auto_describe(&content);
        let ngrams = tagging::extract_ngrams(&content, 2, 5);
        let size = content.len();

        let idx = PasteIndex {
            id: base.to_string(),
            title,
            description: Some(description),
            keywords,
            cid,
            witness,
            timestamp,
            filename: name.clone(),
            ngrams,
            ipfs_cid: None,
            reply_to: None,
            size,
            uucp_path: entry.path().to_string_lossy().to_string(),
        };

        if let Ok(json) = serde_json::to_string(&idx) {
            new_lines.push(json);
            added += 1;
        }
    }

    // Append new entries
    if !new_lines.is_empty() {
        let mut f = fs::OpenOptions::new().create(true).append(true).open(&index_path).unwrap();
        for line in &new_lines {
            writeln!(f, "{}", line).unwrap();
        }
    }

    let total = existing.len() + added;
    eprintln!("Added {} new entries. Total: {}", added, total);
}
