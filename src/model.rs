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

/// A conformal arrow between two paste sections in the orbifold.
/// Thread = directed path in Z/71 × Z/59 × Z/47.
/// Geometry search = geodesic from root coords.
#[derive(Serialize, Deserialize, Clone)]
pub struct ConformalArrow {
    /// Source paste id
    pub source: String,
    /// Target paste id (reply)
    pub target: String,
    /// Orbifold coords of source: (l mod 71, m mod 59, n mod 47)
    pub source_coords: (u64, u64, u64),
    /// Orbifold coords of target
    pub target_coords: (u64, u64, u64),
    /// Orbifold displacement (target - source mod each prime)
    pub delta: (u64, u64, u64),
    /// Coboundary: encoding change along the arrow
    pub coboundary: String,
}

impl ConformalArrow {
    pub fn new(source: &PasteIndex, target: &PasteIndex) -> Self {
        use crate::dasl::orbifold_coords;
        let sc = orbifold_coords(source.cid.as_bytes());
        let tc = orbifold_coords(target.cid.as_bytes());
        let delta = (
            (tc.0 + 71 - sc.0) % 71,
            (tc.1 + 59 - sc.1) % 59,
            (tc.2 + 47 - sc.2) % 47,
        );
        Self {
            source: source.id.clone(),
            target: target.id.clone(),
            source_coords: sc,
            target_coords: tc,
            delta,
            coboundary: format!("δ: ({},{},{}) → ({},{},{})", sc.0, sc.1, sc.2, tc.0, tc.1, tc.2),
        }
    }
}

/// A thread as a sequence of conformal arrows (path in the orbifold)
#[derive(Serialize, Deserialize, Clone)]
pub struct Thread {
    pub root_id: String,
    pub root_coords: (u64, u64, u64),
    pub arrows: Vec<ConformalArrow>,
    pub pastes: Vec<PasteIndex>,
}
