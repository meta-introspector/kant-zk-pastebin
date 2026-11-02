//! Postgres connection pool and query helpers for pastebin.
//!
//! Reads from index.jsonl once at startup, then serves queries from postgres.
//! All paste metadata, tags, CIDs, and ngrams live in postgres now.

use crate::handlers::SearchResult;
use deadpool_postgres::Pool;
use std::sync::Arc;

/// App-wide postgres pool, shared via actix-web data.
pub struct DbState {
    pub pool: Pool,
}

impl DbState {
    pub fn new(pool: Pool) -> Self {
        Self { pool }
    }
}

/// Query pastes by full-text search (tsvector).
pub async fn search_postgres(pool: &Pool, query: &str, limit: usize) -> Vec<SearchResult> {
    let client = match pool.get().await {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    // Plainto_tsquery for OR-style matching across words
    let ts_query = query.split_whitespace().collect::<Vec<_>>().join(" | ");
    let ts_query = if ts_query.is_empty() {
        "''".to_string()
    } else {
        format!("plainto_tsquery('english', '{}')", ts_query.replace("'", "''"))
    };

    let rows = match client
        .query(
            &format!(
                r#"
                SELECT p.id, p.title, p.description, p.keywords_json,
                       p.ipfs_cid, p.cid_v0, p.cid_v1, p.witness,
                       p.timestamp, p.size, p.da51_addr,
                       p.orbifold_x, p.orbifold_y, p.orbifold_z,
                       p.reply_to, p.root_id,
                       ts_rank_cd(p.search_vector, to_tsquery($1)) AS rank
                FROM pastes p
                WHERE p.search_vector @@ to_tsquery($1)
                ORDER BY rank DESC
                LIMIT $2
            "#,
            ts_query
        ),
        &[&ts_query, &(limit as i64)]
    ).await {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };

    let mut results = Vec::new();
    for row in rows {
        results.push(SearchResult {
            id: row.get::<_, Option<String>>(0).unwrap_or_default(),
            title: row.get::<_, Option<String>>(1).unwrap_or_default(),
            description: row.get::<_, Option<String>>(2).unwrap_or_default(),
            keywords: row.get::<_, Option<Vec<String>>>(3).unwrap_or_default(),
            match_type: "postgres-fts".to_string(),
            excerpt: String::new(),
            url: format!("/paste/{}", row.get::<_, Option<String>>(0).unwrap_or_default()),
            timestamp: row.get::<_, Option<String>>(9).unwrap_or_default(),
            size: row.get::<_, i64>(10).unwrap_or(0) as usize,
            source: Some("postgres".to_string()),
            file_path: None,
        });
    }

    results
}

/// Query pastes by CID.
pub async fn search_cid(pool: &Pool, cid: &str) -> Option<SearchResult> {
    let client = pool.get().await.ok()?;

    let row = client
        .query_opt(
            "SELECT id, title, description, keywords_json, ipfs_cid, cid_v0, cid_v1,
                      timestamp, size, uucp_path
             FROM pastes
             WHERE cid_v0 = $1 OR cid_v1 = $1 OR ipfs_cid = $1
             LIMIT 1",
            &[&cid],
        )
        .await.ok()??;

    Some(SearchResult {
        id: row.get::<_, Option<String>>(0).unwrap_or_default(),
        title: row.get::<_, Option<String>>(1).unwrap_or_default(),
        description: row.get::<_, Option<String>>(2).unwrap_or_default(),
        keywords: row.get::<_, Option<Vec<String>>>(3).unwrap_or_default(),
        match_type: "cid".to_string(),
        excerpt: String::new(),
        url: format!("/paste/{}", row.get::<_, Option<String>>(0).unwrap_or_default()),
        timestamp: row.get::<_, Option<String>>(7).unwrap_or_default(),
        size: row.get::<_, i64>(8).unwrap_or(0) as usize,
        source: Some("postgres".to_string()),
        file_path: Some(row.get::<_, Option<String>>(9).unwrap_or_default().unwrap_or_default()),
    })
}

/// List all tags with counts.
pub async fn list_tags(pool: &Pool, limit: usize) -> Vec<(String, i64)> {
    let client = pool.get().await.ok()?;

    let rows = client
        .query(
            "SELECT tag, count(*) FROM paste_tags GROUP BY tag ORDER BY count DESC LIMIT $1",
            &[&(limit as i64)],
        )
        .await.ok()?;

    rows.iter().map(|r| (r.get::<_, String>(0), r.get::<_, i64>(1))).collect()
}

/// Insert a new paste into postgres.
pub async fn insert_paste(
    pool: &Pool,
    id: &str,
    title: &str,
    description: &str,
    content: &str,
    cid: Option<&str>,
    ipfs_cid: Option<&str>,
    witness: Option<&str>,
    timestamp: &str,
    size: i64,
    uucp_path: Option<&str>,
) -> anyhow::Result<()> {
    let client = pool.get().await?;

    let cid_v0 = cid.filter(|c| c.starts_with("Qm"));
    let cid_v1 = cid.filter(|c| c.starts_with("baf"));

    client
        .execute(
            "INSERT INTO pastes (id, title, description, content, size, timestamp, uucp_path,
                                  cid_v0, cid_v1, witness, ipfs_cid, indexed_at, ipfs_pinned)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, now(), $12)
             ON CONFLICT (id) DO UPDATE SET
                title = EXCLUDED.title,
                description = EXCLUDED.description,
                content = EXCLUDED.content,
                indexed_at = now()",
            &[
                &id.to_string(),
                &title.to_string(),
                &description.to_string(),
                &content.to_string(),
                &size,
                &timestamp.to_string(),
                &uucp_path.map(|s| s.to_string()),
                &cid_v0.map(|s| s.to_string()),
                &cid_v1.map(|s| s.to_string()),
                &witness.map(|s| s.to_string()),
                &ipfs_cid.map(|s| s.to_string()),
                &false,
            ],
        )
        .await?;

    Ok(())
}
