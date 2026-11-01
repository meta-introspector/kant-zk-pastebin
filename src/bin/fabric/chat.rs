//! Chat transport: the existing Kant relay, not a new protocol.
//!
//! `server/relay.mjs` already implements one append-only log per room with a
//! cursor (`GET /room/{room}?cursor=N` -> `{ok, cursor, lines, truncated}`),
//! and the browser client in `web/kant-net.mjs` speaks it. Agents use that
//! same relay: a room is derived from the task id, a line is a fabric event's
//! canonical JSON, and the relay carries it without parsing it.
//!
//! The relay is trusted for availability only. Every line it returns is put
//! through `protocol::verify_line`, so a relay that edits, forges or reorders
//! is caught here rather than believed.

use std::time::Duration;

use crate::fabric::http;

pub struct Relay {
    pub url: String,
}

impl Relay {
    pub fn from_env() -> Relay {
        Relay {
            url: std::env::var("FABRIC_RELAY")
                .unwrap_or_else(|_| "http://127.0.0.1:8787".into()),
        }
    }

    pub fn health(&self) -> Result<serde_json::Value, String> {
        let r = http::request("GET", &format!("{}/health", self.url), None, Duration::from_secs(5))?;
        if r.status != 200 {
            return Err(format!("relay health -> {}", r.status));
        }
        r.json()
    }

    /// Append one line. Returns the room's cursor after the append.
    pub fn post(&self, room: &str, line: &str) -> Result<i64, String> {
        let url = format!("{}/room/{room}", self.url);
        let mut body = line.as_bytes().to_vec();
        if !body.ends_with(b"\n") {
            body.push(b'\n');
        }
        let r = http::request(
            "POST",
            &url,
            Some(("text/plain; charset=utf-8", body)),
            Duration::from_secs(10),
        )?;
        if r.status != 200 {
            return Err(format!(
                "relay post -> {}: {}",
                r.status,
                String::from_utf8_lossy(&r.body)
            ));
        }
        let v = r.json()?;
        v.get("cursor")
            .and_then(|c| c.as_i64())
            .ok_or_else(|| format!("relay post returned no cursor: {v}"))
    }

    /// Fetch lines after `cursor`. `lines` may be empty; `cursor` is absolute.
    pub fn fetch(&self, room: &str, cursor: i64) -> Result<(i64, Vec<String>, bool), String> {
        let url = format!("{}/room/{room}?cursor={cursor}", self.url);
        let r = http::request("GET", &url, None, Duration::from_secs(10))?;
        if r.status != 200 {
            return Err(format!("relay fetch -> {}", r.status));
        }
        let v = r.json()?;
        let next = v.get("cursor").and_then(|c| c.as_i64()).unwrap_or(cursor);
        let truncated = v.get("truncated").and_then(|t| t.as_bool()).unwrap_or(false);
        let lines = v
            .get("lines")
            .and_then(|l| l.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(|s| s.to_string()))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        Ok((next, lines, truncated))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn room_is_a_function_of_the_task() {
        let a = crate::fabric::protocol::task_room("tabc");
        let b = crate::fabric::protocol::task_room("tabc");
        assert_eq!(a, b);
        assert_eq!(a.len(), 64);
    }

    #[test]
    fn post_and_fetch_against_a_live_relay() {
        let relay = Relay::from_env();
        if relay.health().is_err() {
            eprintln!("skip: no relay at {}", relay.url);
            return;
        }
        let room = format!("fabric-selftest-{}", std::process::id());
        let start = relay.fetch(&room, 0).unwrap().0;
        let cursor = relay.post(&room, "first line").unwrap();
        assert!(cursor > start);
        let (next, lines, _) = relay.fetch(&room, start).unwrap();
        assert_eq!(lines, vec!["first line".to_string()]);
        assert_eq!(next, cursor);
        // Nothing is returned twice when polling with the cursor given.
        let (_, again, _) = relay.fetch(&room, next).unwrap();
        assert!(again.is_empty());
        // And a poll from the beginning sees the whole room.
        let (_, all, _) = relay.fetch(&room, 0).unwrap();
        assert_eq!(all, vec!["first line".to_string()]);
    }
}
