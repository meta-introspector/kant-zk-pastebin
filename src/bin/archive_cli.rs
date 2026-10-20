use kant_pastebin::archive::{extract, ArchiveResult};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::Path;
use serde_json::to_string_pretty;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <archive_path> [--json] [--stats]", args[0]);
        std::process::exit(1);
    }

    let archive_path = &args[1];
    let json_output = args.contains(&"--json".to_string());
    let show_stats = args.contains(&"--stats".to_string());

    let path = Path::new(archive_path);
    if !path.exists() {
        eprintln!("Error: archive file not found: {}", archive_path);
        std::process::exit(1);
    }

    let data = fs::read(archive_path).expect("Failed to read archive file");
    let result = extract(&data, archive_path).expect("Failed to extract archive");

    if json_output {
        let json = to_string_pretty(&result).expect("Failed to serialize to JSON");
        println!("{}", json);
        return;
    }

    // Human-readable output
    println!("Archive: {}", result.filename);
    println!("Title: {}", result.title);
    println!("Description: {}", result.description);
    println!("Entries: {}", result.entry_count);
    println!("Total size: {} bytes", result.total_size);
    println!();

    for (i, entry) in result.entries.iter().enumerate() {
        let icon = if entry.is_dir { "\u{1F4C1}" } else { "\u{1F4C4}" };
        let size = format_size(entry.size);
        let type_str = if entry.is_dir { "directory" } else { "file" };
        let text_type = if entry.is_text() { "text" } else { "binary" };
        let _ = writeln!(io::stdout(), "{}: {} {}  {}  {}  {}", i + 1, icon, entry.path, size, type_str, text_type);
    }

    if show_stats {
        print_archive_stats(&result);
    }
}

fn format_size(bytes: u64) -> String {
    if bytes < 1024 {
        format!("{} B", bytes)
    } else if bytes < 1024 * 1024 {
        format!("{} KB", bytes / 1024)
    } else {
        format!("{} MB", bytes / (1024 * 1024))
    }
}

fn print_archive_stats(result: &ArchiveResult) {
    let mut stats = Statistics::default();
    for entry in &result.entries {
        if entry.is_dir {
            stats.dir_count += 1;
        } else {
            stats.file_count += 1;
            if entry.is_text() {
                stats.text_count += 1;
            } else {
                stats.binary_count += 1;
            }
            stats.total_count += 1;
        }

        // Count by extension category
        let category = categorize_by_path(&entry.path);
        *stats.category_counts.entry(category).or_insert(0) += 1;
    }

    println!("\nStatistics:");
    println!("  Total entries: {}", stats.total_count);
    println!("  Directories: {}", stats.dir_count);
    println!("  Files: {}", stats.file_count);
    println!("  Text files: {}", stats.text_count);
    println!("  Binary files: {}", stats.binary_count);

    println!("\nCategories:");
    for (category, count) in stats.category_counts.iter() {
        println!("  {}: {}", category, count);
    }
}

fn categorize_by_path(path: &str) -> String {
    let lower = path.to_lowercase();
    let text_exts = [".md", ".txt", ".lean", ".tex", ".org", ".html", ".htm", ".css", ".js", ".rs", ".py", ".json", ".yaml", ".yml", ".toml", ".xml", ".csv"];
    let image_exts = [".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"];
    let doc_exts = [".pdf"];
    let archive_exts = [".gz", ".bz2", ".xz", ".zip", ".tar"];

    if text_exts.iter().any(|ext| lower.ends_with(ext)) {
        "text".to_string()
    } else if image_exts.iter().any(|ext| lower.ends_with(ext)) {
        "image".to_string()
    } else if doc_exts.iter().any(|ext| lower.ends_with(ext)) {
        "document".to_string()
    } else if archive_exts.iter().any(|ext| lower.ends_with(ext)) {
        "archive".to_string()
    } else {
        "other".to_string()
    }
}

#[derive(Default)]
struct Statistics {
    total_count: usize,
    file_count: usize,
    dir_count: usize,
    text_count: usize,
    binary_count: usize,
    category_counts: HashMap<String, usize>,
}


