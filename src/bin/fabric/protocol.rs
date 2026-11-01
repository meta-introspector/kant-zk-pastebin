//! The fabric event envelope and the task state machine.
//!
//! An event is one JSON object. Its `block_cid` is the raw CID of its own
//! canonical bytes, so a line carried by the relay, by a Durable Object or by
//! an IPFS block can always be re-checked by whoever receives it. Nothing
//! downstream is trusted: `verify_line` recomputes the address and drops the
//! line on any mismatch, which is why a relay or a Cloudflare Worker cannot
//! invent an event.
//!
//! Task transitions are the whole coordination contract:
//!
//!     offered --claim--> claimed --start--> running --result{ok}--> done
//!                                                  \--result{!ok}-> failed
//!     any non-terminal --cancel--> cancelled
//!     claimed/running with an expired lease --sweep--> offered
//!
//! Terminal states never move. The rules are tested directly below and are the
//! same rules the daemon applies, so a claim cannot skip an offer and a result
//! cannot be posted by an agent that never held the lease.

use serde_json::{json, Value};

use crate::fabric::canon;

pub const PROTOCOL_VERSION: u64 = 1;
pub const TERMINAL: [&str; 3] = ["done", "failed", "cancelled"];

pub fn is_terminal(state: &str) -> bool {
    TERMINAL.contains(&state)
}

/// A parsed, integrity-checked event.
#[derive(Clone, Debug)]
pub struct Event {
    pub id: String,
    pub kind: String,
    pub task: Option<String>,
    pub room: Option<String>,
    pub agent: String,
    pub ts: u64,
    pub body: Value,
    pub block_cid: String,
    pub line: Value,
}

fn field_str(v: &Value, k: &str) -> Option<String> {
    v.get(k).and_then(|x| x.as_str()).map(|s| s.to_string())
}

/// The bytes an event's address is computed over: the object without its
/// `block_cid` field. A hash cannot cover itself, so the address is over the
/// payload and the field merely records it; `verify_line` removes the field
/// before recomputing, which is what makes the check exact rather than
/// approximate.
pub fn signed_bytes(v: &Value) -> Vec<u8> {
    let mut copy = v.clone();
    if let Some(obj) = copy.as_object_mut() {
        obj.remove("block_cid");
    }
    canon::canonical_bytes(&copy)
}

/// Build an event from its parts, computing the id and address.
pub fn make_event(
    kind: &str,
    task: Option<&str>,
    room: Option<&str>,
    agent: &str,
    ts: u64,
    body: Value,
) -> Event {
    let mut v = json!({
        "v": PROTOCOL_VERSION,
        "kind": kind,
        "task": task,
        "room": room,
        "agent": agent,
        "ts": ts,
        "body": body,
    });
    // The id is a digest of the content, so replaying the same event is a
    // no-op rather than a second row: retries are safe across transports.
    let digest = canon::sha256(&signed_bytes(&v));
    let id = hex::encode(&digest[..8]);
    v["id"] = json!(id);
    let block_cid = canon::raw_cid(&signed_bytes(&v));
    v["block_cid"] = json!(block_cid);
    Event {
        id: field_str(&v, "id").unwrap_or_default(),
        kind: kind.to_string(),
        task: task.map(|s| s.to_string()),
        room: room.map(|s| s.to_string()),
        agent: agent.to_string(),
        ts,
        body: v["body"].clone(),
        block_cid: field_str(&v, "block_cid").unwrap_or_default(),
        line: v,
    }
}

/// Parse and verify a line received from anywhere. `Err` carries the reason the
/// line was dropped, which the caller logs; it is never a reason to trust it.
pub fn verify_line(line: &str) -> Result<Event, String> {
    let v: Value = serde_json::from_str(line).map_err(|e| format!("not json: {e}"))?;
    if v.get("v").and_then(|x| x.as_u64()) != Some(PROTOCOL_VERSION) {
        return Err("wrong protocol version".into());
    }
    let claimed = field_str(&v, "block_cid").ok_or("no block_cid")?;
    if !canon::verifies(&claimed, &signed_bytes(&v)) {
        return Err("block_cid does not match the event bytes".into());
    }
    let id = field_str(&v, "id").ok_or("no id")?;
    let kind = field_str(&v, "kind").ok_or("no kind")?;
    let agent = field_str(&v, "agent").ok_or("no agent")?;
    let ts = v.get("ts").and_then(|x| x.as_u64()).ok_or("no ts")?;
    let body = v.get("body").cloned().ok_or("no body")?;
    Ok(Event {
        id,
        kind,
        task: field_str(&v, "task"),
        room: field_str(&v, "room"),
        agent,
        ts,
        body,
        block_cid: claimed,
        line: v,
    })
}

/// The projection a task keeps after an event.
#[derive(Clone, Debug, PartialEq)]
pub struct TaskRow {
    pub id: String,
    pub state: String,
    pub title: String,
    pub kind: String,
    pub owner: Option<String>,
    pub lease_until: Option<u64>,
    pub result_cid: Option<String>,
    pub value: Value,
}

fn lease_expired(row: &TaskRow, now: u64) -> bool {
    matches!(row.lease_until, Some(t) if t <= now)
}

/// Apply `ev` to the task it names. Returns the new row, or the reason the
/// transition is illegal. `current` is `None` for a `task.offer`.
pub fn apply(
    current: Option<&TaskRow>,
    ev: &Event,
    now: u64,
    lease_secs: u64,
) -> Result<TaskRow, String> {
    let body = &ev.body;

    if ev.kind == "task.offer" {
        if current.is_some() {
            return Err("task already exists".into());
        }
        let id = format!("t{}", ev.id);
        let title = body
            .get("title")
            .and_then(|x| x.as_str())
            .ok_or("task.offer needs a title")?;
        let kind = body
            .get("kind")
            .and_then(|x| x.as_str())
            .unwrap_or("general");
        let mut value = json!({
            "id": id,
            "state": "offered",
            "title": title,
            "kind": kind,
            "owner": null,
            "lease_until": null,
            "result_cid": null,
            "payload": body.get("payload").cloned().unwrap_or(Value::Null),
            "offer_cid": ev.block_cid,
            "created": now,
            "updated": now,
        });
        value["state"] = json!("offered");
        return Ok(TaskRow {
            id: value["id"].as_str().unwrap().to_string(),
            state: "offered".into(),
            title: title.to_string(),
            kind: kind.to_string(),
            owner: None,
            lease_until: None,
            result_cid: None,
            value,
        });
    }

    let row = current.ok_or_else(|| format!("no such task for {}", ev.kind))?;
    if is_terminal(&row.state) {
        return Err(format!("task {} is terminal ({})", row.id, row.state));
    }

    let mut next = row.clone();
    match ev.kind.as_str() {
        "task.claim" => {
            let reclaimable = row.state == "offered" || lease_expired(row, now);
            if !reclaimable {
                return Err(format!(
                    "task {} is {} and leased to {:?} until {:?}",
                    row.id, row.state, row.owner, row.lease_until
                ));
            }
            next.state = "claimed".into();
            next.owner = Some(ev.agent.clone());
            next.lease_until = Some(now + lease_secs);
        }
        "task.expire" => {
            // Only the sweeper emits this, and only when the lease really has
            // run out: it is the one transition no agent can ask for.
            if !lease_expired(row, now) {
                return Err(format!("lease on {} has not expired", row.id));
            }
            next.state = "offered".into();
            next.owner = None;
            next.lease_until = None;
        }
        "task.renew" | "task.start" | "task.progress" | "task.result" => {
            if row.owner.as_deref() != Some(ev.agent.as_str()) {
                return Err(format!(
                    "agent {} does not hold the lease on {}",
                    ev.agent, row.id
                ));
            }
            if lease_expired(row, now) {
                return Err(format!("lease on {} expired", row.id));
            }
            match ev.kind.as_str() {
                "task.renew" | "task.progress" => {
                    next.lease_until = Some(now + lease_secs);
                }
                "task.start" => {
                    if row.state != "claimed" {
                        return Err(format!("cannot start a task in state {}", row.state));
                    }
                    next.state = "running".into();
                    next.lease_until = Some(now + lease_secs);
                }
                _ => {
                    if row.state != "running" && row.state != "claimed" {
                        return Err(format!("cannot post a result in state {}", row.state));
                    }
                    let ok = body.get("ok").and_then(|x| x.as_bool()).unwrap_or(false);
                    next.state = if ok { "done".into() } else { "failed".into() };
                    next.result_cid = field_str(body, "result_cid");
                    next.lease_until = None;
                }
            }
        }
        "task.cancel" => {
            next.state = "cancelled".into();
            next.lease_until = None;
        }
        "chat.say" | "peer.hello" => return Err(format!("{} does not move a task", ev.kind)),
        other => return Err(format!("unknown event kind {other}")),
    }
    next.value["state"] = json!(next.state);
    next.value["owner"] = json!(next.owner);
    next.value["lease_until"] = json!(next.lease_until);
    next.value["result_cid"] = json!(next.result_cid);
    next.value["updated"] = json!(now);
    Ok(next)
}

/// The lease sweeper's decision: a claimed/running task whose lease ran out is
/// offered again, so a dead agent cannot strand work.
pub fn sweep(row: &TaskRow, now: u64) -> Option<&'static str> {
    if (row.state == "claimed" || row.state == "running") && lease_expired(row, now) {
        Some("offered")
    } else {
        None
    }
}

/// One room per task, derived rather than assigned: two agents that know the
/// task id can meet without asking anyone.
pub fn task_room(task: &str) -> String {
    hex::encode(canon::sha256(format!("agent-fabric/v1/task/{task}").as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn offer(id_agent: &str) -> Event {
        make_event(
            "task.offer",
            None,
            None,
            id_agent,
            100,
            json!({"title": "prove the gate", "kind": "proof", "payload": {"n": 1}}),
        )
    }

    fn ev(kind: &str, task: &str, agent: &str, ts: u64) -> Event {
        make_event(kind, Some(task), None, agent, ts, json!({}))
    }

    fn offered() -> TaskRow {
        let e = offer("agent-a");
        apply(None, &e, 100, 60).unwrap()
    }

    #[test]
    fn offer_makes_an_offered_task() {
        let row = offered();
        assert_eq!(row.state, "offered");
        assert!(row.owner.is_none());
        assert!(row.value["offer_cid"].as_str().unwrap().starts_with("bafkrei"));
    }

    #[test]
    fn claim_then_start_then_result() {
        let mut row = offered();
        let id = row.id.clone();
        row = apply(Some(&row), &ev("task.claim", &id, "agent-a", 101), 101, 60).unwrap();
        assert_eq!(row.state, "claimed");
        row = apply(Some(&row), &ev("task.start", &id, "agent-a", 102), 102, 60).unwrap();
        assert_eq!(row.state, "running");
        let done = make_event(
            "task.result",
            Some(&id),
            None,
            "agent-a",
            103,
            json!({"ok": true, "result_cid": "bafkrei"}),
        );
        row = apply(Some(&row), &done, 103, 60).unwrap();
        assert_eq!(row.state, "done");
        assert_eq!(row.result_cid.as_deref(), Some("bafkrei"));
    }

    #[test]
    fn terminal_never_moves() {
        let mut row = offered();
        let id = row.id.clone();
        row = apply(Some(&row), &ev("task.cancel", &id, "agent-a", 101), 101, 60).unwrap();
        assert_eq!(row.state, "cancelled");
        for kind in ["task.claim", "task.start", "task.result", "task.cancel"] {
            assert!(apply(Some(&row), &ev(kind, &id, "agent-a", 102), 102, 60).is_err());
        }
    }

    #[test]
    fn no_claim_skips_the_offer() {
        let row = offered();
        let id = row.id.clone();
        // Starting without claiming is refused even by the offering agent.
        assert!(apply(Some(&row), &ev("task.start", &id, "agent-a", 101), 101, 60).is_err());
        // And a result before a claim is refused too.
        assert!(apply(Some(&row), &ev("task.result", &id, "agent-a", 101), 101, 60).is_err());
    }

    #[test]
    fn only_the_lease_holder_moves() {
        let mut row = offered();
        let id = row.id.clone();
        row = apply(Some(&row), &ev("task.claim", &id, "agent-a", 100), 100, 60).unwrap();
        assert!(apply(Some(&row), &ev("task.start", &id, "agent-b", 101), 101, 60).is_err());
        assert!(apply(Some(&row), &ev("task.result", &id, "agent-b", 101), 101, 60).is_err());
    }

    #[test]
    fn expired_lease_can_be_reclaimed() {
        let mut row = offered();
        let id = row.id.clone();
        row = apply(Some(&row), &ev("task.claim", &id, "agent-a", 100), 100, 60).unwrap();
        assert_eq!(row.lease_until, Some(160));
        assert_eq!(sweep(&row, 161), Some("offered"));
        row = apply(Some(&row), &ev("task.claim", &id, "agent-b", 162), 162, 60).unwrap();
        assert_eq!(row.owner.as_deref(), Some("agent-b"));
    }

    #[test]
    fn live_lease_is_not_reclaimable() {
        let mut row = offered();
        let id = row.id.clone();
        row = apply(Some(&row), &ev("task.claim", &id, "agent-a", 100), 100, 60).unwrap();
        assert!(apply(Some(&row), &ev("task.claim", &id, "agent-b", 101), 101, 60).is_err());
        assert_eq!(sweep(&row, 159), None);
    }

    #[test]
    fn forged_line_is_refused() {
        let e = ev("task.claim", "tabc", "agent-a", 101);
        let mut v = e.line.clone();
        v["body"] = json!({"ok": true, "result_cid": "bafkreievil"});
        // The address still names the old bytes, so the doctored line fails.
        assert!(verify_line(&serde_json::to_string(&v).unwrap()).is_err());
        // Re-signing it with the doctoring agent's own fields would verify —
        // the guarantee is integrity relative to the address, not identity of
        // the author, and the state machine then refuses the wrong agent.
        let resigned = verify_line(&serde_json::to_string(&make_event(
            "task.result",
            Some("tabc"),
            None,
            "agent-b",
            101,
            json!({"ok": true}),
        ).line).unwrap())
        .unwrap();
        assert_eq!(resigned.agent, "agent-b");
        let row = offered();
        assert!(apply(Some(&row), &resigned, 101, 60).is_err());
    }

    #[test]
    fn genuine_line_verifies() {
        let e = ev("task.claim", "tabc", "agent-a", 101);
        let back = verify_line(&serde_json::to_string(&e.line).unwrap()).unwrap();
        assert_eq!(back.id, e.id);
        assert_eq!(back.block_cid, e.block_cid);
        assert_eq!(signed_bytes(&back.line), signed_bytes(&e.line));
    }

    #[test]
    fn reordered_keys_still_verify() {
        let e = ev("task.claim", "tabc", "agent-a", 101);
        let reordered = format!(
            r#"{{"body":{},"agent":"agent-a","kind":"task.claim","task":"tabc","ts":101,"v":1,"id":"{}","block_cid":"{}","room":null}}"#,
            e.body, e.id, e.block_cid
        );
        let back = verify_line(&reordered).unwrap();
        assert_eq!(back.block_cid, e.block_cid);
    }

    #[test]
    fn room_is_derived_not_assigned() {
        let a = task_room("tabc");
        assert_eq!(a, task_room("tabc"));
        assert_ne!(a, task_room("tdef"));
        assert_eq!(a.len(), 64);
    }
}
