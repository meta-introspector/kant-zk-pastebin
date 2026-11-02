//! Two-way sync with the Cloudflare Durable Object board.
//!
//! Postgres is the source of truth for a running fabric; the Durable Object is
//! the copy that survives this host and that a Worker or another machine can
//! read. Both directions are exercised by the test suite:
//!
//! * **push** sends every local event the DO has not seen (`append`), in order.
//! * **pull** reads from the cursor the DO gave us and applies what is new
//!   locally. Starting from cursor 0 with an empty database reconstructs the
//!   whole board, which is the property `sync_reconstructs_from_the_object`
//!   checks end to end.
//!
//! Lines pulled from the DO go through the same `verify_line` as lines from
//! the relay: a Worker that returns a doctored line is refused, not applied.

use std::time::Duration;

use serde_json::{json, Value};

use crate::fabric::http;
use crate::fabric::protocol;
use crate::fabric::store::{self, Store};

pub struct DoSync {
    pub base: String,
}

pub struct PushResult {
    pub pushed: usize,
    pub cursor: i64,
}

pub struct PullResult {
    pub applied: usize,
    pub duplicates: usize,
    pub rejected: Vec<String>,
    pub cursor: i64,
}

impl DoSync {
    pub fn new(base: &str) -> DoSync {
        DoSync { base: base.trim_end_matches('/').to_string() }
    }

    pub fn enabled(&self) -> bool {
        !self.base.is_empty()
    }

    pub fn health(&self) -> Result<Value, String> {
        let r = http::request(
            "GET",
            &format!("{}/health", self.base),
            None,
            Duration::from_secs(5),
        )?;
        r.json()
    }

    /// Push local events the board has not acknowledged. The high-water mark is
    /// the local sequence number, so a restart resumes rather than replays.
    pub fn push(&self, store: &Store) -> Result<PushResult, String> {
        if !self.enabled() {
            return Ok(PushResult { pushed: 0, cursor: 0 });
        }
        let since: i64 = store
            .meta("do_pushed_seq")?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let batch = store.events_since(since, 500)?;
        if batch.is_empty() {
            return Ok(PushResult { pushed: 0, cursor: since });
        }
        let lines: Vec<Value> = batch.iter().map(|e| e["line"].clone()).collect();
        let body = serde_json::to_vec(&json!({"lines": lines})).map_err(|e| e.to_string())?;
        let r = http::request(
            "POST",
            &format!("{}/append", self.base),
            Some(("application/json", body)),
            Duration::from_secs(6),
        )?;
        if r.status != 200 {
            return Err(format!("do append -> {}: {}", r.status, String::from_utf8_lossy(&r.body)));
        }
        let v = r.json()?;
        let cursor = v.get("cursor").and_then(|c| c.as_i64()).unwrap_or(0);
        let high = batch
            .iter()
            .filter_map(|e| e["seq"].as_i64())
            .max()
            .unwrap_or(since);
        store.set_meta("do_pushed_seq", &high.to_string())?;
        store.set_meta("do_cursor", &cursor.to_string())?;
        Ok(PushResult { pushed: batch.len(), cursor })
    }

    /// Pull lines the board holds that we have not applied.
    pub fn pull(&self, store: &Store, now: u64, lease_secs: u64) -> Result<PullResult, String> {
        if !self.enabled() {
            return Ok(PullResult { applied: 0, duplicates: 0, rejected: vec![], cursor: 0 });
        }
        let mut cursor: i64 = store
            .meta("do_pull_cursor")?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let mut applied = 0;
        let mut duplicates = 0;
        let mut rejected = Vec::new();
        loop {
            let url = format!("{}/since?cursor={cursor}", self.base);
            let r = http::request("GET", &url, None, Duration::from_secs(6))?;
            if r.status != 200 {
                return Err(format!("do since -> {}", r.status));
            }
            let v = r.json()?;
            let lines = v
                .get("lines")
                .and_then(|l| l.as_array())
                .cloned()
                .unwrap_or_default();
            let next = v.get("cursor").and_then(|c| c.as_i64()).unwrap_or(cursor);
            if lines.is_empty() {
                cursor = next;
                break;
            }
            for line in &lines {
                let text = line.as_str().unwrap_or("");
                match protocol::verify_line(text) {
                    Err(e) => rejected.push(e),
                    Ok(ev) => {
                        if store.event_line(&ev.id)?.is_some() {
                            duplicates += 1;
                            continue;
                        }
                        match store::ingest(store, &ev, now, lease_secs) {
                            Ok(_) => applied += 1,
                            Err(e) => rejected.push(e),
                        }
                    }
                }
            }
            cursor = next;
            if lines.len() < 1 {
                break;
            }
        }
        store.set_meta("do_pull_cursor", &cursor.to_string())?;
        Ok(PullResult { applied, duplicates, rejected, cursor })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_url_is_normalised() {
        assert_eq!(DoSync::new("http://127.0.0.1:8791/").base, "http://127.0.0.1:8791");
        assert!(!DoSync::new("").enabled());
        assert!(DoSync::new("http://127.0.0.1:8791").enabled());
    }
}
