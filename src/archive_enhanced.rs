// Enhanced archive analysis and pattern matching
// Collects ngrams, prefixes, suffixes from file paths and content
// Enables quick selection by patterns and stores common patterns

use std::collections::{HashMap, HashSet};
use std::path::Path;

/// File category for classification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileCategory {
    Lean,          // Lean proofs and documentation
    Web,           // HTML, CSS, JavaScript, web assets
    Docs,          // Markdown, text documents, notes
    Graphics,      // Images, SVG, graphics files
    Source,        // Source code (Rust, Python, etc.)
    Config,        // Configuration files
    Data,          // JSON, CSV, data files
    Binary,        // Binary executables, libraries
    Other,         // Uncategorized
}

/// Pattern analysis for a file
#[derive(Debug, Clone)]
pub struct FilePattern {
    pub path: String,
    pub category: FileCategory,
    pub ngrams: Vec<String>,           // Common ngrams from content
    pub path_prefixes: Vec<String>,   // Path prefixes
    pub path_suffixes: Vec<String>,   // Path suffixes
    pub size: u64,
    pub is_text: bool,
    pub tags: Vec<String>,             // Auto-generated tags
}

/// Pattern store for quick selection
#[derive(Debug)]
pub struct PatternStore {
    pub all_patterns: Vec<FilePattern>,
    pub category_patterns: HashMap<FileCategory, Vec<FilePattern>>,
    pub path_prefix_map: HashMap<String, Vec<FilePattern>>,   // Path prefix -> files
    pub path_suffix_map: HashMap<String, Vec<FilePattern>>,   // Path suffix -> files
    pub ngram_map: HashMap<String, Vec<FilePattern>>,          // Ngram -> files
    pub tag_map: HashMap<String, Vec<FilePattern>>,            // Tag -> files
    pub common_patterns: Vec<String>,                         // Frequently used patterns
    pub directory_groups: HashMap<String, Vec<String>>,        // Directory groups (lean, web, docs, etc.)
}

impl PatternStore {
    /// Create a new pattern store from archive entries
    pub fn from_archive_entries(entries: &[crate::archive::ArchiveEntry]) -> Self {
        let mut store = PatternStore {
            all_patterns: Vec::new(),
            category_patterns: HashMap::new(),
            path_prefix_map: HashMap::new(),
            path_suffix_map: HashMap::new(),
            ngram_map: HashMap::new(),
            tag_map: HashMap::new(),
            common_patterns: Vec::new(),
            directory_groups: HashMap::new(),
        };

        // Define directory groups for quick selection
        let mut lean_dirs = Vec::new();
        let mut web_dirs = Vec::new();
        let mut docs_dirs = Vec::new();
        let mut graphics_dirs = Vec::new();
        let mut source_dirs = Vec::new();

        for entry in entries {
            if entry.is_dir {
                continue;
            }

            let pattern = FilePattern::new(entry);
            store.all_patterns.push(pattern.clone());

            // Add to category map
            store.category_patterns
                .entry(pattern.category)
                .or_default()
                .push(pattern.clone());

            // Index by path components
            let path_lower = pattern.path.to_lowercase();
            let path = &pattern.path;

            // Add path prefixes
            if let Some(parent) = Path::new(path).parent() {
                if let Some(parent_str) = parent.to_str() {
                    let parent_lower = parent_str.to_lowercase();
                    store.path_prefix_map
                        .entry(parent_lower)
                        .or_default()
                        .push(pattern.clone());
                }
            }

            // Add path suffixes (filename with extension)
            if let Some(file_name) = Path::new(path).file_name() {
                if let Some(file_str) = file_name.to_str() {
                    let file_lower = file_str.to_lowercase();
                    store.path_suffix_map
                        .entry(file_lower)
                        .or_default()
                        .push(pattern.clone());
                }
            }

            // Add ngrams from content
            for ngram in &pattern.ngrams {
                store.ngram_map
                    .entry(ngram.clone())
                    .or_default()
                    .push(pattern.clone());
            }

            // Add tags
            for tag in &pattern.tags {
                store.tag_map
                    .entry(tag.clone())
                    .or_default()
                    .push(pattern.clone());
            }

            // Classify into directory groups
            store.classify_directory(path, &mut lean_dirs, &mut web_dirs, 
                                   &mut docs_dirs, &mut graphics_dirs, &mut source_dirs);
        }

        // Set directory groups
        if !lean_dirs.is_empty() {
            store.directory_groups.insert("lean".to_string(), lean_dirs);
        }
        if !web_dirs.is_empty() {
            store.directory_groups.insert("web".to_string(), web_dirs);
        }
        if !docs_dirs.is_empty() {
            store.directory_groups.insert("docs".to_string(), docs_dirs);
        }
        if !graphics_dirs.is_empty() {
            store.directory_groups.insert("graphics".to_string(), graphics_dirs);
        }
        if !source_dirs.is_empty() {
            store.directory_groups.insert("source".to_string(), source_dirs);
        }

        // Extract common patterns (most frequent)
        store.extract_common_patterns();

        store
    }

    /// Classify a directory path into categories
    fn classify_directory(
        path: &str,
        lean_dirs: &mut Vec<String>,
        web_dirs: &mut Vec<String>,
        docs_dirs: &mut Vec<String>,
        graphics_dirs: &mut Vec<String>,
        source_dirs: &mut Vec<String>,
    ) {
        let lower = path.to_lowercase();
        let path_obj = Path::new(path);
        let mut components = path_obj.components();
        
        // Check if any path component indicates the category
        while let Some(component) = components.next() {
            if let Some(comp_str) = component.as_os_str().to_str() {
                let comp_lower = comp_str.to_lowercase();
                
                // Lean patterns
                if comp_lower.contains("lean") || 
                   comp_lower.contains("proof") || 
                   comp_lower.contains("theorem") ||
                   comp_lower.ends_with(".lean") {
                    lean_dirs.push(path.to_string());
                    return;
                }
                
                // Web patterns
                if comp_lower.contains("web") ||
                   comp_lower.contains("html") ||
                   comp_lower.contains("css") ||
                   comp_lower.contains("js") ||
                   comp_lower.contains("asset") ||
                   lower.ends_with(".html") ||
                   lower.ends_with(".css") ||
                   lower.ends_with(".js") {
                    web_dirs.push(path.to_string());
                    return;
                }
                
                // Docs patterns
                if comp_lower.contains("doc") ||
                   comp_lower.contains("readme") ||
                   comp_lower.contains("note") ||
                   lower.ends_with(".md") ||
                   lower.ends_with(".txt") ||
                   lower.ends_with(".pdf") {
                    docs_dirs.push(path.to_string());
                    return;
                }
                
                // Graphics patterns
                if comp_lower.contains("graphic") ||
                   comp_lower.contains("image") ||
                   comp_lower.contains("img") ||
                   lower.ends_with(".png") ||
                   lower.ends_with(".jpg") ||
                   lower.ends_with(".jpeg") ||
                   lower.ends_with(".svg") ||
                   lower.ends_with(".gif") ||
                   lower.ends_with(".webp") {
                    graphics_dirs.push(path.to_string());
                    return;
                }
                
                // Source patterns
                if comp_lower.contains("src") ||
                   comp_lower.contains("source") ||
                   comp_lower.contains("lib") ||
                   comp_lower.contains("bin") ||
                   lower.ends_with(".rs") ||
                   lower.ends_with(".py") ||
                   lower.ends_with(".java") ||
                   lower.ends_with(".go") ||
                   lower.ends_with(".js") {
                    source_dirs.push(path.to_string());
                    return;
                }
            }
        }
    }

    /// Extract common patterns from the store
    fn extract_common_patterns(&mut self) {
        // Count frequency of each path component
        let mut path_component_counts: HashMap<String, usize> = HashMap::new();
        let mut extension_counts: HashMap<String, usize> = HashMap::new();

        for pattern in &self.all_patterns {
            let path_lower = pattern.path.to_lowercase();
            for component in path_lower.split('/') {
                *path_component_counts.entry(component.to_string()).or_insert(0) += 1;
            }

            if let Some(ext) = Path::new(&pattern.path).extension() {
                if let Some(ext_str) = ext.to_str() {
                    *extension_counts.entry(ext_str.to_string()).or_insert(0) += 1;
                }
            }
        }

        // Sort by frequency
        let mut sorted_components: Vec<_> = path_component_counts.into_iter().collect();
        sorted_components.sort_by(|a, b| b.1.cmp(&a.1));
        
        // Add top components to common patterns
        let mut common_count = 0;
        for (component, count) in sorted_components {
            if common_count >= 20 { break; } // Limit to top 20
            self.common_patterns.push(component);
            common_count += 1;
        }

        // Add common extensions
        let mut sorted_extensions: Vec<_> = extension_counts.into_iter().collect();
        sorted_extensions.sort_by(|a, b| b.1.cmp(&a.1));
        for (ext, count) in sorted_extensions {
            if common_count >= 30 { break; } // Limit total
            self.common_patterns.push(format!(".{}", ext));
            common_count += 1;
        }
    }

    /// Quick select files by pattern
    pub fn select_by_pattern(&self, pattern: &str) -> Vec<FilePattern> {
        let mut results = Vec::new();

        // Try exact match first
        if let Some(files) = self.path_prefix_map.get(pattern) {
            results.extend(files.clone());
            return results;
        }

        // Try case-insensitive partial match
        for (key, files) in &self.path_prefix_map {
            if key.contains(&pattern.to_lowercase()) || pattern.contains(&key.to_lowercase()) {
                results.extend(files.clone());
            }
        }

        // Try ngram matches
        if let Some(files) = self.ngram_map.get(pattern) {
            results.extend(files.clone());
        }

        // Try tag matches
        if let Some(files) = self.tag_map.get(pattern) {
            results.extend(files.clone());
        }

        // Remove duplicates
        results.sort_by(|a, b| a.path.cmp(&b.path));
        results.dedup_by(|a, b| a.path == b.path);

        results
    }

    /// Get files by category
    pub fn get_by_category(&self, category: FileCategory) -> Vec<FilePattern> {
        self.category_patterns.get(&category).unwrap_or(&Vec::new()).clone()
    }

    /// Get files by directory group
    pub fn get_by_directory_group(&self, group: &str) -> Vec<FilePattern> {
        if let Some(dirs) = self.directory_groups.get(group) {
            let mut result = Vec::new();
            for dir in dirs {
                if let Some(files) = self.path_prefix_map.get(dir.to_lowercase()) {
                    result.extend(files.clone());
                }
            }
            result
        } else {
            Vec::new()
        }
    }

    /// Get all common patterns
    pub fn get_common_patterns(&self) -> &[String] {
        &self.common_patterns
    }
}

impl FilePattern {
    /// Create a new file pattern from an archive entry
    fn new(entry: &crate::archive::ArchiveEntry) -> Self {
        let path = entry.path.clone();
        let size = entry.size;
        let is_text = entry.content.is_some();

        // Determine category
        let category = classify_file_category(&path, is_text);

        // Extract ngrams from content if available
        let ngrams = if let Some(ref content) = entry.content {
            crate::tagging::extract_ngrams(content, 3, 10) // Top 10 trigrams
                .into_iter()
                .map(|(ngram, _)| ngram)
                .collect()
        } else {
            Vec::new()
        };

        // Extract path components
        let path_lower = path.to_lowercase();
        let path_obj = Path::new(&path);

        let path_prefixes = if let Some(parent) = path_obj.parent() {
            if let Some(parent_str) = parent.to_str() {
                vec![parent_str.to_string(), parent_str.to_lowercase()]
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };

        let path_suffixes = if let Some(file_name) = path_obj.file_name() {
            if let Some(file_str) = file_name.to_str() {
                let file_lower = file_str.to_lowercase();
                let mut suffixes = Vec::new();

                // Full filename
                suffixes.push(file_str.to_string());
                suffixes.push(file_lower.clone());

                // File with extension
                if let Some(ext) = path_obj.extension() {
                    if let Some(ext_str) = ext.to_str() {
                        suffixes.push(format!(".{}", ext_str));
                        suffixes.push(format!(".{}", ext_str.to_lowercase()));
                    }
                }

                // Just the filename without extension
                if let Some(file_name_no_ext) = path_obj.file_stem() {
                    if let Some(file_name_no_ext_str) = file_name_no_ext.to_str() {
                        suffixes.push(file_name_no_ext_str.to_string());
                        suffixes.push(file_name_no_ext_str.to_lowercase());
                    }
                }

                suffixes
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };

        // Auto-generate tags
        let tags = if is_text {
            crate::tagging::auto_tag(entry.content.as_deref().unwrap_or(""))
        } else {
            Vec::new()
        };

        Self {
            path,
            category,
            ngrams,
            path_prefixes,
            path_suffixes,
            size,
            is_text,
            tags,
        }
    }
}

/// Classify a file into a category based on its path and content
fn classify_file_category(path: &str, is_text: bool) -> FileCategory {
    let lower = path.to_lowercase();
    let path_obj = Path::new(path);

    // Check file extension
    if let Some(ext) = path_obj.extension() {
        if let Some(ext_str) = ext.to_str() {
            match ext_str.to_lowercase().as_str() {
                // Lean category
                "lean" => return FileCategory::Lean,

                // Web category
                "html" | "htm" | "css" | "js" | "json" => return FileCategory::Web,

                // Docs category
                "md" | "markdown" | "txt" | "text" | "pdf" | "rst" | "adoc" => {
