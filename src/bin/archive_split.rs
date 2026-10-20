use kant_pastebin::archive::{extract, ArchiveResult};
use std::path::Path;
use std::fs;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: {} <archive_path> [--json]", args[0]);
        std::process::exit(1);
    }

    let archive_path = &args[1];
    let json_output = args.get(2).map(|s| s == "--json").unwrap_or(false);

    let path = Path::new(archive_path);
    if !path.exists() {
        eprintln!("Error: archive file not found: {}", archive_path);
        std::process::exit(1);
    }

    match fs::read(path) {
        Ok(data) => {
            match extract(&data, archive_path) {
                Ok(result) => {
                    if json_output {
                        let json_str = serde_json::to_string_pretty(&result).unwrap_or_default();
                        print!("{}", json_str);
                    } else {
                        print_archive_result(&result);
                    }
                }
                Err(e) => {
                    eprintln!("Error extracting archive: {}", e);
                    std::process::exit(1);
                }
            }
        }
        Err(e) => {
            eprintln!("Error reading file: {}", e);
            std::process::exit(1);
        }
    }
}

fn print_archive_result(result: &ArchiveResult) {
    println!("Archive: {}", result.filename);
    println!("Title: {}", result.title);
    println!("Description: {}", result.description);
    println!("Entries: {}", result.entry_count);
    println!("Total size: {} bytes", result.total_size);
    println!();

    for (i, entry) in result.entries.iter().enumerate() {
        let icon = if entry.is_dir { "📁" } else { "📄" };
        let size = if entry.size < 1024 {
            format!("{} B", entry.size)
        } else if entry.size < 1024 * 1024 {
            format!("{} KB", entry.size / 1024)
        } else {
            format!("{} MB", entry.size / (1024 * 1024))
        };
        let is_text = if entry.is_text() { "text" } else { "binary" };
        print!("{}. {} {}  {}  {}", i + 1, icon, entry.path, size, is_text);
        if !entry.is_dir && entry.content.is_some() {
            print!("  {} chars", entry.content.as_ref().unwrap().len());
        }
        println!();
    }
}