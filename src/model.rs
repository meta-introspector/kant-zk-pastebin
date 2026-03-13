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
}
