// Summary - Deterministic NLP-based auto-population of title, description, and body
// No external ML services, pure Rust, no syscalls

use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct Summary {
    pub title: String,
    pub description: String,
    pub body: String,
}

pub fn summarize_upload(name: &str, content: &str) -> Option<Summary> {
    let chunks = chunk_text(content, 350);
    if chunks.len() == 1 {
        summarize_chunk(name, &chunks[0])
    } else {
        let combined = chunks.join("\n---\n");
        summarize_chunk(name, &combined)
    }
}

fn chunk_text(text: &str, target_tokens: usize) -> Vec<String> {
    let target_chars = target_tokens.saturating_mul(4).max(200);
    recursive_split(text, target_chars)
}

fn recursive_split(text: &str, max_chars: usize) -> Vec<String> {
    if text.len() <= max_chars {
        return vec![text.to_string()];
    }

    let parts: Vec<&str> = text.split("\n\n").collect();
    if parts.len() > 1 {
        let mut chunks = Vec::new();
        let mut current = String::new();
        for part in parts {
            if !current.is_empty() {
                current.push_str("\n\n");
            }
            current.push_str(part);
            if current.len() > max_chars && !current.trim().is_empty() {
                chunks.extend(recursive_split(&current, max_chars));
                current.clear();
            }
        }
        if !current.trim().is_empty() {
            chunks.extend(recursive_split(&current, max_chars));
        }
        if !chunks.is_empty() {
            return chunks;
        }
    }

    let parts: Vec<&str> = text.split('\n').collect();
    if parts.len() > 1 {
        let mut chunks = Vec::new();
        let mut current = String::new();
        for part in parts {
            if !current.is_empty() {
                current.push('\n');
            }
            current.push_str(part);
            if current.len() > max_chars && !current.trim().is_empty() {
                chunks.extend(recursive_split(&current, max_chars));
                current.clear();
            }
        }
        if !current.trim().is_empty() {
            chunks.extend(recursive_split(&current, max_chars));
        }
        if !chunks.is_empty() {
            return chunks;
        }
    }

    let parts: Vec<&str> = text.split(". ").collect();
    if parts.len() > 1 {
        let mut chunks = Vec::new();
        let mut current = String::new();
        for part in parts {
            if !current.is_empty() {
                current.push_str(". ");
            }
            current.push_str(part);
            if current.len() > max_chars && !current.trim().is_empty() {
                chunks.extend(recursive_split(&current, max_chars));
                current.clear();
            }
        }
        if !current.trim().is_empty() {
            chunks.extend(recursive_split(&current, max_chars));
        }
        if !chunks.is_empty() {
            return chunks;
        }
    }

    let mut chunks = Vec::new();
    let mut current = String::new();
    for word in text.split_whitespace() {
        if !current.is_empty() {
            current.push(' ');
        }
        current.push_str(word);
        if current.len() > max_chars && !current.trim().is_empty() {
            chunks.push(current.trim().to_string());
            current.clear();
        }
    }
    if !current.trim().is_empty() {
        chunks.push(current.trim().to_string());
    }
    if !chunks.is_empty() {
        return chunks;
    }

    vec![text.to_string()]
}

fn summarize_chunk(name: &str, chunk: &str) -> Option<Summary> {
    let lines: Vec<&str> = chunk.lines().collect();
    let word_count = chunk.split_whitespace().count();

    let title = generate_title(name, &lines, chunk);
    let description = generate_description(&lines, chunk);
    let body = generate_body(chunk);

    Some(Summary {
        title,
        description,
        body,
    })
}

fn generate_title(name: &str, lines: &[&str], full: &str) -> String {
    let base = if name.is_empty() || name == "upload" {
        extract_first_meaningful_line(lines)
    } else {
        clean_filename(name)
    };

    if base.len() > 80 {
        base.chars().take(77).collect::<String>() + "..."
    } else if base.len() < 3 {
        let keywords = top_keywords(full, 3);
        if keywords.is_empty() {
            "Untitled Paste".to_string()
        } else {
            keywords
                .iter()
                .map(|w| capitalize(w))
                .collect::<Vec<_>>()
                .join(" ")
        }
    } else {
        base
    }
}

fn generate_description(lines: &[&str], full: &str) -> String {
    let mut candidates = Vec::new();
    for line in lines {
        let trimmed = line.trim();
        if trimmed.len() > 20
            && trimmed.len() < 200
            && !trimmed.starts_with("#")
            && !trimmed.starts_with("//")
        {
            if !trimmed.contains("http") || trimmed.contains("://") {
                candidates.push(trimmed);
            }
        }
        if candidates.len() >= 5 {
            break;
        }
    }

    if candidates.is_empty() {
        return format!("Document with {} words", full.split_whitespace().count());
    }

    let mut desc = candidates[0].to_string();
    if candidates.len() > 1 {
        desc.push_str(". ");
        desc.push_str(candidates[1]);
    }
    if desc.len() > 180 {
        desc.truncate(177);
        desc.push_str("...");
    }
    desc
}

fn generate_body(full: &str) -> String {
    let words: Vec<&str> = full.split_whitespace().take(400).collect();
    let mut body = words.join(" ");
    let total_words = full.split_whitespace().count();
    if total_words > 400 {
        body.push_str(" ... [truncated for context window]");
    }
    body
}

fn extract_first_meaningful_line(lines: &[&str]) -> String {
    for line in lines {
        let trimmed = line.trim();
        if trimmed.len() > 10
            && !trimmed.starts_with('#')
            && !trimmed.starts_with("//")
            && !trimmed.starts_with("/*")
        {
            return clean_line(trimmed);
        }
    }
    "Untitled Paste".to_string()
}

fn clean_filename(name: &str) -> String {
    let stem = name.rsplit('.').next().unwrap_or(name);
    stem.replace('_', " ")
        .split_whitespace()
        .map(capitalize)
        .collect::<Vec<_>>()
        .join(" ")
}

fn clean_line(line: &str) -> String {
    line.trim_start_matches(|c: char| !c.is_alphanumeric())
        .trim_end_matches(|c: char| !c.is_alphanumeric() && c != '.')
        .to_string()
}

fn capitalize(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

fn top_keywords(text: &str, n: usize) -> Vec<String> {
    let mut counts: HashMap<String, usize> = HashMap::new();
    for word in text.split_whitespace() {
        let w = word
            .to_lowercase()
            .trim_matches(|c: char| !c.is_alphanumeric())
            .to_string();
        if w.len() > 3 && !is_stopword(&w) {
            *counts.entry(w).or_insert(0) += 1;
        }
    }
    let mut items: Vec<_> = counts.into_iter().collect();
    items.sort_by(|a, b| b.1.cmp(&a.1));
    items.truncate(n);
    items.into_iter().map(|(w, _)| w).collect()
}

fn is_stopword(w: &str) -> bool {
    matches!(
        w,
        "the"
            | "and"
            | "for"
            | "with"
            | "this"
            | "that"
            | "from"
            | "have"
            | "been"
            | "were"
            | "was"
            | "are"
            | "but"
            | "not"
            | "you"
            | "all"
            | "can"
            | "her"
            | "his"
            | "him"
            | "our"
            | "out"
            | "who"
            | "what"
            | "when"
            | "where"
            | "why"
            | "how"
            | "each"
            | "which"
            | "their"
            | "than"
            | "them"
            | "then"
            | "some"
            | "would"
            | "make"
            | "like"
            | "into"
            | "time"
            | "very"
            | "just"
            | "over"
            | "such"
            | "after"
            | "also"
            | "only"
            | "more"
            | "most"
            | "other"
            | "should"
            | "could"
            | "there"
    )
}
