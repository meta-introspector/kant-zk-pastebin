// Summary - AI-powered auto-population of title, description, and body via Ollama
use std::env;

#[derive(Debug, Clone)]
pub struct Summary {
    pub title: String,
    pub description: String,
    pub body: String,
}

pub async fn summarize_upload(name: &str, content: &str) -> Option<Summary> {
    let ollama_url =
        env::var("OLLAMA_URL").unwrap_or_else(|_| "http://localhost:11434".to_string());
    let model = env::var("OLLAMA_MODEL").unwrap_or_else(|_| "llama3".to_string());

    let chunks = chunk_text(content, 250);
    if chunks.len() == 1 {
        summarize_chunk(&ollama_url, &model, name, &chunks[0]).await
    } else {
        let mut combined = String::new();
        for (i, chunk) in chunks.iter().enumerate() {
            if let Some(s) = summarize_chunk_brief(&ollama_url, &model, name, i + 1, chunk).await {
                combined.push_str(&format!("[Part {}]: {}\n", i + 1, s));
            } else {
                combined.push_str(&format!("[Part {}]: {}\n", i + 1, truncate(chunk, 300)));
            }
        }
        summarize_combined(&ollama_url, &model, name, &combined).await
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

async fn summarize_chunk(ollama_url: &str, model: &str, name: &str, chunk: &str) -> Option<Summary> {
    let prompt = format!(
        "You are a summarization assistant. Summarize the following file named '{}' for use in an AI knowledge base.\n\nContent:\n{}\n\nRules:\n- Title: max 80 chars, descriptive\n- Description: 1-2 sentences only\n- Body: concise summary targeting ~400 tokens (max 1500 chars)\n\nReturn ONLY valid JSON with no markdown fences and no extra text:\n{{\"title\":\"...\",\"description\":\"...\",\"body\":\"...\"}}\n",
        name, chunk
    );
    call_ollama_summary(ollama_url, model, &prompt, 1200).await
}

async fn summarize_chunk_brief(
    ollama_url: &str,
    model: &str,
    name: &str,
    idx: usize,
    chunk: &str,
) -> Option<String> {
    let prompt = format!(
        "Summarize this chunk (part {} of file '{}') in 1-2 sentences only. No JSON, no extra text:\n\n{}\n",
        idx, name, chunk
    );
    call_ollama_text(ollama_url, model, &prompt, 120).await
}

async fn summarize_combined(
    ollama_url: &str,
    model: &str,
    name: &str,
    combined: &str,
) -> Option<Summary> {
    let prompt = format!(
        "You are a summarization assistant. These are chunk summaries from file '{}'.\n\n{}\n\nRules:\n- Title: max 80 chars, descriptive\n- Description: 1-2 sentences only\n- Body: concise combined summary targeting ~400 tokens (max 1500 chars)\n\nReturn ONLY valid JSON with no markdown fences and no extra text:\n{{\"title\":\"...\",\"description\":\"...\",\"body\":\"...\"}}\n",
        name, combined
    );
    call_ollama_summary(ollama_url, model, &prompt, 1200).await
}

async fn call_ollama_text(
    ollama_url: &str,
    model: &str,
    prompt: &str,
    max_tokens: usize,
) -> Option<String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .ok()?;

    let url = format!("{}/api/generate", ollama_url);
    let body = serde_json::json!({
        "model": model,
        "prompt": prompt,
        "stream": false,
        "options": {"num_predict": max_tokens, "temperature": 0.3}
    });

    let resp = client.post(&url).json(&body).send().await.ok()?;
    let json: serde_json::Value = resp.json().await.ok()?;
    json.get("response")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
}

async fn call_ollama_summary(
    ollama_url: &str,
    model: &str,
    prompt: &str,
    max_tokens: usize,
) -> Option<Summary> {
    let text = call_ollama_text(ollama_url, model, prompt, max_tokens).await?;
    parse_summary(&text)
}

fn parse_summary(text: &str) -> Option<Summary> {
    let cleaned = text
        .trim()
        .trim_start_matches("```json")
        .trim_start_matches("```")
        .trim_end_matches("```")
        .trim();
    let json: serde_json::Value = serde_json::from_str(cleaned).ok()?;
    Some(Summary {
        title: json.get("title")?.as_str()?.trim().to_string(),
        description: json.get("description")?.as_str()?.trim().to_string(),
        body: json.get("body")?.as_str()?.trim().to_string(),
    })
}

fn truncate(s: &str, max_chars: usize) -> String {
    if s.len() <= max_chars {
        s.to_string()
    } else {
        let mut t = s[..max_chars].to_string();
        t.push_str("...");
        t
    }
}
