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

#[derive(Serialize, Deserialize, Clone, Default)]
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
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SplitUnit {
    /// Byte-based chunking.
    Byte,
    /// Word-count chunking.
    Word,
    /// Token-estimate chunking.
    Token,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
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
    /// Maximum input context window in the profile unit
    pub context_window: usize,
    /// Chunk size unit: bytes, words, or estimated tokens.
    pub unit: SplitUnit,
    /// Chunk size in `unit`.
    pub chunk_size: usize,
    /// Overlap in `unit` between consecutive chunks (for context continuity)
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
                name: "notebooklm".into(),
                label: "NotebookLM".into(),
                context_window: 666_667,
                chunk_size: 500_000,
                unit: SplitUnit::Word,
                overlap: 20_000,
                max_output_tokens: 50_000,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("NotebookLM: up to about 500K words per input".into()),
            },
            Self {
                name: "openai".into(),
                label: "OpenAI GPT-4o / GPT-4.1".into(),
                context_window: 1_000_000,
                chunk_size: 750_000,
                unit: SplitUnit::Word,
                overlap: 30_000,
                max_output_tokens: 16_384,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some(
                    "OpenAI large-context models: about 750K words, with output headroom".into(),
                ),
            },
            Self {
                name: "gemini".into(),
                label: "Gemini 1.5 / 2.0".into(),
                context_window: 2_000_000,
                chunk_size: 1_500_000,
                unit: SplitUnit::Word,
                overlap: 50_000,
                max_output_tokens: 8_192,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some(
                    "Gemini large-context models: about 1.5M words, with output headroom".into(),
                ),
            },
            Self {
                name: "claude".into(),
                label: "Claude 3.5 Sonnet".into(),
                context_window: 200_000,
                chunk_size: 150_000,
                unit: SplitUnit::Word,
                overlap: 8_000,
                max_output_tokens: 16_384,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some(
                    "Claude 3.5 Sonnet: about 150K words, with overlap for continuity".into(),
                ),
            },
            Self {
                name: "llama".into(),
                label: "Llama 3 128K".into(),
                context_window: 128_000,
                chunk_size: 96_000,
                unit: SplitUnit::Word,
                overlap: 4_000,
                max_output_tokens: 4_096,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Llama 3 128K: about 96K words".into()),
            },
            Self {
                name: "openai_16k".into(),
                label: "OpenAI 16K".into(),
                context_window: 16_000,
                chunk_size: 12_000,
                unit: SplitUnit::Word,
                overlap: 1_000,
                max_output_tokens: 4_096,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("OpenAI 16K context: about 12K words".into()),
            },
            Self {
                name: "grok".into(),
                label: "Grok 3".into(),
                context_window: 131_072,
                chunk_size: 98_000,
                unit: SplitUnit::Word,
                overlap: 4_000,
                max_output_tokens: 8_192,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Grok 3: about 98K words".into()),
            },
            Self {
                name: "perplexity".into(),
                label: "Perplexity".into(),
                context_window: 128_000,
                chunk_size: 96_000,
                unit: SplitUnit::Word,
                overlap: 3_000,
                max_output_tokens: 4_096,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Perplexity: about 96K words".into()),
            },
            Self {
                name: "local".into(),
                label: "Local (8K)".into(),
                context_window: 8_192,
                chunk_size: 6_144,
                unit: SplitUnit::Token,
                overlap: 512,
                max_output_tokens: 2_048,
                split_mode: SplitMode::Line,
                builtin: true,
                description: Some("Local LLM: 8K tokens, about 6K words".into()),
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
    pub unit: Option<SplitUnit>,
    pub overlap: Option<usize>,
    pub context_window: Option<usize>,
    pub max_output_tokens: Option<usize>,
    pub split_mode: Option<SplitMode>,
    pub description: Option<String>,
}
