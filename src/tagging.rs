// Tagging - Auto-tagging, content analysis, and text utilities
use std::collections::HashMap;

pub fn slugify(s: &str) -> String {
    // Strip URLs before slugifying
    let cleaned: String = s.split_whitespace()
        .filter(|w| !w.starts_with("http://") && !w.starts_with("https://"))
        .collect::<Vec<_>>()
        .join(" ");
    let slug: String = cleaned.chars()
        .map(|c| if c.is_alphanumeric() { c.to_ascii_lowercase() } else { '_' })
        .collect::<String>()
        .split('_')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("_");
    // Hard cap: timestamp is 15 chars + _ = 16, total filename max ~80
    if slug.len() > 50 { slug[..50].to_string() } else { slug }
}

#[zkperf_macros::witness_boundary(complexity = "K1:vector", max_n = 10000, max_ms = 1010)]
pub fn extract_ngrams(text: &str, n: usize, top: usize) -> Vec<(String, usize)> {
    let words: Vec<&str> = text.split_whitespace().collect();
    let mut counts: HashMap<String, usize> = HashMap::new();
    for i in 0..words.len().saturating_sub(n - 1) {
        let ngram = words[i..i + n].join(" ").to_lowercase();
        *counts.entry(ngram).or_insert(0) += 1;
    }
    let mut ngrams: Vec<(String, usize)> = counts.into_iter().collect();
    ngrams.sort_by(|a, b| b.1.cmp(&a.1));
    ngrams.truncate(top);
    ngrams
}

#[zkperf_macros::witness_boundary(complexity = "K1:vector", max_n = 10000, max_ms = 1010)]
pub fn auto_tag(content: &str) -> Vec<String> {
    let mut tags = Vec::new();
    let lower = content.to_lowercase();

    if lower.contains("<html") || lower.contains("<!doctype") {
        tags.push("html".to_string());
        if let Some(title) = extract_html_title(content) {
            tags.push(format!("title:{}", title));
        }
        for meta in extract_html_meta(content) {
            tags.push(format!("meta:{}", meta));
        }
    }

    if lower.contains("rust") || lower.contains("cargo") { tags.push("rust".to_string()); }
    if lower.contains("python") || lower.contains("pip") { tags.push("python".to_string()); }
    if lower.contains("javascript") || lower.contains("npm") { tags.push("javascript".to_string()); }
    if lower.contains("fn ") || lower.contains("impl ") { tags.push("code".to_string()); }
    if lower.contains("error") || lower.contains("exception") { tags.push("error".to_string()); }
    if lower.contains("todo") || lower.contains("fixme") { tags.push("todo".to_string()); }
    if lower.contains("http") || lower.contains("api") { tags.push("api".to_string()); }
    if lower.contains("docker") || lower.contains("kubernetes") { tags.push("devops".to_string()); }
    if lower.contains("http://") || lower.contains("https://") { tags.push("url".to_string()); }

    if lower.contains("github.com") || lower.contains("gitlab.com") || lower.contains("git@") {
        tags.push("git".to_string());
        for line in content.lines() {
            if let Some(repo) = extract_repo_name(line) {
                tags.push(format!("repo:{}", repo));
            }
        }
    }

    tags
}

#[zkperf_macros::witness_boundary(complexity = "K0:scalar", max_n = 1, max_ms = 150)]
pub fn extract_html_title(html: &str) -> Option<String> {
    let start = html.find("<title>")?;
    let end = html[start..].find("</title>")?;
    Some(html[start + 7..start + end].trim().to_string())
}

#[zkperf_macros::witness_boundary(complexity = "K1:vector", max_n = 10000, max_ms = 1010)]
pub fn extract_html_meta(html: &str) -> Vec<String> {
    let mut metas = Vec::new();
    for line in html.lines() {
        if line.contains("<meta") && line.contains("name=") && line.contains("content=") {
            if let Some(name) = extract_attr(line, "name") {
                if let Some(content) = extract_attr(line, "content") {
                    metas.push(format!("{}:{}", name, content));
                }
            }
        }
    }
    metas
}

#[zkperf_macros::witness_boundary(complexity = "K0:scalar", max_n = 1, max_ms = 150)]
fn extract_attr(line: &str, attr: &str) -> Option<String> {
    let pattern = format!("{}=\"", attr);
    let start = line.find(&pattern)? + pattern.len();
    let end = line[start..].find('"')?;
    Some(line[start..start + end].to_string())
}

#[zkperf_macros::witness_boundary(complexity = "K0:scalar", max_n = 1, max_ms = 240)]
fn extract_repo_name(line: &str) -> Option<String> {
    if let Some(start) = line.find("github.com/").or_else(|| line.find("gitlab.com/")) {
        let after = &line[start..];
        let parts: Vec<&str> = after.split('/').collect();
        if parts.len() >= 3 {
            return Some(format!("{}/{}", parts[1], parts[2].split_whitespace().next()?));
        }
    }
    if let Some(start) = line.find("git@") {
        let after = &line[start..];
        if let Some(colon_pos) = after.find(':') {
            let repo_part = &after[colon_pos + 1..];
            let repo = repo_part.split_whitespace().next()?.trim_end_matches(".git");
            return Some(repo.to_string());
        }
    }
    None
}

#[zkperf_macros::witness_boundary(complexity = "K0:scalar", max_n = 1, max_ms = 250)]
pub fn auto_describe(content: &str) -> String {
    let lines: Vec<&str> = content.lines().take(3).collect();
    let preview: String = lines.join(" ")
        .split_whitespace()
        .filter(|w| !w.starts_with("http://") && !w.starts_with("https://"))
        .collect::<Vec<_>>()
        .join(" ")
        .chars().take(80).collect();
    if preview.len() < content.len() { format!("{}...", preview) } else { preview }
}
