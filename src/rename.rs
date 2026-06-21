use crate::model::PasteIndex;
use crate::tagging;
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct RenameOptions {
    pub uucp_dir: String,
    pub apply: bool,
    pub rename_files: bool,
    pub limit: Option<usize>,
}

#[derive(Debug, Default, Serialize)]
pub struct RenameReport {
    pub total: usize,
    pub renamed: usize,
    pub skipped: usize,
    pub errors: Vec<RenameError>,
    pub items: Vec<RenameItem>,
}

#[derive(Debug, Serialize)]
pub struct RenameItem {
    pub id: String,
    pub old_id: String,
    pub filename: String,
    pub old_filename: String,
    pub title: String,
    pub old_title: String,
    pub description: String,
    pub old_description: Option<String>,
    pub source_archive: String,
    pub selected_files: usize,
    pub cid: String,
    pub old_cid: String,
    pub applied: bool,
}

#[derive(Debug, Serialize)]
pub struct RenameError {
    pub id: String,
    pub filename: String,
    pub error: String,
}

#[derive(Clone)]
struct IndexRecord {
    raw: String,
    parsed: Option<PasteIndex>,
}

#[derive(Debug, Clone)]
struct RenameTarget {
    source_archive: String,
    selected_files: usize,
}

pub fn default_uucp_dir() -> String {
    std::env::var("UUCP_SPOOL").unwrap_or_else(|_| "/mnt/data1/spool/uucp/pastebin".to_string())
}

pub fn rename_allm_pastes(options: &RenameOptions) -> Result<RenameReport, String> {
    let index_path = Path::new(&options.uucp_dir).join("index.jsonl");
    let index_text = fs::read_to_string(&index_path)
        .map_err(|e| format!("failed to read {}: {}", index_path.display(), e))?;

    let mut records = Vec::new();
    for line in index_text.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let parsed = serde_json::from_str::<PasteIndex>(line).ok();
        records.push(IndexRecord {
            raw: line.to_string(),
            parsed,
        });
    }
    let entries: Vec<PasteIndex> = records
        .iter()
        .filter_map(|record| record.parsed.clone())
        .collect();
    let malformed = records
        .iter()
        .filter(|record| record.parsed.is_none())
        .count();

    let mut report = RenameReport::default();
    report.total = entries
        .iter()
        .filter(|entry| is_allm_candidate(entry))
        .count();

    let mut changed_entries = Vec::new();
    for entry in entries.iter().cloned() {
        if !is_allm_candidate(&entry) {
            continue;
        }
        if report.items.len() >= options.limit.unwrap_or(usize::MAX) {
            report.skipped += 1;
            continue;
        }

        let content_path = if entry.uucp_path.is_empty() {
            Path::new(&options.uucp_dir).join(format!("{}.txt", entry.id))
        } else {
            PathBuf::from(&entry.uucp_path)
        };
        let content = match fs::read_to_string(&content_path) {
            Ok(content) => content,
            Err(e) => {
                report.skipped += 1;
                report.errors.push(RenameError {
                    id: entry.id.clone(),
                    filename: entry.filename.clone(),
                    error: format!("failed to read {}: {e}", content_path.display()),
                });
                continue;
            }
        };

        let target = match derive_rename_target(&entry, &content) {
            Some(target) => target,
            None => {
                report.skipped += 1;
                continue;
            }
        };
        let new_title = archive_name_title(&target.source_archive);
        let new_description =
            archive_aggregate_description(&new_title, target.selected_files, entry.size);
        let updated_content = update_paste_header(&content, &new_title, &new_description);
        let (new_cid, witness) = hash_content(updated_content.as_bytes());

        let mut new_entry = entry.clone();
        new_entry.title = new_title.clone();
        new_entry.description = Some(new_description.clone());
        new_entry.cid = new_cid.clone();
        new_entry.witness = witness;

        let mut item = RenameItem {
            id: new_entry.id.clone(),
            old_id: entry.id.clone(),
            filename: new_entry.filename.clone(),
            old_filename: entry.filename.clone(),
            title: new_title,
            old_title: entry.title.clone(),
            description: new_description,
            old_description: entry.description.clone(),
            source_archive: target.source_archive.clone(),
            selected_files: target.selected_files,
            cid: new_cid.clone(),
            old_cid: entry.cid.clone(),
            applied: false,
        };

        if options.rename_files {
            let new_filename = rename_filename(&entry.filename, &item.title, target.selected_files);
            let new_path = unique_path(Path::new(&options.uucp_dir), &new_filename);
            if content_path != new_path {
                if options.apply {
                    fs::rename(&content_path, &new_path).map_err(|e| {
                        format!(
                            "failed to rename {} to {}: {e}",
                            content_path.display(),
                            new_path.display()
                        )
                    })?;
                }
                new_entry.id = new_path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or(&new_entry.id)
                    .to_string();
                new_entry.filename = new_path
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or(&new_entry.filename)
                    .to_string();
                new_entry.uucp_path = new_path.display().to_string();
                item.id = new_entry.id.clone();
                item.filename = new_entry.filename.clone();
            }
        }

        changed_entries.push((entry.id.clone(), new_entry, updated_content, new_cid));
        item.applied = options.apply;
        report.items.push(item);
        report.renamed += 1;
    }

    if options.apply {
        for (_, entry, content, new_cid) in &changed_entries {
            let content_path = if entry.uucp_path.is_empty() {
                Path::new(&options.uucp_dir).join(format!("{}.txt", entry.id))
            } else {
                PathBuf::from(&entry.uucp_path)
            };
            fs::write(&content_path, content)
                .map_err(|e| format!("failed to write {}: {e}", content_path.display()))?;
            fs::write(
                Path::new(&options.uucp_dir).join(format!("{}.cid", new_cid)),
                &entry.id,
            )
            .map_err(|e| {
                format!(
                    "failed to write cid file for {}: {e}",
                    content_path.display()
                )
            })?;
        }

        let changes: HashMap<String, PasteIndex> = changed_entries
            .iter()
            .map(|(old_id, new_entry, _, _)| (old_id.clone(), new_entry.clone()))
            .collect();
        for record in &mut records {
            if let Some(entry) = &record.parsed {
                if let Some(new_entry) = changes.get(&entry.id) {
                    record.parsed = Some(new_entry.clone());
                    record.raw = serde_json::to_string(new_entry).unwrap();
                }
            }
        }
        let index_lines: Vec<String> = records.iter().map(|record| record.raw.clone()).collect();
        fs::write(&index_path, format!("{}\n", index_lines.join("\n")))
            .map_err(|e| format!("failed to write {}: {e}", index_path.display()))?;
    }

    if malformed > 0 && options.apply {
        eprintln!("warning: preserved {malformed} malformed index lines unchanged");
    }

    Ok(report)
}

fn derive_rename_target(entry: &PasteIndex, content: &str) -> Option<RenameTarget> {
    if let Some(source_archive) = source_archive_from_content(content) {
        return Some(RenameTarget {
            source_archive,
            selected_files: selected_file_count(content),
        });
    }

    if let Some((count, source_archive)) =
        parse_concatenated_description(entry.description.as_deref()?)
    {
        return Some(RenameTarget {
            source_archive,
            selected_files: count,
        });
    }

    None
}

fn is_allm_candidate(entry: &PasteIndex) -> bool {
    let title = entry.title.trim();
    let filename = entry.filename.to_lowercase();
    title.eq_ignore_ascii_case("allm.txt")
        || title.to_lowercase().contains("allm.txt")
        || filename.contains("_allm_")
        || filename.contains("allm_txt")
}

fn source_archive_from_content(content: &str) -> Option<String> {
    content.lines().find_map(|line| {
        line.strip_prefix("Source archive: ")
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToOwned::to_owned)
    })
}

fn selected_file_count(content: &str) -> usize {
    for line in content.lines() {
        if let Some(value) = line.strip_prefix("Selected files:") {
            return value
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .count();
        }
    }

    content
        .lines()
        .filter(|line| line.trim_start().starts_with("─────"))
        .count()
}

fn parse_concatenated_description(description: &str) -> Option<(usize, String)> {
    let stripped = description.trim();
    let (count_text, source_archive) = stripped.split_once(" files from ")?;
    let count = count_text
        .strip_prefix("Concatenated ")?
        .parse::<usize>()
        .ok()?;
    Some((count, source_archive.trim().to_string()))
}

fn archive_aggregate_description(title: &str, selected_files: usize, size: usize) -> String {
    if selected_files > 0 {
        format!(
            "{} selected files from {} ({} bytes)",
            selected_files, title, size
        )
    } else {
        format!("Archive aggregate from {} ({} bytes)", title, size)
    }
}

fn update_paste_header(content: &str, title: &str, description: &str) -> String {
    let mut lines: Vec<String> = content.lines().map(ToOwned::to_owned).collect();
    let header_end = lines
        .iter()
        .position(|line| line.trim().is_empty())
        .unwrap_or(lines.len());
    let body_start = if header_end < lines.len() && lines[header_end].trim().is_empty() {
        header_end + 1
    } else {
        header_end
    };
    let body: Vec<String> = lines.iter().skip(body_start).cloned().collect();
    let mut updated = Vec::new();
    let mut saw_title = false;
    let mut saw_description = false;

    for line in lines.drain(..header_end) {
        if let Some(rest) = line.strip_prefix("Title:") {
            updated.push(format!("Title: {}", title));
            saw_title = true;
            if rest.trim().is_empty() {
                continue;
            }
        } else if let Some(rest) = line.strip_prefix("Description:") {
            updated.push(format!("Description: {}", description));
            saw_description = true;
            if rest.trim().is_empty() {
                continue;
            }
        } else {
            updated.push(line);
        }
    }

    if !saw_title {
        updated.insert(0, format!("Title: {}", title));
    }
    if !saw_description {
        let insert_at = updated
            .iter()
            .position(|line| line.starts_with("Title:"))
            .map(|idx| idx + 1)
            .unwrap_or(0);
        updated.insert(insert_at, format!("Description: {}", description));
    }

    updated.extend(body);
    updated.join("\n")
}

fn hash_content(content: &[u8]) -> (String, String) {
    let hash = Sha256::digest(content);
    (
        format!("bafk{}", hex::encode(&hash[..16])),
        hex::encode(hash),
    )
}

pub fn archive_name_title(name: &str) -> String {
    std::path::Path::new(name)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(name)
        .trim_end_matches(".tar.gz")
        .trim_end_matches(".tgz")
        .trim_end_matches(".tar.bz2")
        .trim_end_matches(".tbz2")
        .trim_end_matches(".tbz")
        .trim_end_matches(".tar.xz")
        .trim_end_matches(".txz")
        .trim_end_matches(".tar")
        .trim_end_matches(".zip")
        .trim_end_matches(".gz")
        .trim_end_matches(".bz2")
        .trim_end_matches(".xz")
        .trim_end_matches('.')
        .to_string()
}

fn rename_filename(old_filename: &str, title: &str, selected_files: usize) -> String {
    let prefix = old_filename.chars().take(15).collect::<String>();
    let slug = if title.trim().is_empty() {
        "archive".to_string()
    } else {
        tagging::slugify(title)
    };
    let slug = slug.chars().take(96).collect::<String>();
    format!("{}_{}_{}_files.txt", prefix, slug, selected_files)
}

fn unique_path(dir: &Path, filename: &str) -> PathBuf {
    let path = dir.join(filename);
    if !path.exists() {
        return path;
    }
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("archive");
    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("txt");
    for idx in 2.. {
        let candidate = dir.join(format!("{}_{}.{}", stem, idx, ext));
        if !candidate.exists() {
            return candidate;
        }
    }
    unreachable!()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derives_title_and_description_from_archive_source() {
        let content = "--- id ---\nTitle: allm.txt\nDescription: old\nKeywords: allm\nCID: old\nWitness: old\n\n=== ALLM.TXT ===\nSource archive: my-project.tar.gz\nSelected files: a.txt, b.txt\n";
        let entry = PasteIndex {
            id: "id".to_string(),
            title: "allm.txt".to_string(),
            description: Some("Concatenated 2 files from my-project.tar.gz".to_string()),
            keywords: vec!["allm".to_string()],
            cid: "old".to_string(),
            witness: "old".to_string(),
            timestamp: String::new(),
            filename: "id.txt".to_string(),
            ngrams: vec![],
            ipfs_cid: None,
            reply_to: None,
            size: 123,
            uucp_path: String::new(),
            root: None,
        };
        let target = derive_rename_target(&entry, content).expect("target");
        let title = archive_name_title(&target.source_archive);
        let description = archive_aggregate_description(&title, target.selected_files, entry.size);

        assert_eq!(title, "my-project");
        assert_eq!(target.selected_files, 2);
        assert_eq!(description, "2 selected files from my-project (123 bytes)");
    }

    #[test]
    fn updates_header_without_duplicating_description() {
        let content = "--- id ---\nTitle: allm.txt\nDescription: old\nKeywords: allm\n\nbody";
        let updated = update_paste_header(content, "New Title", "New Description");
        let description_count = updated
            .lines()
            .filter(|line| line.starts_with("Description:"))
            .count();
        let title_count = updated
            .lines()
            .filter(|line| line.starts_with("Title:"))
            .count();

        assert_eq!(description_count, 1);
        assert_eq!(title_count, 1);
        assert!(updated.contains("Title: New Title"));
        assert!(updated.contains("Description: New Description"));
        assert!(updated.ends_with("body"));
    }
}
