// paste.rs — data structures for the Kant pastebin server
use serde::{Deserialize, Serialize};

// === Existing models ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paste {
    pub id: String,
    pub content: String,
    pub created: u64,
    pub expires: Option<u64>,
    pub tags: Vec<String>,
    pub owner: Option<String>,
    pub title: Option<String>,
    pub reply_to: Option<String>,
    pub cid: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Response {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Paste>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub witness: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ipfs_cid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub permalink: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uucp_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PasteIndex {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub keywords: Vec<String>,
    pub cid: String,
    pub witness: String,
    pub timestamp: String,
    pub filename: String,
    pub ngrams: Vec<String>,
    pub ipfs_cid: Option<String>,
    pub reply_to: Option<String>,
    pub size: usize,
    pub uucp_path: String,
    pub root: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SplitProfile {
    pub name: String,
    pub label: String,
    pub context_window: usize,
    pub unit: SplitUnit,
    pub chunk_size: usize,
    pub overlap: usize,
    pub max_output_tokens: usize,
    pub split_mode: SplitMode,
    pub builtin: bool,
    pub description: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SplitUnit {
    Byte,
    Word,
    Token,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SplitMode {
    Line,
    Word,
    Exact,
}

impl SplitProfile {
    /// Built-in platform presets based on current API limits.
    pub fn presets() -> Vec<Self> {
        vec![
            Self {
                name: "openai".to_string(),
                label: "OpenAI GPT-4o".to_string(),
                context_window: 128_000,
                unit: SplitUnit::Token,
                chunk_size: 8_000,
                overlap: 500,
                max_output_tokens: 4_096,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("OpenAI GPT-4o with 128k context window".to_string()),
            },
            Self {
                name: "grok".to_string(),
                label: "Grok 3".to_string(),
                context_window: 131_072,
                unit: SplitUnit::Token,
                chunk_size: 8_000,
                overlap: 500,
                max_output_tokens: 8_192,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Grok 3 with 131k context window".to_string()),
            },
            Self {
                name: "perplexity".to_string(),
                label: "Perplexity Pro".to_string(),
                context_window: 127_000,
                unit: SplitUnit::Token,
                chunk_size: 8_000,
                overlap: 500,
                max_output_tokens: 8_192,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Perplexity Pro with 127k context window".to_string()),
            },
            Self {
                name: "notebooklm".to_string(),
                label: "NotebookLM".to_string(),
                context_window: 1_000_000,
                unit: SplitUnit::Token,
                chunk_size: 32_000,
                overlap: 1_000,
                max_output_tokens: 10_000,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("NotebookLM with 1M context window".to_string()),
            },
            Self {
                name: "custom".to_string(),
                label: "Custom".to_string(),
                context_window: 4_096,
                unit: SplitUnit::Token,
                chunk_size: 1_000,
                overlap: 100,
                max_output_tokens: 1_000,
                split_mode: SplitMode::Word,
                builtin: true,
                description: Some("Custom profile".to_string()),
            },
        ]
    }

    /// Find a built-in preset by name
    pub fn find_preset(name: &str) -> Option<Self> {
        Self::presets().into_iter().find(|p| p.name == name)
    }
}

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

// === New: Avatar / Identity models ===

/// A user avatar (stored as base64 or IPFS CID)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Avatar {
    pub id: String,
    pub owner: String,
    pub data_url: Option<String>, // base64 data URL for local storage
    pub ipfs_cid: Option<String>, // IPFS CID for p2p sharing
    pub mime_type: String,
    pub size_bytes: usize,
    pub created: u64,
}

/// A user identity / profile
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Identity {
    pub id: String,
    pub name: String,
    pub display_name: Option<String>,
    pub avatar_id: Option<String>,
    pub bio: Option<String>,
    pub relays: Vec<String>, // known relays for mesh networking
    pub created: u64,
    pub updated: u64,
}

/// A post in a threaded view.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadPost {
    pub id: String,
    pub title: String,
    pub depth: usize,
    pub reply_to: Option<String>,
    pub description: Option<String>,
    pub content_excerpt: String,
    pub created: u64,
    pub timestamp: String,
    pub size: usize,
}

/// A peer in the mesh network
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeshPeer {
    pub id: String,
    pub identity: Identity,
    pub relay: String,
    pub last_seen: u64,
    pub status: MeshPeerStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MeshPeerStatus {
    Online,
    Offline,
    Unknown,
}

/// A mesh network message (relay-to-relay)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeshMessage {
    pub id: String,
    pub from: String,
    pub to: Option<String>, // None = broadcast
    pub kind: MeshMessageKind,
    pub payload: String,
    pub timestamp: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MeshMessageKind {
    IdentityAnnounce,
    RoomSync,
    PasteSync,
    AvatarSync,
    RelayPing,
}
