// Archive — extract and list contents of compressed archives
// Supports: .tar.gz, .tar.bz2, .tar.xz, .zip, .gz, .bz2, .xz

use std::io::Read;

/// Info about a single file within an archive
#[derive(serde::Serialize, Clone)]
pub struct ArchiveEntry {
    pub path: String,
    pub size: u64,
    pub is_dir: bool,
    pub content: Option<String>,
}

impl<'de> serde::Deserialize<'de> for ArchiveEntry {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(serde::Deserialize)]
        struct Helper {
            path: String,
            size: u64,
            is_dir: bool,
            content: Option<String>,
        }
        let h = Helper::deserialize(deserializer)?;
        Ok(ArchiveEntry {
            path: h.path,
            size: h.size,
            is_dir: h.is_dir,
            content: h.content,
        })
    }
}

impl ArchiveEntry {
    /// Check if this entry is a text file (based on extension or content)
    pub fn is_text(&self) -> bool {
        // Check extension FIRST - known text extensions are always text
        let path_lower = self.path.to_lowercase();
        let text_exts = [".md", ".txt", ".lean", ".tex", ".org", ".html", ".htm", ".css", ".js", ".rs", ".py", ".json", ".yaml", ".yml", ".toml", ".xml", ".csv"];
        if text_exts.iter().any(|ext| path_lower.ends_with(ext)) {
            return true;
        }
        
        // Fall back to content analysis for unknown extensions
        if let Some(ref content) = self.content {
            // Check if content looks like text
            let printable = content
                .bytes()
                .filter(|&b| b >= 32 && b < 127 || b == 10 || b == 13 || b == 9)
                .count();
            let total = content.len().max(1);
            printable * 100 / total > 90
        } else {
            false
        }
    }
}

/// Summary of the extracted archive
#[derive(serde::Serialize, serde::Deserialize, Clone)]
pub struct ArchiveResult {
    pub filename: String,
    pub title: String,
    pub description: String,
    pub entries: Vec<ArchiveEntry>,
    pub total_size: u64,
    pub entry_count: usize,
}

/// Allowed file extensions for markdown/lean only mode
const MARKDOWN_EXTENSIONS: &[&str] = &[
    ".md",
    ".txt",
    ".lean",
    ".tex",
    ".org",
];
/// Excluded file extensions (svg, json, etc.)
const EXCLUDED_EXTENSIONS: &[&str] = &[".svg", ".json"];
/// Maximum file size in bytes (0 = no limit)
pub const MAX_FILE_SIZE: u64 = 10 * 1024 * 1024; // 110MB

/// Detect format from filename extension and extract
pub fn extract(data: &[u8], filename: &str) -> Result<ArchiveResult, String> {
    let lower = filename.to_lowercase();

    if lower.ends_with(".tar.gz") || lower.ends_with(".tgz") {
        extract_tar_gz(data, filename)
    } else if lower.ends_with(".tar.bz2") || lower.ends_with(".tbz2") || lower.ends_with(".tbz") {
        extract_tar_bz2(data, filename)
    } else if lower.ends_with(".tar.xz") || lower.ends_with(".txz") {
        extract_tar_xz(data, filename)
    } else if lower.ends_with(".tar") {
        extract_tar(data, filename)
    } else if lower.ends_with(".zip") {
        extract_zip(data, filename)
    } else if lower.ends_with(".gz") {
        extract_single_compressed(data, filename, PhantomData::<GzipDecoder>)
    } else if lower.ends_with(".bz2") {
        extract_single_compressed(data, filename, PhantomData::<Bzip2Decoder>)
    } else if lower.ends_with(".xz") {
        extract_single_compressed(data, filename, PhantomData::<XzDecoder>)
    } else {
        Err(format!("Unsupported archive format: {}", filename))
    }
}

// ── Decoder wrappers (trait to unify single-stream decompression) ──────

trait Decoder: Read + Sized {
    fn new(r: Box<dyn Read>) -> Result<Self, String>;
}

struct GzipDecoder(flate2::read::GzDecoder<Box<dyn Read>>);
impl Decoder for GzipDecoder {
    fn new(r: Box<dyn Read>) -> Result<Self, String> {
        Ok(GzipDecoder(flate2::read::GzDecoder::new(r)))
    }
}
impl Read for GzipDecoder {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        self.0.read(buf)
    }
}

struct Bzip2Decoder(bzip2::read::BzDecoder<Box<dyn Read>>);
impl Decoder for Bzip2Decoder {
    fn new(r: Box<dyn Read>) -> Result<Self, String> {
        Ok(Bzip2Decoder(bzip2::read::BzDecoder::new(r)))
    }
}
impl Read for Bzip2Decoder {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        self.0.read(buf)
    }
}

struct XzDecoder(xz2::read::XzDecoder<Box<dyn Read>>);
impl Decoder for XzDecoder {
    fn new(r: Box<dyn Read>) -> Result<Self, String> {
        Ok(XzDecoder(xz2::read::XzDecoder::new(r)))
    }
}
impl Read for XzDecoder {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        self.0.read(buf)
    }
}

use std::marker::PhantomData;

/// Decompress a single-stream file (.gz, .bz2, .xz) — yields one entry.
fn extract_single_compressed<D: Decoder>(
    data: &[u8],
    filename: &str,
    _decoder: PhantomData<D>,
) -> Result<ArchiveResult, String> {
    let owned = data.to_vec();
    let reader: Box<dyn Read> = Box::new(std::io::Cursor::new(owned));
    let mut dec = D::new(reader).map_err(|e| format!("Decompress error: {}", e))?;

    let mut content = Vec::new();
    dec.read_to_end(&mut content)
        .map_err(|e| format!("Read error: {}", e))?;

    // Strip the compression extension for the output name
    let out_name = filename
        .rsplit_once('.')
        .map(|(base, _)| {
            // For .tar.gz → strip .gz → already handled by tar; for .gz → strip .gz
            if base.ends_with(".tar") {
                base.to_string()
            } else {
                filename
                    .trim_end_matches(".gz")
                    .trim_end_matches(".bz2")
                    .trim_end_matches(".xz")
                    .to_string()
            }
        })
        .unwrap_or_else(|| filename.to_string());

    let is_text = content.windows(4).all(|w| {
        // Very simple heuristic: if first 4 bytes are all ASCII printable
        w.iter()
            .all(|&b| b.is_ascii_graphic() || b == b'\n' || b == b'\r' || b == b'\t' || b == b' ')
    }) || content.is_empty();

    // After decompression, check if the result is actually a tar archive
    // (tar magic bytes at offset 257: "ustar"). If so, recursively extract.
    if content.len() >= 262 && &content[257..262] == b"ustar" {
        // The decompressed content is a tar archive — extract it recursively
        let tar_filename = filename
            .trim_end_matches(".gz")
            .trim_end_matches(".bz2")
            .trim_end_matches(".xz")
            .to_string();
        return extract_tar_from_reader(std::io::Cursor::new(content), &tar_filename);
    }

    let entry_content = if is_text {
        Some(String::from_utf8_lossy(&content).to_string())
    } else {
        None
    };

    let title = filename
        .trim_end_matches(".gz")
        .trim_end_matches(".bz2")
        .trim_end_matches(".xz")
        .trim_end_matches(".tar")
        .rsplit('/')
        .next()
        .unwrap_or(filename)
        .trim_end_matches('.')
        .to_string();

    Ok(ArchiveResult {
        filename: filename.to_string(),
        title,
        description: format!("Single compressed file extracted from {}", filename),
        entries: vec![ArchiveEntry {
            path: out_name,
            size: content.len() as u64,
            is_dir: false,
            content: entry_content,
        }],
        total_size: content.len() as u64,
        entry_count: 1,
    })
}

// ── Tar extraction (with various compressions) ─────────────────────────

fn extract_tar(data: &[u8], filename: &str) -> Result<ArchiveResult, String> {
    // &[u8] implements Read — pass directly without boxing
    extract_tar_from_reader(data, filename)
}

fn extract_tar_gz(data: &[u8], filename: &str) -> Result<ArchiveResult, String> {
    let dec = flate2::read::GzDecoder::new(data);
    extract_tar_from_reader(dec, filename)
}

fn extract_tar_bz2(data: &[u8], filename: &str) -> Result<ArchiveResult, String> {
    // Copy to owned Vec to avoid lifetime issues with the decoder
    let owned = data.to_vec();
    let dec = bzip2::read::BzDecoder::new(std::io::Cursor::new(owned));
    extract_tar_from_reader(dec, filename)
}

fn extract_tar_xz(data: &[u8], filename: &str) -> Result<ArchiveResult, String> {
    // Copy to owned Vec to avoid lifetime issues with the decoder
    let owned = data.to_vec();
    let dec = xz2::read::XzDecoder::new(std::io::Cursor::new(owned));
    extract_tar_from_reader(dec, filename)
}

fn extract_tar_from_reader<R: Read>(reader: R, filename: &str) -> Result<ArchiveResult, String> {
    let mut archive = tar::Archive::new(reader);
    let mut entries = Vec::new();
    let mut total_size = 0u64;

    for entry in archive.entries().map_err(|e| format!("Tar error: {}", e))? {
        let mut entry = entry.map_err(|e| format!("Tar entry error: {}", e))?;
        let path = entry
            .path()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| "unknown".to_string());
        let size = entry.size();
        let is_dir = entry.header().entry_type().is_dir();

        // Apply file filtering: exclude svg, json, and large files by default
        let lower_path = path.to_lowercase();
        
        // Skip excluded extensions (.svg, .json)
        if EXCLUDED_EXTENSIONS.iter().any(|&ext| lower_path.ends_with(ext)) {
            continue;
        }

        // Skip files larger than MAX_FILE_SIZE
        if size > MAX_FILE_SIZE {
            continue;
        }

        // A directory is a row in the viewer, not a file: it has no content
        // and must not land in the file patterns. (The tar path used to keep
        // every entry as `is_dir: false`, so directories showed up as
        // zero-byte text files.)
        if is_dir {
            entries.push(ArchiveEntry {
                path,
                size: 0,
                is_dir: true,
                content: None,
            });
            continue;
        }

        // Extraction keeps every file type: narrowing to Markdown/Lean is a
        // selection the caller makes afterwards (`--category`, `--markdown-only`,
        // or a pattern in the archive viewer), not something the reader may
        // impose. Applying the allow-list here silently dropped every .rs,
        // .html, .py, .toml … entry, so those files could never be browsed or
        // split.
        total_size += size;

        // Read content — expand the limit for known text extensions so that
        // multi-megabyte .txt/.md files are extracted instead of being
        // reported as "binary" by the archive viewer.
        let text_ext = MARKDOWN_EXTENSIONS.iter().any(|m| lower_path.ends_with(*m));
        let content_limit: u64 = if text_ext { MAX_FILE_SIZE } else { 1024 * 1024 };
        let content = if size < content_limit {
            let mut raw = Vec::new();
            let read_result = entry.read_to_end(&mut raw);
            // Only include text content, skip binary
            if read_result.is_ok() && guess_is_text(&raw) {
                Some(String::from_utf8_lossy(&raw).to_string())
            } else {
                None
            }
        } else {
            None
        };

        // Recursive unpack: nested archives (.tar.gz/.tgz/.zip inside)
        let is_nested = lower_path.ends_with(".tar.gz")
            || lower_path.ends_with(".tgz")
            || lower_path.ends_with(".tar.bz2")
            || lower_path.ends_with(".tar.xz")
            || lower_path.ends_with(".zip");
        if is_nested && content.is_some() {
            if let Ok(nested) = extract(content.as_ref().unwrap().as_bytes(), &path) {
                for mut ne in nested.entries {
                    ne.path = format!("{}/{}", path, ne.path);
                    entries.push(ne);
                }
                continue;
            }
        }

        entries.push(ArchiveEntry {
            path,
            size,
            is_dir: false,
            content,
        });
    }

    let title = filename
        .rsplit('/')
        .next()
        .unwrap_or(filename)
        .trim_end_matches(".tar.gz")
        .trim_end_matches(".tgz")
        .trim_end_matches(".tar.bz2")
        .trim_end_matches(".tbz2")
        .trim_end_matches(".tbz")
        .trim_end_matches(".tar.xz")
        .trim_end_matches(".txz")
        .trim_end_matches(".tar")
        .trim_end_matches('.')
        .to_string();

    Ok(ArchiveResult {
        filename: filename.to_string(),
        title,
        description: format!(
            "Archive extracted from {} with {} entries",
            filename,
            entries.len()
        ),
        entry_count: entries.len(),
        total_size,
        entries,
    })
}

// ── Zip extraction ─────────────────────────────────────────────────────

fn extract_zip(data: &[u8], filename: &str) -> Result<ArchiveResult, String> {
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(data))
        .map_err(|e| format!("Zip error: {}", e))?;

    let mut entries = Vec::new();
    let mut total_size = 0u64;

    for i in 0..archive.len() {
        let mut file = archive
            .by_index(i)
            .map_err(|e| format!("Zip entry {}: {}", i, e))?;

        let path = file.name().to_string();
        let lower_path = path.to_lowercase();
        let is_dir = file.is_dir();
        let size = file.size();

        // Apply file filtering: exclude svg, json, and large files by default
        // Skip excluded extensions (.svg, .json)
        if EXCLUDED_EXTENSIONS.iter().any(|&ext| lower_path.ends_with(ext)) {
            continue;
        }

        // Skip files larger than MAX_FILE_SIZE
        if size > MAX_FILE_SIZE {
            continue;
        }

        // Same as the tar reader: keep every file type, filter at selection.
        if is_dir {
            entries.push(ArchiveEntry {
                path,
                size: 0,
                is_dir: true,
                content: None,
            });
            continue;
        }

        total_size += size;

        // Same widened limit as tar: text extensions may be large.
        let text_ext = MARKDOWN_EXTENSIONS.iter().any(|m| lower_path.ends_with(*m));
        let content_limit: u64 = if text_ext { MAX_FILE_SIZE } else { 1024 * 1024 };
        let content = if size < content_limit {
            let mut buf = Vec::new();
            file.read_to_end(&mut buf).ok();
            // Only include text content, skip binary
            if guess_is_text(&buf) {
                Some(String::from_utf8_lossy(&buf).to_string())
            } else {
                None
            }
        } else {
            None
        };

        entries.push(ArchiveEntry {
            path,
            size,
            is_dir: false,
            content,
        });
    }

    let title = filename
        .rsplit('/')
        .next()
        .unwrap_or(filename)
        .trim_end_matches(".zip")
        .trim_end_matches('.')
        .to_string();

    Ok(ArchiveResult {
        filename: filename.to_string(),
        title,
        description: format!(
            "Zip archive extracted from {} with {} entries",
            filename,
            entries.len()
        ),
        entry_count: entries.len(),
        total_size,
        entries,
    })
}

// ── Utility ────────────────────────────────────────────────────────────

/// Simple heuristic: if >90% of bytes are ASCII printable or whitespace, treat as text.
fn guess_is_text(buf: &[u8]) -> bool {
    if buf.is_empty() {
        return true;
    }
    let printable = buf
        .iter()
        .filter(|&&b| b.is_ascii_graphic() || b == b'\n' || b == b'\r' || b == b'\t' || b == b' ')
        .count();
    printable > (buf.len() * 9 / 10)
}
/// Extract all files of a specific category from an archive
pub fn extract_by_category(data: &[u8], filename: &str, category: &str) -> Result<Vec<ArchiveEntry>, String> {
    let result = extract(data, filename)?;
    let filtered: Vec<ArchiveEntry> = result.entries
        .into_iter()
        .filter(|e| categorize_by_extension(&e.path) == category)
        .collect();
    Ok(filtered)
}

/// Extract all Lean files (.lean) from an archive
pub fn extract_lean_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "lean")
}

/// Extract all Markdown files (.md, .txt, .tex, .org) from an archive
pub fn extract_markdown_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "markdown")
}

/// Extract all SVG files from an archive
pub fn extract_svg_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "svg")
}

/// Extract all web files (HTML, CSS, JS) from an archive
pub fn extract_web_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "web")
}

/// Extract all GIF files from an archive
pub fn extract_gif_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "gif")
}

/// Extract all graphics files (PNG, JPG, SVG, GIF, WebP) from an archive
pub fn extract_graphics_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "graphics")
}

/// Extract all source code files from an archive
pub fn extract_source_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "source")
}

/// Extract all data files (JSON, CSV, YAML, TOML, XML) from an archive
pub fn extract_data_files(data: &[u8], filename: &str) -> Result<Vec<ArchiveEntry>, String> {
    extract_by_category(data, filename, "data")
}

/// Categorize a file by its extension
pub fn categorize_by_extension(path: &str) -> &'static str {
    let lower = path.to_lowercase();
    if lower.ends_with(".lean") {
        return "lean";
    }
    if lower.ends_with(".md") || lower.ends_with(".txt") || lower.ends_with(".tex") || lower.ends_with(".org") {
        return "markdown";
    }
    if lower.ends_with(".svg") {
        return "svg";
    }
    if lower.ends_with(".gif") {
        return "gif";
    }
    if lower.ends_with(".html") || lower.ends_with(".htm") || lower.ends_with(".css") || lower.ends_with(".js") || lower.ends_with(".ts") || lower.ends_with(".jsx") || lower.ends_with(".tsx") {
        return "web";
    }
    if lower.ends_with(".png") || lower.ends_with(".jpg") || lower.ends_with(".jpeg") || lower.ends_with(".webp") || lower.ends_with(".svg") || lower.ends_with(".gif") {
        return "graphics";
    }
    if lower.ends_with(".rs") || lower.ends_with(".py") || lower.ends_with(".go") || lower.ends_with(".java") || lower.ends_with(".cpp") || lower.ends_with(".c") || lower.ends_with(".h") || lower.ends_with(".hpp") || lower.ends_with(".js") || lower.ends_with(".ts") {
        return "source";
    }
    if lower.ends_with(".json") || lower.ends_with(".csv") || lower.ends_with(".yaml") || lower.ends_with(".yml") || lower.ends_with(".toml") || lower.ends_with(".xml") {
        return "data";
    }
    if lower.ends_with(".bin") || lower.ends_with(".exe") || lower.ends_with(".so") || lower.ends_with(".dll") || lower.ends_with(".dylib") {
        return "binary";
    }
    "other"
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn sample_targz() -> Vec<u8> {
        let mut tar_bytes = Vec::new();
        {
            let mut builder = tar::Builder::new(&mut tar_bytes);
            for (path, body) in [
                ("proj/src/main.rs", "fn main() {}\n"),
                ("proj/docs/a.md", "# a\n"),
            ] {
                let mut header = tar::Header::new_gnu();
                header.set_path(path).unwrap();
                header.set_size(body.len() as u64);
                header.set_mode(0o644);
                header.set_cksum();
                builder.append(&header, body.as_bytes()).unwrap();
            }
            builder.finish().unwrap();
        }
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gz.write_all(&tar_bytes).unwrap();
        gz.finish().unwrap()
    }

    #[test]
    fn extraction_keeps_non_markdown_sources() {
        let result = extract(&sample_targz(), "sample.tar.gz").unwrap();
        let paths: Vec<&str> = result.entries.iter().map(|e| e.path.as_str()).collect();
        assert!(
            paths.contains(&"proj/src/main.rs"),
            "a .rs entry was dropped by extraction: {:?}",
            paths
        );
        assert!(
            paths.contains(&"proj/docs/a.md"),
            "a .md entry was dropped by extraction: {:?}",
            paths
        );
    }
}
