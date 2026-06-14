// Model - Data structures for kant-pastebin
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Deserialize, ToSchema)]
pub struct Paste {
    pub content: Option<String>,
    pub cid: Option<String>,
    pub title: Option<String>,
    pub keywords: Option<Vec<String>>,
    pub reply_to: Option<String>,
}

#[derive(Serialize, ToSchema)]
pub struct Response {
    pub id: String,
    pub cid: String,
    pub ipfs_cid: Option<String>,
    pub witness: String,
    pub url: String,
    pub permalink: String,
    pub uucp_path: String,
    pub reply_to: Option<String>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct PasteIndex {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub keywords: Vec<String>,
    pub cid: String,
    pub witness: String,
    pub timestamp: String,
    pub filename: String,
    pub ngrams: Vec<(String, usize)>,
    pub ipfs_cid: Option<String>,
    pub reply_to: Option<String>,
    pub size: usize,
    pub uucp_path: String,
    pub root: Option<String>,
}

// ─── Split Profiles ───────────────────────────────────────────────────

/// How to split at chunk boundaries.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SplitMode {
    /// Break on newline boundaries
    Line,
    /// Break on word boundaries (default)
    Word,
    /// Break at exact byte offset
    Exact,
}

/// A split profile defines how content is chunked for a specific LLM platform.
///
/// Each platform has different context window sizes and output limits.
/// The profile encodes these as chunk_size (input) and overlap (for
/// maintaining context across chunk boundaries).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SplitProfile {
    /// Unique profile name (e.g. "openai", "grok", "perplexity", "custom")
    pub name: String,
    /// Display label (e.g. "OpenAI GPT-4o")
    pub label: String,
    /// Maximum input context window in bytes
    pub context_window: usize,
    /// Chunk size in bytes (how much to send per request)
    pub chunk_size: usize,
    /// Overlap in bytes between consecutive chunks (for context continuity)
    pub overlap: usize,
    /// Maximum output tokens the platform can generate per request
    pub max_output_tokens: usize,
    /// Split boundary mode
    pub split_mode: SplitMode,
    /// Whether this is a built-in preset (cannot be deleted)
    pub builtin: bool,
    /// Optional description
    pub description: Option<String>,
}

impl SplitProfile {
    /// Built-in platform presets based on current API limits.
    pub fn presets() -> Vec<Self> {
        vec![
            Self {
                name: "openai".into(),
                label: "OpenAI GPT-4o".into(),
                context_window: 128_000,
                // Leave room for system prompt + output (~8K tokens ≈ 32KB)
                chunk_size: 100_000,
                overlap: 2_000,
                max_output_tokens: 16_384,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("GPT-4o: 128K context, ~16K output tokens".into()),
            },
            Self {
                name: "grok".into(),
                label: "Grok 3".into(),
                context_window: 131_072,
                chunk_size: 110_000,
                overlap: 2_000,
                max_output_tokens: 8_192,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Grok 3: 131K context, ~8K output tokens".into()),
            },
            Self {
                name: "perplexity".into(),
                label: "Perplexity".into(),
                context_window: 128_000,
                chunk_size: 100_000,
                overlap: 1_500,
                max_output_tokens: 4_096,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Perplexity: 128K context, ~4K output tokens".into()),
            },
            Self {
                name: "claude".into(),
                label: "Claude 4 Sonnet".into(),
                context_window: 200_000,
                chunk_size: 160_000,
                overlap: 3_000,
                max_output_tokens: 16_384,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Claude 4 Sonnet: 200K context, ~16K output tokens".into()),
            },
            Self {
                name: "gemini".into(),
                label: "Gemini 2.5 Pro".into(),
                context_window: 1_000_000,
                chunk_size: 800_000,
                overlap: 4_000,
                max_output_tokens: 8_192,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Gemini 2.5 Pro: 1M context, ~8K output tokens".into()),
            },
            Self {
                name: "local".into(),
                label: "Local (8K)".into(),
                context_window: 8_192,
                chunk_size: 6_000,
                overlap: 500,
                max_output_tokens: 2_048,
                split_mode: SplitMode::Line,
                builtin: true,
                description: Some("Local LLM: 8K context, small chunks".into()),
            },
        ]
    }

    /// Find a preset by name.
    pub fn find_preset(name: &str) -> Option<Self> {
        Self::presets().into_iter().find(|p| p.name == name)
    }
}

/// Request body for creating/updating a custom split profile.
#[derive(Debug, Deserialize)]
pub struct SplitProfileRequest {
    pub name: String,
    pub label: Option<String>,
    pub chunk_size: usize,
    pub overlap: Option<usize>,
    pub context_window: Option<usize>,
    pub max_output_tokens: Option<usize>,
    pub split_mode: Option<SplitMode>,
    pub description: Option<String>,
}
