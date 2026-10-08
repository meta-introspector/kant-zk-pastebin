// Archive utility functions for enhanced filtering and pattern analysis
use std::collections::{HashMap, HashSet};
use regex_lite::Regex;
use std::path::Path;

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
        let lower = path.to_lowercase();
        let path_obj = Path::new(path);
        
        // Determine category based on extension and path
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
                    "rs" | "py" | "java" | "cpp" | "c" | "go" | "rs" => return "source".to_string(),
                    "pdf" => return "document".to_string(),
                    "zip" | "tar" | "gz" | "bz2" | "xz" => return "archive".to_string(),
                    _ => {}
                }
            }
        }
        
        // Check path patterns
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
                    .push(parent_lower);
                
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
                let regex_pattern = pattern.replace('*', ".*").replace('.', "\.");
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
        let content = entry.content;
        
        let category = Self::categorize_entry(&entry);
        let patterns = Self::extract_path_patterns(&path);
        let is_excluded_by_default = Self::should_filter_entry(&entry, config);
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