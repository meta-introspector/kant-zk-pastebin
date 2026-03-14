#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! ```

use std::fs;
use std::process::Command;
use std::io::Write;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone)]
struct PasteIndex {
    id: String,
    title: String,
    description: Option<String>,
    keywords: Vec<String>,
    cid: String,
    witness: String,
    timestamp: String,
    filename: String,
    ngrams: Vec<(String, usize)>,
    ipfs_cid: Option<String>,
    reply_to: Option<String>,
    size: usize,
    uucp_path: String,
}

fn ipfs_add(content: &str) -> Option<String> {
    let mut child = Command::new("/nix/store/6avpxclcjrgm0ll1a9dp8638haw0jyn8-kubo-0.39.0/bin/ipfs")
        .args(&["add", "-Q", "--pin=false"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .ok()?;
    
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(content.as_bytes()).ok()?;
    }
    
    let output = child.wait_with_output().ok()?;
    String::from_utf8(output.stdout).ok().map(|s| s.trim().to_string())
}

fn extract_html_title(html: &str) -> Option<String> {
    let start = html.find("<title>")?;
    let end = html[start..].find("</title>")?;
    Some(html[start + 7..start + end].trim().to_string())
}

fn auto_describe(content: &str) -> String {
    let lines: Vec<&str> = content.lines().take(3).collect();
    let preview = lines.join(" ").chars().take(100).collect::<String>();
    if preview.len() < content.len() { format!("{}...", preview) } else { preview }
}

fn main() {
    let spool = "/mnt/data1/spool/uucp/pastebin";
    let index_file = format!("{}/index.jsonl", spool);
    
    println!("🔄 Upgrading pastes...");
    
    let entries: Vec<PasteIndex> = fs::read_to_string(&index_file)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str::<PasteIndex>(line).ok())
        .collect();
    
    let mut upgraded = 0;
    let mut new_entries = Vec::new();
    
    for entry in entries {
        let file_path = format!("{}/{}", spool, entry.filename);
        if let Ok(content) = fs::read_to_string(&file_path) {
            let body = content.lines()
                .skip_while(|line| !line.is_empty())
                .skip(1)
                .collect::<Vec<_>>()
                .join("\n");
            
            let description = auto_describe(&body);
            
            // Extract HTML title
            let new_title = if body.to_lowercase().contains("<html") || body.to_lowercase().contains("<!doctype") {
                extract_html_title(&body).unwrap_or_else(|| entry.title.clone())
            } else if entry.title == "untitled" || entry.title.is_empty() {
                description.clone()
            } else {
                entry.title.clone()
            };
            
            // Check file header
            let file_has_ipfs = content.lines()
                .find(|line| line.starts_with("IPFS:"))
                .and_then(|line| line.split_once(':'))
                .map(|(_, val)| !val.trim().is_empty())
                .unwrap_or(false);
            
            let file_title = content.lines()
                .find(|line| line.starts_with("Title:"))
                .and_then(|line| line.split_once(':'))
                .map(|(_, val)| val.trim())
                .unwrap_or("");
            
            let needs_title_update = file_title == "untitled" && new_title != "untitled";
            
            // Get or generate IPFS CID
            let ipfs_cid = if !file_has_ipfs || entry.ipfs_cid.is_none() || entry.ipfs_cid.as_deref() == Some("") {
                entry.ipfs_cid.clone().or_else(|| {
                    println!("  Generating IPFS for: {}", entry.id);
                    ipfs_add(&body)
                })
            } else {
                entry.ipfs_cid.clone()
            };
            
            // Update file header
            if !file_has_ipfs || needs_title_update {
                let mut updated_content = content.clone();
                
                if !file_has_ipfs {
                    if let Some(ref cid_val) = ipfs_cid {
                        println!("  Adding IPFS to {}: {}", entry.id, cid_val);
                        updated_content = updated_content.replace("IPFS: \n", &format!("IPFS: {}\n", cid_val));
                    }
                }
                
                if needs_title_update {
                    println!("  Updating title for {}: {}", entry.id, new_title);
                    updated_content = updated_content.replace("Title: untitled\n", &format!("Title: {}\n", new_title));
                }
                
                fs::write(&file_path, updated_content).ok();
                upgraded += 1;
            }
            
            let mut new_entry = entry.clone();
            new_entry.title = new_title;
            new_entry.ipfs_cid = ipfs_cid;
            new_entry.description = Some(description);
            
            new_entries.push(new_entry);
        } else {
            new_entries.push(entry);
        }
    }
    
    // Write new index
    let new_index: String = new_entries.iter()
        .map(|e| serde_json::to_string(e).unwrap())
        .collect::<Vec<_>>()
        .join("\n") + "\n";
    
    fs::write(&index_file, new_index).ok();
    
    println!("\n✅ Upgraded {} pastes (total: {})", upgraded, new_entries.len());
}
