// Archive utility functions for enhanced filtering and pattern analysis
use std::collections::{HashMap, HashSet};
use regex_lite::Regex;
use std::path::Path;

/// Pattern store for archive file analysis and selection
///
/// This struct holds all pattern analysis results for an archive and
/// provides fast lookup by category, path prefix/suffix, ngram, or tag.
///
/// # Example
/// ```no_run
/// let store = PatternStore::from_archive_entries(&entries);
/// let lean_files = store.get_by_category(FileCategory::Lean);
/// let results = store.select_by_pattern("src");
/// ```
#[derive(Debug, Clone, Default)]
pub struct PatternStore {
    /// All patterns extracted from the archive
    pub all_patterns: Vec<FilePattern>,
    /// Files grouped by category
    pub category_patterns: HashMap<FileCategory, Vec<FilePattern>>,
    /// Path prefix -> matching files
    pub path_prefix_map: HashMap<String, Vec<FilePattern>>,
    /// Path suffix (filename) -> matching files
    pub path_suffix_map: HashMap<String, Vec<FilePattern>>,
    /// Ngram -> matching files
    pub ngram_map: HashMap<String, Vec<FilePattern>>,
    /// Tag -> matching files
    pub tag_map: HashMap<String, Vec<FilePattern>>,
    /// Common (frequent) patterns for quick access
    pub common_patterns: Vec<String>,
    /// Directory groups (e.g. leans/, web/, docs/) -> directory paths
    pub directory_groups: HashMap<String, Vec<String>>,
}

/// File category for classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum FileCategory {
    /// Lean proof and documentation files
    Lean = 0,
    /// Documentation files (markdown, text)
    Docs = 1,
    /// Web files (HTML, CSS, JS)
    Web = 2,
    /// Graphics and images
    Graphics = 3,
    /// Source code files
    Source = 4,
    /// Configuration files
    Config = 5,
    /// Data files (JSON, CSV, etc.)
    Data = 6,
    /// Binary files
    Binary = 7,
    /// Uncategorized
    #[default]
    Other = 8,
}

/// File pattern extracted from an archive entry
#[derive(Debug, Clone)]
pub struct FilePattern {
    pub path: String,
    pub category: FileCategory,
    pub ngrams: Vec<String>,
    pub path_prefixes: Vec<String>,
    pub path_suffixes: Vec<String>,
    pub size: u64,
    pub is_text: bool,
    pub tags: Vec<String>,
}

impl FilePattern {
    /// Create a file pattern from an archive entry
    pub fn from_entry(entry: &crate::archive::ArchiveEntry) -> Self {
        let path = entry.path.clone();
        let category = Self::categorize_entry(&entry);
        let ngrams = Self::extract_ngrams(&path);
        let path_prefixes = Self::extract_path_prefixes(&path);
        let path_suffixes = Self::extract_path_suffixes(&path);
        let size = entry.size;
        let is_text = entry.is_text();
        let tags = Self::generate_tags(&path);
        
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

    /// Categorize entry based on path
    fn categorize_entry(entry: &crate::archive::ArchiveEntry) -> FileCategory {
        let path = &entry.path;
        let path_obj = Path::new(path);
        
        if let Some(ext) = path_obj.extension() {
            if let Some(ext_str) = ext.to_str() {
                match ext_str.to_lowercase().as_str() {
                    "lean" => return FileCategory::Lean,
                    "md" | "markdown" => return FileCategory::Docs,
                    "txt" | "text" => return FileCategory::Docs,
                    "html" | "htm" => return FileCategory::Web,
                    "js" | "css" => return FileCategory::Web,
                    "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" => return FileCategory::Graphics,
                    "json" => return FileCategory::Data,
                    "rs" | "py" | "java" | "cpp" | "c" | "go" => return FileCategory::Source,
                    "pdf" | "tex" => return FileCategory::Docs,
                    "zip" | "tar" | "gz" | "bz2" | "xz" => return FileCategory::Other,
                    _ => {}
                }
            }
        }
        
        let lower = path.to_lowercase();
        if lower.contains("lean") || lower.contains("proof") {
            return FileCategory::Lean;
        } else if lower.contains("doc") || lower.contains("readme") {
            return FileCategory::Docs;
        } else if lower.contains("web") || lower.contains("site") {
            return FileCategory::Web;
        } else if lower.contains("image") || lower.contains("img") {
            return FileCategory::Graphics;
        } else if lower.contains("source") || lower.contains("src") {
            return FileCategory::Source;
        } else if lower.contains("data") || lower.contains("dataset") {
            return FileCategory::Data;
        }
        
        FileCategory::Other
    }

    /// Extract ngrams from path
    fn extract_ngrams(path: &str) -> Vec<String> {
        let mut ngrams = Vec::new();
        let words: Vec<&str> = path
            .split(|c: char| c == '/' || c == '_' || c == '-')
            .filter(|w| !w.is_empty())
            .collect();
        
        for i in 0..words.len().saturating_sub(1) {
            if i < words.len() - 1 {
                ngrams.push(format!("{} {}", words[i], words[i + 1]));
            }
        }
        ngrams
    }

    /// Extract path prefixes (directories)
    fn extract_path_prefixes(path: &str) -> Vec<String> {
        let mut prefixes = Vec::new();
        let path_obj = Path::new(path);
        
        if let Some(parent) = path_obj.parent() {
            if let Some(parent_str) = parent.to_str() {
                let parent_lower = parent_str.to_lowercase();
                prefixes.push(parent_lower.clone());
                
                // Extract individual directory components
                for component in parent_lower.split('/') {
                    if !component.is_empty() {
                        prefixes.push(component.to_string());
                    }
                }
            }
        }
        
        prefixes
    }

    /// Extract path suffixes (filename + extension)
    fn extract_path_suffixes(path: &str) -> Vec<String> {
        let mut suffixes = Vec::new();
        let path_obj = Path::new(path);
        
        if let Some(file_name) = path_obj.file_name() {
            if let Some(file_str) = file_name.to_str() {
                let file_lower = file_str.to_lowercase();
                suffixes.push(file_lower.clone());
                
                // Filename without extension
                if let Some(file_stem) = path_obj.file_stem() {
                    if let Some(file_stem_str) = file_stem.to_str() {
                        suffixes.push(file_stem_str.to_lowercase());
                    }
                }
                
                // Extract words from filename (snake_case, kebab-case, camelCase)
                let camel_lower = file_lower.clone();
                let snake_lower = camel_lower.replace('-', "_");
                for word in snake_lower.split('_') {
                    if !word.is_empty() {
                        suffixes.push(word.to_string());
                    }
                }
            }
        }
        
        suffixes
    }

    /// Generate tags based on file path
    fn generate_tags(path: &str) -> Vec<String> {
        let mut tags = Vec::new();
        let path_obj = Path::new(path);
        
        // Add extension tag
        if let Some(ext) = path_obj.extension() {
            if let Some(ext_str) = ext.to_str() {
                tags.push(format!("ext:{}", ext_str.to_lowercase()));
            }
        }
        
        // Add path prefix tags
        if let Some(parent) = path_obj.parent() {
            if let Some(parent_str) = parent.to_str() {
                for component in parent_str.to_lowercase().split('/') {
                    if !component.is_empty() && component.len() > 2 {
                        tags.push(format!("dir:{}", component));
                    }
                }
            }
        }
        
        // Add filename stem tags
        if let Some(file_stem) = path_obj.file_stem() {
            if let Some(file_stem_str) = file_stem.to_str() {
                let file_lower = file_stem_str.to_lowercase();
                // Split into words (camelCase, snake_case, kebab-case)
                let file_lower_owned = file_lower.replace('-', "_");
                let words: Vec<&str> = file_lower_owned.split('_').collect();
                for word in words {
                    tags.push(format!("word:{}", word));
                }
            }
        }
        
        tags
    }
}

impl PatternStore {
    /// Create a new empty pattern store
    pub fn new() -> Self {
        Self::default()
    }

    /// Build a pattern store from a list of archive entries
    ///
    /// Analyzes each file path and content to extract patterns,
    /// categorize files, and build lookup maps.
    pub fn from_archive_entries(entries: &[crate::archive::ArchiveEntry]) -> Self {
        use crate::archive_utils::FileCategory as Cat;

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

        // Collect top-level directories by category for quick grouping
        let mut lean_dirs: Vec<String> = Vec::new();
        let mut docs_dirs: Vec<String> = Vec::new();
        let mut web_dirs: Vec<String> = Vec::new();
        let mut graphics_dirs: Vec<String> = Vec::new();
        let mut source_dirs: Vec<String> = Vec::new();
        let mut dir_seen: HashSet<String> = HashSet::new();

        for entry in entries.iter().filter(|e| !e.is_dir) {
            let pattern = FilePattern::from_entry(entry);
            store.all_patterns.push(pattern.clone());

            // Group by category
            store
                .category_patterns
                .entry(pattern.category)
                .or_default()
                .push(pattern.clone());

            // Index by path prefixes (directories)
            if let Some(parent) = Path::new(&pattern.path).parent() {
                if let Some(parent_str) = parent.to_str() {
                    let parent_lower = parent_str.to_lowercase();
                    store.path_prefix_map
                        .entry(parent_lower.clone())
                        .or_default()
                        .push(pattern.clone());

                    // Track top-level directories for quick selection
                    let is_top =
                        parent.to_string_lossy().trim_end_matches('/').matches('/').count() <= 1;
                    if is_top && dir_seen.insert(parent_lower.clone()) {
                        match pattern.category {
                            Cat::Lean => lean_dirs.push(parent_lower),
                            Cat::Docs => docs_dirs.push(parent_lower),
                            Cat::Web => web_dirs.push(parent_lower),
                            Cat::Graphics => graphics_dirs.push(parent_lower),
                            Cat::Source => source_dirs.push(parent_lower),
                            _ => {}
                        }
                    }
                }
            }

            // Index by suffix (filename + extension)
            if let Some(file_name) = Path::new(&pattern.path).file_name() {
                if let Some(file_str) = file_name.to_str() {
                    let file_lower = file_str.to_lowercase();
                    store
                        .path_suffix_map
                        .entry(file_lower)
                        .or_default()
                        .push(pattern.clone());
                }
            }

            // Index by content ngrams
            for ngram in &pattern.ngrams {
                store
                    .ngram_map
                    .entry(ngram.clone())
                    .or_default()
                    .push(pattern.clone());
            }

            // Index by tags
            for tag in &pattern.tags {
                store
                    .tag_map
                    .entry(tag.clone())
                    .or_default()
                    .push(pattern.clone());
            }
        }

        // Store top-level directory groups
        for dir in lean_dirs {
            store.directory_groups.entry("lean".to_string()).or_default().push(dir);
        }
        for dir in docs_dirs {
            store.directory_groups.entry("docs".to_string()).or_default().push(dir);
        }
        for dir in web_dirs {
            store.directory_groups.entry("web".to_string()).or_default().push(dir);
        }
        for dir in graphics_dirs {
            store.directory_groups.entry("graphics".to_string()).or_default().push(dir);
        }
        for dir in source_dirs {
            store.directory_groups.entry("source".to_string()).or_default().push(dir);
        }

        // Extract common patterns (most frequent)
        store.extract_common_patterns();

        store
    }

    /// Get files that match a search pattern
    ///
    /// Searches path prefixes, ngrams, and tags for the given pattern.
    ///
    /// # Example
    /// ```no_run
    /// let matches = store.select_by_pattern("src");
    /// ```
    pub fn select_by_pattern(&self, pattern: &str) -> Vec<FilePattern> {
        let mut results = Vec::new();
        let pat_lower = pattern.to_lowercase();

        // Prefix / directory match
        for (key, files) in &self.path_prefix_map {
            if key.contains(&pat_lower) || pat_lower.contains(key) {
                results.extend(files.clone());
            }
        }

        // Ngram match
        if let Some(files) = self.ngram_map.get(&pat_lower) {
            results.extend(files.clone());
        }

        // Tag match
        if let Some(files) = self.tag_map.get(&pat_lower) {
            results.extend(files.clone());
        }

        results.sort_by(|a, b| a.path.cmp(&b.path));
        results.dedup_by(|a, b| a.path == b.path);
        results
    }

    /// Get files in a given category
    ///
    /// # Example
    /// ```no_run
    /// let lean = store.get_by_category(FileCategory::Lean);
    /// ```
    pub fn get_by_category(&self, category: FileCategory) -> Vec<FilePattern> {
        self.category_patterns.get(&category).cloned().unwrap_or_default()
    }

    /// Get files under a top-level directory group
    ///
    /// Groups: "lean", "docs", "web", "graphics", "source"
    pub fn get_by_directory(&self, dir: &str) -> Vec<FilePattern> {
        // Filter all patterns by the directory group
        self.all_patterns
            .iter()
            .filter(|p| self.directory_groups.get(dir).map(|dirs| dirs.iter().any(|d| p.path.starts_with(d))).unwrap_or(false))
            .cloned()
            .collect()
    }

    /// Get a file by exact path
    pub fn get_by_path(&self, path: &str) -> Option<FilePattern> {
        self.all_patterns.iter().find(|p| p.path == path).cloned()
    }

    /// Return all unique common patterns for quick selection UI
    pub fn get_common_patterns(&self) -> &[String] {
        &self.common_patterns
    }

    /// Analyze all paths to find frequently used prefixes and suffixes
    fn extract_common_patterns(&mut self) {
        let mut prefix_counts: HashMap<String, usize> = HashMap::new();
        let mut ext_counts: HashMap<String, usize> = HashMap::new();

        for pattern in &self.all_patterns {
            if let Some(parent) = Path::new(&pattern.path).parent() {
                if let Some(p) = parent.to_str() {
                    *prefix_counts.entry(p.to_string()).or_insert(0) += 1;
                }
            }
            if let Some(ext) = Path::new(&pattern.path).extension() {
                if let Some(e) = ext.to_str() {
                    *ext_counts.entry(e.to_string()).or_insert(0) += 1;
                }
            }
        }

        // Most common prefixes first (up to 20)
        let mut sorted_prefixes: Vec<_> = prefix_counts.into_iter().collect();
        sorted_prefixes.sort_by(|a, b| b.1.cmp(&a.1));
        let mut pushed = 0;
        for (prefix, _) in sorted_prefixes {
            if pushed >= 20 {
                break;
            }
            self.common_patterns.push(prefix);
            pushed += 1;
        }

        // Most common extensions (up to 10)
        let mut sorted_exts: Vec<_> = ext_counts.into_iter().collect();
        sorted_exts.sort_by(|a, b| b.1.cmp(&a.1));
        for (ext, _) in sorted_exts {
            if pushed >= 30 {
                break;
            }
            self.common_patterns.push(format!(".{}", ext));
            pushed += 1;
        }
    }
}

/// Enhanced archive entry with pattern analysis
#[derive(Debug, Clone)]
pub struct EnhancedArchiveEntry {
    pub path: String,
    pub size: u64,
    pub is_dir: bool,
    pub content: Option<String>,
    pub patterns: HashMap<String, Vec<String>>, // pattern type -> matches
    pub category: String,
    pub tags: Vec<String>,
    pub is_excluded_by_default: bool,
    pub is_markdown_lean_only: bool,
}

/// Archive filtering configuration
#[derive(Debug, Clone)]
pub struct ArchiveFilterConfig {
    pub exclude_extensions: HashSet<String>,
    pub exclude_patterns: Vec<String>, // Path patterns to exclude
    pub include_extensions: HashSet<String>, // Empty means include all
    pub max_file_size: u64,
    pub exclude_svg: bool,
    pub exclude_json: bool,
    pub exclude_large_files: bool,
    pub markdown_lean_only: bool,
}

impl Default for ArchiveFilterConfig {
    fn default() -> Self {
        let mut exclude_extensions = HashSet::new();
        exclude_extensions.insert("svg".to_string());
        exclude_extensions.insert("json".to_string());
        
        let mut include_extensions = HashSet::new();
        include_extensions.insert("md".to_string());
        include_extensions.insert("txt".to_string());
        include_extensions.insert("lean".to_string());
        include_extensions.insert("tex".to_string());
        include_extensions.insert("html".to_string());
        include_extensions.insert("htm".to_string());
        include_extensions.insert("js".to_string());
        include_extensions.insert("css".to_string());
        include_extensions.insert("rs".to_string());
        include_extensions.insert("py".to_string());
        include_extensions.insert("java".to_string());
        
        Self {
            exclude_extensions,
            exclude_patterns: vec![
                "*.tmp".to_string(),
                "*.bak".to_string(),
                "*.~*".to_string(),
            ],
            include_extensions,
            max_file_size: 10 * 1024 * 1024, // 10MB
            exclude_svg: true,
            exclude_json: true,
            exclude_large_files: true,
            markdown_lean_only: false, // Default to include all text files
        }
    }
}

/// Pattern analyzer for archive files
pub struct ArchivePatternAnalyzer;

impl ArchivePatternAnalyzer {
    /// Analyze archive entry and categorize it
    pub fn categorize_entry(entry: &crate::archive::ArchiveEntry) -> String {
        let path = &entry.path;
        let path_obj = Path::new(path);
        
        if let Some(ext) = path_obj.extension() {
            if let Some(ext_str) = ext.to_str() {
                match ext_str.to_lowercase().as_str() {
                    "lean" => return "lean".to_string(),
                    "md" | "markdown" => return "markdown".to_string(),
                    "txt" | "text" => return "text".to_string(),
                    "html" | "htm" => return "web".to_string(),
                    "js" | "css" => return "web".to_string(),
                    "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" => return "graphics".to_string(),
                    "json" => return "data".to_string(),
                    "rs" | "py" | "java" | "cpp" | "c" | "go" => return "source".to_string(),
                    "pdf" => return "document".to_string(),
                    "zip" | "tar" | "gz" | "bz2" | "xz" => return "archive".to_string(),
                    _ => {}
                }
            }
        }
        
        let lower = path.to_lowercase();
        if lower.contains("lean") || lower.contains("proof") {
            return "lean".to_string();
        } else if lower.contains("doc") || lower.contains("readme") {
            return "markdown".to_string();
        } else if lower.contains("web") || lower.contains("site") {
            return "web".to_string();
        } else if lower.contains("image") || lower.contains("img") {
            return "graphics".to_string();
        } else if lower.contains("source") || lower.contains("src") {
            return "source".to_string();
        } else if lower.contains("data") || lower.contains("dataset") {
            return "data".to_string();
        }
        
        "other".to_string()
    }

    /// Extract patterns from a file path
    pub fn extract_path_patterns(path: &str) -> HashMap<String, Vec<String>> {
        let mut patterns: HashMap<String, Vec<String>> = HashMap::new();
        let lower = path.to_lowercase();
        let path_obj = Path::new(path);
        
        // File extension patterns
        if let Some(ext) = path_obj.extension() {
            if let Some(ext_str) = ext.to_str() {
                patterns.entry("extension".to_string())
                    .or_default()
                    .push(ext_str.to_lowercase());
            }
        }
        
        // Directory path patterns
        if let Some(parent) = path_obj.parent() {
            if let Some(parent_str) = parent.to_str() {
                let parent_lower = parent_str.to_lowercase();
                patterns.entry("parent_directory".to_string())
                    .or_default()
                    .push(parent_lower.clone());
                
                // Extract individual directory components
                for component in parent_lower.split('/') {
                    if !component.is_empty() {
                        patterns.entry("directory".to_string())
                            .or_default()
                            .push(component.to_string());
                    }
                }
            }
        }
        
        // Filename patterns
        if let Some(file_name) = path_obj.file_name() {
            if let Some(file_str) = file_name.to_str() {
                let file_lower = file_str.to_lowercase();
                patterns.entry("filename".to_string())
                    .or_default()
                    .push(file_lower.clone());
                
                // Filename without extension
                if let Some(file_stem) = path_obj.file_stem() {
                    if let Some(file_stem_str) = file_stem.to_str() {
                        patterns.entry("filename_stem".to_string())
                            .or_default()
                            .push(file_stem_str.to_lowercase());
                    }
                }
                
                // Filename patterns (snake_case, kebab-case, camelCase)
                if file_lower.contains('_') {
                    patterns.entry("snake_case".to_string())
                        .or_default()
                        .push(file_lower.clone());
                }
                
                if file_lower.contains('-') {
                    patterns.entry("kebab_case".to_string())
                        .or_default()
                        .push(file_lower.clone());
                }
                
                if file_lower.chars().any(|c| c.is_uppercase()) {
                    patterns.entry("camel_case".to_string())
                        .or_default()
                        .push(file_lower.clone());
                }
            }
        }
        
        // Timestamp patterns (if present)
        let timestamp_pattern = r"\d{4}-\d{2}-\d{2}|\d{2}-\d{2}-\d{4}|\d{4}\.\d{2}\.\d{2}|\d{8}";
        if Regex::new(timestamp_pattern).unwrap().is_match(&lower) {
            patterns.entry("timestamp".to_string())
                .or_default()
                .push(lower.clone());
        }
        
        // Numeric patterns
        let digit_pattern = r"\d+";
        if Regex::new(digit_pattern).unwrap().is_match(&lower) {
            patterns.entry("numeric".to_string())
                .or_default()
                .push(lower.clone());
        }
        
        patterns
    }
    
    /// Check if an archive entry should be filtered based on configuration
    pub fn should_filter_entry(entry: &crate::archive::ArchiveEntry, config: &ArchiveFilterConfig) -> bool {
        // Check if entry is a directory (we only care about files)
        if entry.is_dir {
            return false;
        }
        
        let path = &entry.path;
        let lower = path.to_lowercase();
        let path_obj = Path::new(path);
        
        // Check file extension exclusions
        if let Some(ext) = path_obj.extension() {
            if let Some(ext_str) = ext.to_str() {
                let ext_lower = ext_str.to_lowercase();
                
                // Check if extension is in exclude list
                if config.exclude_extensions.contains(&ext_lower) {
                    return true;
                }
                
                // If include_extensions is not empty, only include specified extensions
                if !config.include_extensions.is_empty() {
                    if !config.include_extensions.contains(&ext_lower) {
                        return true;
                    }
                }
                
                // Special exclusions
                if config.exclude_svg && ext_lower == "svg" {
                    return true;
                }
                
                if config.exclude_json && ext_lower == "json" {
                    return true;
                }
            }
        }
        
        // Check file size
        if config.exclude_large_files && entry.size > config.max_file_size {
            return true;
        }
        
        // Check path pattern exclusions
        for pattern in &config.exclude_patterns {
            if pattern.contains('*') {
                // Convert glob pattern to regex
                let regex_pattern = pattern.replace('*', ".*").replace('.', "\\.");
                if let Ok(re) = Regex::new(&regex_pattern) {
                    if re.is_match(&lower) {
                        return true;
                    }
                }
            } else if lower.contains(&pattern.to_lowercase()) {
                return true;
            }
        }
        
        // Markdown/lean only mode
        if config.markdown_lean_only {
            let allowed_extensions = vec!["md", "markdown", "txt", "lean", "tex", "html", "htm"];
            if let Some(ext) = path_obj.extension() {
                if let Some(ext_str) = ext.to_str() {
                    let ext_lower = ext_str.to_lowercase();
                    if !allowed_extensions.contains(&ext_lower.as_str()) {
                        return true;
                    }
                }
            } else {
                // No extension, exclude if not in allowed list
                let allowed_no_ext = vec!["readme", "license", "contributing", "changelog", "history"];
                let file_name = path_obj.file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("");
                let file_lower = file_name.to_lowercase();
                if !allowed_no_ext.iter().any(|allowed| file_lower.contains(allowed)) {
                    return true;
                }
            }
        }
        
        false
    }
    
    /// Create enhanced archive entry from original entry
    pub fn create_enhanced_entry(entry: crate::archive::ArchiveEntry, config: &ArchiveFilterConfig) -> EnhancedArchiveEntry {
        let path = entry.path.clone();
        let size = entry.size;
        let is_dir = entry.is_dir;
        
        // Get category first (needs to borrow entry)
        let category = Self::categorize_entry(&entry);
        
        // Compute exclusions (needs to borrow entry)
        let is_excluded_by_default = Self::should_filter_entry(&entry, config);
        
        // Get content AFTER all borrows are done
        let content = entry.content;
        
        let patterns = Self::extract_path_patterns(&path);
        let is_markdown_lean_only = config.markdown_lean_only && (
            category == "lean" || 
            category == "markdown" || 
            category == "text" ||
            category == "web"
        );
        
        // Generate tags based on patterns and content
        let tags = Self::generate_tags(&path, &patterns, content.as_deref().unwrap_or(""));
        
        EnhancedArchiveEntry {
            path,
            size,
            is_dir,
            content,
            patterns,
            category,
            tags,
            is_excluded_by_default,
            is_markdown_lean_only,
        }
    }
    
    /// Generate tags for a file based on its properties
    fn generate_tags(path: &str, patterns: &HashMap<String, Vec<String>>, content: &str) -> Vec<String> {
        let mut tags = Vec::new();
        let lower = path.to_lowercase();
        let path_obj = Path::new(path);
        
        // Add extension tag
        if let Some(ext) = path_obj.extension() {
            if let Some(ext_str) = ext.to_str() {
                tags.push(format!("ext:{}", ext_str.to_lowercase()));
            }
        }
        
        // Add directory tags
        if let Some(parent) = path_obj.parent() {
            if let Some(parent_str) = parent.to_str() {
                for component in parent_str.to_lowercase().split('/') {
                    if !component.is_empty() && component.len() > 2 {
                        tags.push(format!("dir:{}", component));
                    }
                }
            }
        }
        
        // Add filename tags
        if let Some(file_name) = path_obj.file_name() {
            if let Some(file_str) = file_name.to_str() {
                let file_lower = file_str.to_lowercase();
                // Split filename into words (snake_case, kebab-case, spaces)
                let words: Vec<&str> = file_lower.split(|c| c == '_' || c == '-' || c == ' ').collect();
                for word in words.iter().filter(|w| !w.is_empty() && w.len() > 2) {
                    tags.push(format!("word:{}", word));
                }
            }
        }
        
        // Add content-based tags using existing tagging module
        let auto_tags = crate::tagging::auto_tag(content);
        tags.extend(auto_tags);
        
        // Add timestamp tags
        let timestamp_pattern = r"\d{4}-\d{2}-\d{2}|\d{2}-\d{2}-\d{4}|\d{4}\.\d{2}\.\d{2}|\d{8}";
        if Regex::new(timestamp_pattern).unwrap().is_match(&lower) {
            tags.push("timestamped".to_string());
        }
        
        tags
    }
    
    /// Convert enhanced archive entries back to original format
    pub fn convert_to_original_format(entries: &[EnhancedArchiveEntry]) -> Vec<crate::archive::ArchiveEntry> {
        entries.iter()
            .map(|enhanced| {
                crate::archive::ArchiveEntry {
                    path: enhanced.path.clone(),
                    size: enhanced.size,
                    is_dir: enhanced.is_dir,
                    content: enhanced.content.clone(),
                }
            })
            .collect()
    }
}