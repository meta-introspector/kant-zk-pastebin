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

/// Summary of the extracted archive
#[derive(serde::Serialize)]
pub struct ArchiveResult {
    pub filename: String,
    pub title: String,
    pub description: String,
    pub entries: Vec<ArchiveEntry>,
    pub total_size: u64,
    pub entry_count: usize,
}

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

        // Skip directory entries in content listing
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

        // Read content for all files (smallish files only) — no binary
        // filter: preserve every file's content (lossy for binary).
        let mut raw = Vec::new();
        let content = if size < 1024 * 1024 {
            entry.read_to_end(&mut raw).ok();
            Some(String::from_utf8_lossy(&raw).to_string())
        } else {
            None
        };

        // Recursive unpack: nested archives (.tar.gz/.tgz/.zip inside)
        let lower_path = path.to_lowercase();
        let is_nested = lower_path.ends_with(".tar.gz")
            || lower_path.ends_with(".tgz")
            || lower_path.ends_with(".tar.bz2")
            || lower_path.ends_with(".tar.xz")
            || lower_path.ends_with(".zip");
        if is_nested && !raw.is_empty() {
            if let Ok(nested) = extract(&raw, &path) {
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
        let is_dir = file.is_dir();
        let size = file.size();

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

        let content = if size < 1024 * 1024 {
            let mut buf = Vec::new();
            file.read_to_end(&mut buf).ok();
            Some(String::from_utf8_lossy(&buf).to_string())
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
